// Particle fragment shader for RendererNG
// Supports texture sampling and soft particles

#include "common.hlsli"

// ============================================================================
// Particle Uniforms
// ============================================================================

cbuffer ParticleUniforms : register(b1)
{
    uint RenderMode;
    float StretchFactor;
    float MinStretchLength;
    uint UseTexture;

    uint SoftParticlesEnabled;
    float SoftParticleDistance;
    float ParticleNearPlane;
    float ParticleFarPlane;
};

// ============================================================================
// Textures and Samplers
// ============================================================================

Texture2D ParticleTexture : register(t0);
SamplerState ParticleSampler : register(s0);

#ifdef SOFT_PARTICLES
Texture2D DepthTexture : register(t1);
SamplerState DepthSampler : register(s1);
#endif

// ============================================================================
// Pixel Input
// ============================================================================

struct PS_INPUT
{
    float4 Position : SV_POSITION;
    float4 Color : COLOR0;
    float2 TexCoord : TEXCOORD0;
    float3 WorldPos : TEXCOORD1;
#ifdef SOFT_PARTICLES
    float4 ScreenPos : TEXCOORD2;
#endif
};

// ============================================================================
// Depth Linearization
// ============================================================================

float LinearizeDepth(float depth, float nearPlane, float farPlane)
{
    // Convert from [0,1] depth to linear view-space depth
    return (nearPlane * farPlane) / (farPlane - depth * (farPlane - nearPlane));
}

// ============================================================================
// Main Fragment Shader
// ============================================================================

float4 main(PS_INPUT input) : SV_Target
{
    // Sample particle texture
    float4 texColor = float4(1, 1, 1, 1);
    if (UseTexture > 0)
    {
        texColor = ParticleTexture.Sample(ParticleSampler, input.TexCoord);
    }

    // Combine texture with particle color
    float4 finalColor = input.Color * texColor;

    // Early alpha discard
    if (finalColor.a < 0.001)
        discard;

#ifdef SOFT_PARTICLES
    // Soft particles: fade based on depth difference from scene geometry
    if (SoftParticlesEnabled > 0)
    {
        // Get screen UV from clip position
        float2 screenUV = input.ScreenPos.xy / input.ScreenPos.w;
        screenUV = screenUV * 0.5 + 0.5;
        screenUV.y = 1.0 - screenUV.y; // Flip Y for texture sampling

        // Sample scene depth
        float sceneDepth = DepthTexture.Sample(DepthSampler, screenUV).r;
        float linearSceneDepth = LinearizeDepth(sceneDepth, ParticleNearPlane, ParticleFarPlane);

        // Get particle depth
        float particleDepth = input.ScreenPos.z / input.ScreenPos.w;
        float linearParticleDepth = LinearizeDepth(particleDepth, ParticleNearPlane, ParticleFarPlane);

        // Calculate soft fade
        float depthDiff = linearSceneDepth - linearParticleDepth;
        float softFade = saturate(depthDiff / SoftParticleDistance);

        // Apply fade to alpha
        finalColor.a *= softFade;
    }
#endif

    return finalColor;
}
