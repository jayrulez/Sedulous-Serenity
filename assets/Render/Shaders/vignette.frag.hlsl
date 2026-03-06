// Vignette Fragment Shader
// Radial darkening from screen center with configurable intensity and smoothness.

cbuffer VignetteParams : register(b0)
{
    float Intensity;     // 0-1 darkening strength
    float Smoothness;    // 0-1 falloff width (higher = wider falloff)
    float2 _Pad;
};

Texture2D SourceTexture : register(t0);
SamplerState LinearSampler : register(s0);

struct FragmentInput
{
    float4 Position : SV_Position;
    float2 TexCoord : TEXCOORD0;
};

float4 main(FragmentInput input) : SV_Target
{
    float3 color = SourceTexture.Sample(LinearSampler, input.TexCoord).rgb;

    // Distance from center (0 at center, ~1 at corners)
    float2 centered = input.TexCoord - 0.5;
    float dist = length(centered) * 2.0; // 0..~1.41

    // Smooth vignette falloff
    float vignette = smoothstep(1.0, 1.0 - Smoothness, dist);

    // Blend between original color and darkened
    color *= lerp(1.0, vignette, Intensity);

    return float4(color, 1.0);
}
