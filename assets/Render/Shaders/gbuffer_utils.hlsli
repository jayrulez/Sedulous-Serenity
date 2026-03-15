// GBuffer utilities: octahedral normal encoding/decoding and GBuffer pack/unpack.
// Used by forward.frag.hlsl (encode) and screen-space effects (decode).
// GBuffer format: RGBA8Unorm — octahedral view-space normal (RG), roughness (B), metallic (A).

#ifndef GBUFFER_UTILS_HLSLI
#define GBUFFER_UTILS_HLSLI

// Octahedral encoding: maps unit normal -> [0,1]^2 (2 channels)
float2 OctahedralEncode(float3 n)
{
    n /= (abs(n.x) + abs(n.y) + abs(n.z));
    if (n.z < 0.0)
        n.xy = (1.0 - abs(n.yx)) * select(n.xy >= 0., 1., -1.);
    return n.xy * 0.5 + 0.5;
}

// Octahedral decode: maps [0,1]^2 -> unit normal
float3 OctahedralDecode(float2 f)
{
    f = f * 2.0 - 1.0;
    float3 n = float3(f.x, f.y, 1.0 - abs(f.x) - abs(f.y));
    if (n.z < 0.0)
        n.xy = (1.0 - abs(n.yx)) * select(n.xy >= 0., 1., -1.);
    return normalize(n);
}

// Pack GBuffer: view-space normal + roughness + metallic -> RGBA8
float4 PackGBuffer(float3 viewNormal, float roughness, float metallic)
{
    float2 octNorm = OctahedralEncode(viewNormal);
    return float4(octNorm, roughness, metallic);
}

// Unpack GBuffer: RGBA8 -> view-space normal, roughness, metallic
void UnpackGBuffer(float4 gbuffer, out float3 viewNormal, out float roughness, out float metallic)
{
    viewNormal = OctahedralDecode(gbuffer.rg);
    roughness = gbuffer.b;
    metallic = gbuffer.a;
}

#endif // GBUFFER_UTILS_HLSLI
