// Unlit Fragment Shader
// Simple color output without lighting calculations
#pragma pack_matrix(row_major)

// Material uniforms (space1 = descriptor set 1 for materials)
// Simplified layout - only properties needed for unlit rendering
// Layout (std140): BaseColor(0), EmissiveColor(16), AlphaCutoff(32), pad(36-48)
cbuffer MaterialUniforms : register(b0, space1)
{
    float4 BaseColor;      // offset 0
    float4 EmissiveColor;  // offset 16
    float AlphaCutoff;     // offset 32
    float3 _Padding;       // offset 36 (cbuffer size rounds to 48)
};

// Material textures (space1 = descriptor set 1 for materials)
Texture2D AlbedoTexture : register(t0, space1);

// Material sampler (space1 = descriptor set 1 for materials)
SamplerState LinearSampler : register(s0, space1);

struct FragmentInput
{
    float4 Position : SV_Position;
    float2 TexCoord : TEXCOORD0;
#ifdef VERTEX_COLORS
    float4 Color : TEXCOORD1;
#endif
};

float4 main(FragmentInput input) : SV_Target
{
    // Sample albedo texture
    float4 albedo = AlbedoTexture.Sample(LinearSampler, input.TexCoord) * BaseColor;

#ifdef VERTEX_COLORS
    albedo *= input.Color;
#endif

#ifdef ALPHA_TEST
    if (albedo.a < AlphaCutoff)
        discard;
#endif

    // Add emissive
    float3 color = albedo.rgb + EmissiveColor.rgb;

    return float4(color, albedo.a);
}
