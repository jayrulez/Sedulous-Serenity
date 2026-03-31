#pragma pack_matrix(row_major)

// Irradiance convolution — convolves an equirectangular HDRI into a cubemap
// by integrating over the hemisphere weighted by cosine (diffuse).
// Dispatched once with face index as push constant or cbuffer.

static const float PI = 3.14159265359;

// Push constants on Vulkan, root constants on DX12.
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

// Convert cubemap face + UV to world direction
float3 CubeFaceDirection(uint face, float2 uv)
{
	// uv in [-1, 1]
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

// Convert world direction to equirectangular UV
float2 DirectionToEquirect(float3 dir)
{
	float2 uv;
	uv.x = atan2(dir.z, dir.x) / (2.0 * PI) + 0.5;
	uv.y = 1.0 - (asin(clamp(dir.y, -1.0, 1.0)) / PI + 0.5);
	return uv;
}

[numthreads(8, 8, 1)]
void CSMain(uint3 dispatchID : SV_DispatchThreadID)
{
	if (dispatchID.x >= PC.CubemapSize || dispatchID.y >= PC.CubemapSize)
		return;

	// Map texel to [-1, 1] UV on this face
	float2 uv = (float2(dispatchID.xy) + 0.5) / float(PC.CubemapSize) * 2.0 - 1.0;
	float3 N = CubeFaceDirection(PC.FaceIndex, uv);

	// Build tangent frame around N
	float3 up = abs(N.y) < 0.999 ? float3(0, 1, 0) : float3(1, 0, 0);
	float3 right = normalize(cross(up, N));
	up = cross(N, right);

	// Cosine-weighted hemisphere integration
	float3 irradiance = float3(0, 0, 0);
	float sampleCount = 0;

	// Uniform sampling over hemisphere
	static const float SAMPLE_DELTA = 0.025;
	for (float phi = 0.0; phi < 2.0 * PI; phi += SAMPLE_DELTA)
	{
		for (float theta = 0.0; theta < 0.5 * PI; theta += SAMPLE_DELTA)
		{
			// Spherical to cartesian (tangent space)
			float3 tangentSample = float3(
				sin(theta) * cos(phi),
				sin(theta) * sin(phi),
				cos(theta));

			// Tangent to world
			float3 sampleDir = tangentSample.x * right + tangentSample.y * up + tangentSample.z * N;

			float2 hdriUV = DirectionToEquirect(sampleDir);
			float3 sampleColor = HdriTexture.SampleLevel(LinearSampler, hdriUV, 0).rgb;

			irradiance += sampleColor * cos(theta) * sin(theta);
			sampleCount += 1.0;
		}
	}

	irradiance = PI * irradiance / sampleCount;

	OutputCubemap[uint3(dispatchID.xy, PC.FaceIndex)] = half4(half3(irradiance), (half)1.0);
}
