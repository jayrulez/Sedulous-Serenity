// Unlit Material Fragment Shader
// Simple color * texture output without lighting calculations

#pragma pack_matrix(row_major)

struct PSInput
{
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
    float3 tint : COLOR0;
};

// ==================== Bind Group 0: Scene Resources ====================
// (Camera uniforms not needed in fragment shader for unlit)

// ==================== Bind Group 1: Material Resources ====================

// Material uniform buffer (binding 1)
cbuffer MaterialUniforms : register(b1, space1)
{
    float4 color;    // Base color/tint
};

// Material texture (binding t0)
Texture2D mainTexture : register(t0, space1);

// Material sampler (binding s0)
SamplerState mainSampler : register(s0, space1);

// ==================== Main ====================

float4 main(PSInput input) : SV_Target
{
    // Sample texture
    float4 texColor = mainTexture.Sample(mainSampler, input.uv);

    // Combine: texture * material color * instance tint
    float4 finalColor = texColor * color * float4(input.tint, 1.0);

#ifdef ALPHA_TEST
    if (finalColor.a < 0.5)
        discard;
#endif

    return finalColor;
}
