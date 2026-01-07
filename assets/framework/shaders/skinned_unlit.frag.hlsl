// Skinned Unlit Fragment Shader
// Simple color * texture output without lighting calculations
// Uses 3 bind groups: Scene (0), Object+Bones (1), Material (2)

#pragma pack_matrix(row_major)

struct PSInput
{
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
};

// ==================== Bind Group 2: Material Resources ====================

// Material uniform buffer (binding 1)
cbuffer MaterialUniforms : register(b1, space2)
{
    float4 color;    // Base color/tint
};

// Material texture (binding t0)
Texture2D mainTexture : register(t0, space2);

// Material sampler (binding s0)
SamplerState mainSampler : register(s0, space2);

// ==================== Main ====================

float4 main(PSInput input) : SV_Target
{
    // Sample texture
    float4 texColor = mainTexture.Sample(mainSampler, input.uv);

    // Combine: texture * material color
    float4 finalColor = texColor * color;

#ifdef ALPHA_TEST
    if (finalColor.a < 0.5)
        discard;
#endif

    return finalColor;
}
