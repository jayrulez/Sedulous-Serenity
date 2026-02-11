// IBL Prefiltered Environment Map Compute Shader
// Convolves an environment cubemap into a specular prefiltered cubemap
// using GGX importance sampling. Called once per mip level.
#pragma pack_matrix(row_major)

TextureCube EnvironmentMap : register(t0);
SamplerState LinearSampler : register(s0);
RWTexture2DArray<float4> OutputPrefiltered : register(u0);

cbuffer Params : register(b0)
{
    uint Resolution;
    float Roughness;
    uint _pad0;
    uint _pad1;
};

static const uint NUM_SAMPLES = 256;
static const float PI = 3.14159265358979323846;

// Cubemap face order: 0=+X, 1=-X, 2=+Y, 3=-Y, 4=+Z, 5=-Z
float3 CubemapTexelDirection(uint face, uint x, uint y, uint resolution)
{
    float u = ((float)x + 0.5) / (float)resolution * 2.0 - 1.0;
    float v = ((float)y + 0.5) / (float)resolution * 2.0 - 1.0;

    float3 dir;
    switch (face)
    {
    case 0: dir = float3( 1.0, -v, -u); break;
    case 1: dir = float3(-1.0, -v,  u); break;
    case 2: dir = float3( u,  1.0,  v); break;
    case 3: dir = float3( u, -1.0, -v); break;
    case 4: dir = float3( u, -v,  1.0); break;
    default: dir = float3(-u, -v, -1.0); break;
    }
    return normalize(dir);
}

void BuildTangentBasis(float3 N, out float3 T, out float3 B)
{
    float3 up = abs(N.y) < 0.999 ? float3(0, 1, 0) : float3(1, 0, 0);
    T = normalize(cross(up, N));
    B = cross(N, T);
}

// Hammersley quasi-random sequence
float RadicalInverseVdC(uint bits)
{
    bits = (bits << 16u) | (bits >> 16u);
    bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);
    bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);
    bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);
    bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);
    return (float)bits * 2.3283064365386963e-10;
}

// GGX importance sampling — returns half-vector in tangent space (Z-up)
float3 ImportanceSampleGGX(float xi1, float xi2, float roughness)
{
    float a = roughness * roughness;
    float phi = 2.0 * PI * xi1;
    float cosTheta = sqrt((1.0 - xi2) / (1.0 + (a * a - 1.0) * xi2));
    float sinTheta = sqrt(1.0 - cosTheta * cosTheta);

    return float3(cos(phi) * sinTheta, sin(phi) * sinTheta, cosTheta);
}

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    if (id.x >= Resolution || id.y >= Resolution || id.z >= 6)
        return;

    float3 N = CubemapTexelDirection(id.z, id.x, id.y, Resolution);
    float3 R = N;
    float3 V = R;

    float3 T, B;
    BuildTangentBasis(N, T, B);

    float3 prefilteredColor = float3(0, 0, 0);
    float totalWeight = 0.0;

    // Clamp roughness to avoid division issues at roughness=0
    float r = max(Roughness, 0.001);

    for (uint i = 0; i < NUM_SAMPLES; i++)
    {
        // Hammersley sequence
        float xi1 = (float)i / (float)NUM_SAMPLES;
        float xi2 = RadicalInverseVdC(i);

        // Importance sample GGX in tangent space
        float3 H_ts = ImportanceSampleGGX(xi1, xi2, r);

        // Transform to world space
        float3 H = T * H_ts.x + B * H_ts.y + N * H_ts.z;

        // Reflect V around H to get light direction
        float3 L = 2.0 * dot(V, H) * H - V;

        float NdotL = max(dot(N, L), 0.0);
        if (NdotL > 0.0)
        {
            prefilteredColor += EnvironmentMap.SampleLevel(LinearSampler, L, 0).rgb * NdotL;
            totalWeight += NdotL;
        }
    }

    if (totalWeight > 0.0)
        prefilteredColor /= totalWeight;

    OutputPrefiltered[uint3(id.x, id.y, id.z)] = float4(prefilteredColor, 1.0);
}
