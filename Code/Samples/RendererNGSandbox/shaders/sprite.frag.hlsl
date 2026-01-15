// Sprite fragment shader for RendererNG
// Simple texture sampling with color modulation

#include "common.hlsli"

// ============================================================================
// Sprite Uniforms
// ============================================================================

cbuffer SpriteUniforms : register(b1)
{
    uint UseTexture;
    float DepthBias;
    float _Padding0;
    float _Padding1;
};

// ============================================================================
// Textures and Samplers
// ============================================================================

Texture2D SpriteTexture : register(t0);
SamplerState SpriteSampler : register(s0);

// ============================================================================
// Pixel Input
// ============================================================================

struct PS_INPUT
{
    float4 Position : SV_POSITION;
    float4 Color : COLOR0;
    float2 TexCoord : TEXCOORD0;
};

// ============================================================================
// Main Fragment Shader
// ============================================================================

float4 main(PS_INPUT input) : SV_Target
{
    // Sample sprite texture
    float4 texColor = float4(1, 1, 1, 1);
    if (UseTexture > 0)
    {
        texColor = SpriteTexture.Sample(SpriteSampler, input.TexCoord);
    }

    // Combine texture with sprite color
    float4 finalColor = input.Color * texColor;

    // Alpha discard for transparent pixels
    if (finalColor.a < 0.001)
        discard;

    return finalColor;
}
