// Equirectangular Panorama to Cubemap Conversion Compute Shader
// Converts a 2D equirectangular HDR image to a 6-face cubemap
#pragma pack_matrix(row_major)

Texture2D EquirectMap : register(t0);
SamplerState LinearSampler : register(s0);
RWTexture2DArray<float4> OutputCubemap : register(u0);

cbuffer Params : register(b0)
{
    uint Resolution;
    uint _pad0;
    uint _pad1;
    uint _pad2;
};

// Cubemap face order: 0=+X, 1=-X, 2=+Y, 3=-Y, 4=+Z, 5=-Z
float3 CubemapTexelDirection(uint face, uint x, uint y, uint resolution)
{
    float u = ((float)x + 0.5) / (float)resolution * 2.0 - 1.0;
    float v = ((float)y + 0.5) / (float)resolution * 2.0 - 1.0;

    float3 dir;
    switch (face)
    {
    case 0: dir = float3( 1.0, -v, -u); break; // +X
    case 1: dir = float3(-1.0, -v,  u); break; // -X
    case 2: dir = float3( u,  1.0,  v); break; // +Y
    case 3: dir = float3( u, -1.0, -v); break; // -Y
    case 4: dir = float3( u, -v,  1.0); break; // +Z
    default: dir = float3(-u, -v, -1.0); break; // -Z
    }
    return normalize(dir);
}

static const float PI = 3.14159265358979323846;

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    if (id.x >= Resolution || id.y >= Resolution || id.z >= 6)
        return;

    float3 dir = CubemapTexelDirection(id.z, id.x, id.y, Resolution);

    // Direction to equirectangular UV
    // u = atan2(z, x) / (2*PI) + 0.5  (longitude)
    // v = asin(y) / PI + 0.5          (latitude, 0=top, 1=bottom)
    float2 uv;
    uv.x = atan2(dir.z, dir.x) / (2.0 * PI) + 0.5;
    uv.y = -asin(dir.y) / PI + 0.5; // Negate Y: equirect top = +Y

    float4 color = EquirectMap.SampleLevel(LinearSampler, uv, 0);
    OutputCubemap[uint3(id.x, id.y, id.z)] = color;
}
