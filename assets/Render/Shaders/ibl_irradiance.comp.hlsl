// IBL Irradiance Map Compute Shader
// Convolves an environment cubemap into a diffuse irradiance cubemap
// using cosine-weighted hemisphere sampling.
#pragma pack_matrix(row_major)

TextureCube EnvironmentMap : register(t0);
SamplerState LinearSampler : register(s0);
RWTexture2DArray<float4> OutputIrradiance : register(u0);

static const uint IRRADIANCE_SIZE = 32;
static const uint NUM_AZIMUTHAL = 64;
static const uint NUM_ELEVATION = 16;
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

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    if (id.x >= IRRADIANCE_SIZE || id.y >= IRRADIANCE_SIZE || id.z >= 6)
        return;

    float3 N = CubemapTexelDirection(id.z, id.x, id.y, IRRADIANCE_SIZE);

    float3 T, B;
    BuildTangentBasis(N, T, B);

    // Cosine-weighted hemisphere convolution
    float3 irradiance = float3(0, 0, 0);

    for (uint ei = 0; ei < NUM_ELEVATION; ei++)
    {
        float theta = PI * 0.5 * ((float)ei + 0.5) / (float)NUM_ELEVATION;
        float cosTheta = cos(theta);
        float sinTheta = sin(theta);

        for (uint ai = 0; ai < NUM_AZIMUTHAL; ai++)
        {
            float phi = 2.0 * PI * (float)ai / (float)NUM_AZIMUTHAL;

            // Sample direction in tangent space
            float3 tsSample = float3(cos(phi) * sinTheta, sin(phi) * sinTheta, cosTheta);

            // Transform to world space
            float3 sampleDir = T * tsSample.x + B * tsSample.y + N * tsSample.z;

            float3 skyColor = EnvironmentMap.SampleLevel(LinearSampler, sampleDir, 0).rgb;
            irradiance += skyColor * cosTheta * sinTheta;
        }
    }

    irradiance *= PI / (float)(NUM_AZIMUTHAL * NUM_ELEVATION);

    OutputIrradiance[uint3(id.x, id.y, id.z)] = float4(irradiance, 1.0);
}
