// Skybox fragment shader for RendererNG
// Samples cubemap with optional HDR exposure

#include "common.hlsli"

// ============================================================================
// Skybox Uniforms
// ============================================================================

cbuffer SkyboxUniforms : register(b1)
{
    float4x4 InverseViewProjection;
    float Exposure;
    float Rotation;
    float _Padding0;
    float _Padding1;
};

// ============================================================================
// Textures and Samplers
// ============================================================================

TextureCube SkyboxCubemap : register(t0);
SamplerState SkyboxSampler : register(s0);

// ============================================================================
// Pixel Input
// ============================================================================

struct SkyboxPS_INPUT
{
    float4 Position : SV_POSITION;
    float3 RayDir : TEXCOORD0;
};

// ============================================================================
// Tone Mapping (simple Reinhard)
// ============================================================================

float3 ToneMapReinhard(float3 color)
{
    return color / (color + 1.0);
}

// ============================================================================
// Main Fragment Shader
// ============================================================================

float4 main(SkyboxPS_INPUT input) : SV_Target
{
    // Sample cubemap
    float3 skyColor = SkyboxCubemap.Sample(SkyboxSampler, input.RayDir).rgb;

    // Apply exposure for HDR cubemaps
    if (Exposure != 1.0)
    {
        skyColor *= Exposure;
    }

    // Optional tone mapping (for HDR)
#ifdef HDR_TONEMAP
    skyColor = ToneMapReinhard(skyColor);
#endif

    return float4(skyColor, 1.0);
}
