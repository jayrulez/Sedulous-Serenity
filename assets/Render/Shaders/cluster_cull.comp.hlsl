// Cluster Light Culling Compute Shader
// Assigns lights to clusters based on sphere-AABB intersection

// Cluster grid parameters
cbuffer ClusterUniforms : register(b0)
{
    uint ClustersX;
    uint ClustersY;
    uint ClustersZ;
    uint _Padding0;

    float ScreenWidth;
    float ScreenHeight;
    float NearPlane;
    float FarPlane;

    float LogDepthScale;
    float LogDepthBias;
    float TileSizeX;
    float TileSizeY;
};

// Lighting uniforms
cbuffer LightingUniforms : register(b1)
{
    float3 AmbientColor;
    uint LightCount;

    float EnvironmentIntensity;
    float Exposure;
    float2 _LightPadding;
};

// Light data structure (matches GPULight in Beef)
struct Light
{
    float3 Position;
    float Range;

    float3 Direction;
    float SpotAngleCos;

    float3 Color;
    float Intensity;

    uint Type; // 0=Directional, 1=Point, 2=Spot, 3=Area
    int ShadowIndex;
    float2 _Padding;
};

// Cluster AABB structure
struct ClusterAABB
{
    float3 Min;
    float3 Max;
};

// Per-cluster light info
struct ClusterLightInfo
{
    uint Offset;
    uint Count;
};

// Input buffers (read-only)
StructuredBuffer<ClusterAABB> ClusterAABBs : register(t0);
StructuredBuffer<Light> Lights : register(t1);

// Output buffers
RWStructuredBuffer<ClusterLightInfo> ClusterLightInfos : register(u0);
RWStructuredBuffer<uint> LightIndices : register(u1);

// Atomic counter for global light index allocation
RWStructuredBuffer<uint> GlobalLightIndexCounter : register(u2);

// Shared memory for light indices within workgroup
#define MAX_LIGHTS_PER_CLUSTER 256
groupshared uint SharedLightCount;
groupshared uint SharedLightIndices[MAX_LIGHTS_PER_CLUSTER];
groupshared uint SharedGlobalOffset;

// Test if a sphere intersects an AABB
bool SphereIntersectsAABB(float3 center, float radius, float3 aabbMin, float3 aabbMax)
{
    // Find closest point on AABB to sphere center
    float3 closest = clamp(center, aabbMin, aabbMax);

    // Check if that point is within the sphere
    float3 diff = center - closest;
    float distSq = dot(diff, diff);

    return distSq <= (radius * radius);
}

// Test if a cone (spot light) intersects an AABB
bool ConeIntersectsAABB(float3 apex, float3 direction, float range, float cosAngle, float3 aabbMin, float3 aabbMax)
{
    // Approximate with sphere test for now
    // A more accurate test would check cone-box intersection
    float3 coneCenter = apex + direction * (range * 0.5);
    float coneRadius = range * 0.5 / max(cosAngle, 0.001);

    return SphereIntersectsAABB(coneCenter, coneRadius, aabbMin, aabbMax);
}

// Test if a light affects a cluster
bool LightAffectsCluster(Light light, ClusterAABB cluster)
{
    // Directional lights affect all clusters
    if (light.Type == 0) // Directional
        return true;

    // Point light - sphere test
    if (light.Type == 1) // Point
    {
        return SphereIntersectsAABB(light.Position, light.Range, cluster.Min, cluster.Max);
    }

    // Spot light - cone test (approximated)
    if (light.Type == 2) // Spot
    {
        return ConeIntersectsAABB(light.Position, light.Direction, light.Range, light.SpotAngleCos, cluster.Min, cluster.Max);
    }

    // Area light - sphere approximation
    if (light.Type == 3) // Area
    {
        return SphereIntersectsAABB(light.Position, light.Range, cluster.Min, cluster.Max);
    }

    return false;
}

// Get linear cluster index from 3D coordinates
uint GetClusterIndex(uint3 clusterCoord)
{
    return clusterCoord.x + clusterCoord.y * ClustersX + clusterCoord.z * ClustersX * ClustersY;
}

[numthreads(1, 1, 1)]
void main(uint3 groupId : SV_GroupID, uint3 groupThreadId : SV_GroupThreadID, uint3 dispatchThreadId : SV_DispatchThreadID)
{
    uint clusterIndex = GetClusterIndex(dispatchThreadId);
    uint totalClusters = ClustersX * ClustersY * ClustersZ;

    if (clusterIndex >= totalClusters)
        return;

    // Initialize shared memory
    if (groupThreadId.x == 0 && groupThreadId.y == 0 && groupThreadId.z == 0)
    {
        SharedLightCount = 0;
    }
    GroupMemoryBarrierWithGroupSync();

    // Get cluster AABB
    ClusterAABB cluster = ClusterAABBs[clusterIndex];

    // Test each light against this cluster
    for (uint i = 0; i < LightCount && SharedLightCount < MAX_LIGHTS_PER_CLUSTER; i++)
    {
        Light light = Lights[i];

        if (LightAffectsCluster(light, cluster))
        {
            uint index;
            InterlockedAdd(SharedLightCount, 1, index);
            if (index < MAX_LIGHTS_PER_CLUSTER)
            {
                SharedLightIndices[index] = i;
            }
        }
    }

    GroupMemoryBarrierWithGroupSync();

    // Allocate space in global light index buffer
    if (groupThreadId.x == 0 && groupThreadId.y == 0 && groupThreadId.z == 0)
    {
        uint lightCount = min(SharedLightCount, MAX_LIGHTS_PER_CLUSTER);
        if (lightCount > 0)
        {
            InterlockedAdd(GlobalLightIndexCounter[0], lightCount, SharedGlobalOffset);
        }
        else
        {
            SharedGlobalOffset = 0;
        }
    }

    GroupMemoryBarrierWithGroupSync();

    // Write cluster info
    uint lightCount = min(SharedLightCount, MAX_LIGHTS_PER_CLUSTER);
    ClusterLightInfos[clusterIndex].Offset = SharedGlobalOffset;
    ClusterLightInfos[clusterIndex].Count = lightCount;

    // Copy light indices to global buffer
    for (uint j = 0; j < lightCount; j++)
    {
        LightIndices[SharedGlobalOffset + j] = SharedLightIndices[j];
    }
}
