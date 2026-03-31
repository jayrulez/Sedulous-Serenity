#pragma pack_matrix(row_major)

#define CLUSTER_X 16
#define CLUSTER_Y 9
#define CLUSTER_Z 24
#define TOTAL_CLUSTERS (CLUSTER_X * CLUSTER_Y * CLUSTER_Z)
#define MAX_LIGHTS_PER_CLUSTER 128

// === Bindings (compute bind group at index 0) ===

cbuffer SceneUniforms : register(b0, space0)
{
	float4x4 ViewMatrix;
	float4x4 ProjectionMatrix;
	float4x4 ViewProjectionMatrix;
	float4x4 InverseViewMatrix;
	float4x4 InverseProjectionMatrix;
	float4x4 PrevViewProjectionMatrix;
	float3 CameraPosition; float Time;
	float3 CameraForward;  float DeltaTime;
	float2 ScreenSize;     float NearPlane; float FarPlane;
	uint FrameNumber;      uint LightCount; uint ShadowCascadeCount; float _scenePad;
};

struct GPULightData
{
	float4 PositionAndRange;
	float4 DirectionAndSpotInner;
	float4 ColorAndIntensity;
	uint   Type;
	float  SpotOuterAngle;
	float  AreaWidth;
	float  AreaHeight;
	uint   ShadowIndex;
	uint   Flags;
	float2 _pad;
};

struct ClusterData
{
	uint offset;
	uint count;
};

StructuredBuffer<GPULightData>  LightBuffer    : register(t1, space0);
RWStructuredBuffer<ClusterData> ClusterGrid    : register(u2, space0);
RWStructuredBuffer<uint>        LightIndexList : register(u3, space0);
RWByteAddressBuffer             GlobalCounter  : register(u4, space0);

// Exponential depth slice boundary
float ClusterDepth(uint z)
{
	return NearPlane * pow(FarPlane / NearPlane, float(z) / float(CLUSTER_Z));
}

// Unproject NDC xy at a given view-space depth using the inverse projection
float3 ScreenToView(float2 ndc, float viewZ)
{
	float4 clip = float4(ndc, 0.5, 1.0);
	float4 view = mul(clip, InverseProjectionMatrix);
	view.xyz /= view.w;
	return view.xyz * (viewZ / view.z);
}

// Compute view-space AABB for a cluster
void GetClusterAABB(uint3 idx, out float3 aabbMin, out float3 aabbMax)
{
	// Negate to match RH view space (visible objects at negative Z).
	// ClusterDepth returns positive distances; light positions from
	// ViewMatrix have negative Z. AABB must be in the same space.
	float nearZ = -ClusterDepth(idx.z);
	float farZ  = -ClusterDepth(idx.z + 1);

	// NDC corners for this tile [-1,1]
	float2 tileMin = float2(idx.xy) / float2(CLUSTER_X, CLUSTER_Y) * 2.0 - 1.0;
	float2 tileMax = float2(idx.xy + 1) / float2(CLUSTER_X, CLUSTER_Y) * 2.0 - 1.0;
	// Flip Y (NDC Y is up, screen Y is down)
	tileMin.y = -tileMin.y;
	tileMax.y = -tileMax.y;

	// 8 corners: 4 at near depth, 4 at far depth
	float3 corners[8];
	corners[0] = ScreenToView(float2(tileMin.x, tileMin.y), nearZ);
	corners[1] = ScreenToView(float2(tileMax.x, tileMin.y), nearZ);
	corners[2] = ScreenToView(float2(tileMin.x, tileMax.y), nearZ);
	corners[3] = ScreenToView(float2(tileMax.x, tileMax.y), nearZ);
	corners[4] = ScreenToView(float2(tileMin.x, tileMin.y), farZ);
	corners[5] = ScreenToView(float2(tileMax.x, tileMin.y), farZ);
	corners[6] = ScreenToView(float2(tileMin.x, tileMax.y), farZ);
	corners[7] = ScreenToView(float2(tileMax.x, tileMax.y), farZ);

	aabbMin = corners[0];
	aabbMax = corners[0];
	[unroll]
	for (uint i = 1; i < 8; i++)
	{
		aabbMin = min(aabbMin, corners[i]);
		aabbMax = max(aabbMax, corners[i]);
	}
}

bool SphereAABBIntersect(float3 center, float radius, float3 aabbMin, float3 aabbMax)
{
	float3 closest = clamp(center, aabbMin, aabbMax);
	float3 d = center - closest;
	return dot(d, d) <= (radius * radius);
}

[numthreads(64, 1, 1)]
void CSMain(uint3 dtid : SV_DispatchThreadID)
{
	uint clusterIndex = dtid.x;
	if (clusterIndex >= TOTAL_CLUSTERS)
		return;

	// Decompose flat index to 3D
	uint3 clusterIdx;
	clusterIdx.x = clusterIndex % CLUSTER_X;
	clusterIdx.y = (clusterIndex / CLUSTER_X) % CLUSTER_Y;
	clusterIdx.z = clusterIndex / (CLUSTER_X * CLUSTER_Y);

	float3 aabbMin, aabbMax;
	GetClusterAABB(clusterIdx, aabbMin, aabbMax);

	// Cull lights against this cluster
	uint localCount = 0;
	uint localIndices[MAX_LIGHTS_PER_CLUSTER];

	for (uint i = 0; i < LightCount && localCount < MAX_LIGHTS_PER_CLUSTER; i++)
	{
		GPULightData light = LightBuffer[i];

		if (light.Type == 0) // Directional: affects all clusters
		{
			localIndices[localCount++] = i;
			continue;
		}

		// Transform light position to view space for AABB test
		float3 lightPosView = mul(float4(light.PositionAndRange.xyz, 1.0), ViewMatrix).xyz;
		float lightRange = light.PositionAndRange.w;

		if (SphereAABBIntersect(lightPosView, lightRange, aabbMin, aabbMax))
		{
			localIndices[localCount++] = i;
		}
	}

	// Allocate from global light index list
	uint globalOffset = 0;
	if (localCount > 0)
		GlobalCounter.InterlockedAdd(0, localCount, globalOffset);

	// Write light indices to the global list
	for (uint i = 0; i < localCount; i++)
		LightIndexList[globalOffset + i] = localIndices[i];

	// Write cluster metadata
	ClusterGrid[clusterIndex].offset = globalOffset;
	ClusterGrid[clusterIndex].count = localCount;
}
