// Chromatic Aberration Fragment Shader
// Per-channel UV offset scaled by distance from screen center.

cbuffer ChromaticAberrationParams : register(b0)
{
    float Intensity;
    float2 TexelSize;
    float _Pad;
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
    float2 uv = input.TexCoord;

    // Offset direction and magnitude: increases toward screen edges
    float2 centered = uv - 0.5;
    float dist = length(centered);
    float2 offset = centered * Intensity * dist;

    // Sample each channel at different UV offsets
    float r = SourceTexture.Sample(LinearSampler, uv - offset).r;
    float g = SourceTexture.Sample(LinearSampler, uv).g;
    float b = SourceTexture.Sample(LinearSampler, uv + offset).b;

    return float4(r, g, b, 1.0);
}
