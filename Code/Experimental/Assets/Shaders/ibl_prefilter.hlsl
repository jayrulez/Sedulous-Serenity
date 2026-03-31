#pragma pack_matrix(row_major)

// Prefiltered environment map — importance-samples GGX for specular IBL.
// Each mip level corresponds to a roughness value.
// Dispatched per face per mip level.

static const float PI = 3.14159265359;
static const uint NUM_SAMPLES = 1024;

struct IBLParamsType
{
	uint FaceIndex;
	uint CubemapSize;
	float Roughness;
	float _pad;
};

// Push constants on Vulkan, root constants on DX12 (space1 = after 1 bind group).
[[vk::push_constant]] ConstantBuffer<IBLParamsType> PC : register(b0, space1);

Texture2D HdriTexture : register(t0);
SamplerState LinearSampler : register(s1);
RWTexture2DArray<half4> OutputCubemap : register(u2);

float3 CubeFaceDirection(uint face, float2 uv)
{
	float u = uv.x;
	float v = uv.y;

	switch (face)
	{
	case 0: return normalize(float3( 1, -v, -u)); // +X
	case 1: return normalize(float3(-1, -v,  u)); // -X
	case 2: return normalize(float3( u,  1,  v)); // +Y
	case 3: return normalize(float3( u, -1, -v)); // -Y
	case 4: return normalize(float3( u, -v,  1)); // +Z
	case 5: return normalize(float3(-u, -v, -1)); // -Z
	default: return float3(0, 0, 1);
	}
}

float2 DirectionToEquirect(float3 dir)
{
	float2 uv;
	uv.x = atan2(dir.z, dir.x) / (2.0 * PI) + 0.5;
	uv.y = 1.0 - (asin(clamp(dir.y, -1.0, 1.0)) / PI + 0.5);
	return uv;
}

// Hammersley quasi-random sequence
float RadicalInverseVdC(uint bits)
{
	bits = (bits << 16u) | (bits >> 16u);
	bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);
	bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);
	bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);
	bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);
	return float(bits) * 2.3283064365386963e-10;
}

float2 Hammersley(uint i, uint N)
{
	return float2(float(i) / float(N), RadicalInverseVdC(i));
}

// GGX importance sampling
float3 ImportanceSampleGGX(float2 Xi, float3 N, float roughness)
{
	float a = roughness * roughness;
	float a2 = a * a;

	float phi = 2.0 * PI * Xi.x;
	float cosTheta = sqrt((1.0 - Xi.y) / (1.0 + (a2 - 1.0) * Xi.y));
	float sinTheta = sqrt(1.0 - cosTheta * cosTheta);

	// Spherical to cartesian (tangent space)
	float3 H;
	H.x = cos(phi) * sinTheta;
	H.y = sin(phi) * sinTheta;
	H.z = cosTheta;

	// Tangent to world
	float3 up = abs(N.y) < 0.999 ? float3(0, 1, 0) : float3(1, 0, 0);
	float3 right = normalize(cross(up, N));
	up = cross(N, right);

	return normalize(right * H.x + up * H.y + N * H.z);
}

[numthreads(8, 8, 1)]
void CSMain(uint3 dispatchID : SV_DispatchThreadID)
{
	if (dispatchID.x >= PC.CubemapSize || dispatchID.y >= PC.CubemapSize)
		return;

	float2 uv = (float2(dispatchID.xy) + 0.5) / float(PC.CubemapSize) * 2.0 - 1.0;
	float3 N = CubeFaceDirection(PC.FaceIndex, uv);
	float3 V = N; // Assume V = N for prefiltering (split-sum approximation)

	float3 prefilteredColor = float3(0, 0, 0);
	float totalWeight = 0.0;

	for (uint i = 0; i < NUM_SAMPLES; i++)
	{
		float2 Xi = Hammersley(i, NUM_SAMPLES);
		float3 H = ImportanceSampleGGX(Xi, N, PC.Roughness);
		float3 L = normalize(2.0 * dot(V, H) * H - V);

		float NdotL = max(dot(N, L), 0.0);
		if (NdotL > 0.0)
		{
			float2 hdriUV = DirectionToEquirect(L);
			prefilteredColor += HdriTexture.SampleLevel(LinearSampler, hdriUV, 0).rgb * NdotL;
			totalWeight += NdotL;
		}
	}

	prefilteredColor /= max(totalWeight, 0.001);

	OutputCubemap[uint3(dispatchID.xy, PC.FaceIndex)] = half4(half3(prefilteredColor), (half)1.0);
}
