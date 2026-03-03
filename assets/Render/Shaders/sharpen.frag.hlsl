// Sharpening Fragment Shader
// Unsharp mask with neighborhood clamping to prevent ringing.
// Designed to counteract TAA softening.

cbuffer SharpenParams : register(b0)
{
    float Intensity;
    float2 TexelSize;
    float _Pad;
};

Texture2D SourceTexture : register(t0);
SamplerState PointSampler : register(s0);

struct FragmentInput
{
    float4 Position : SV_Position;
    float2 TexCoord : TEXCOORD0;
};

float4 main(FragmentInput input) : SV_Target
{
    float2 uv = input.TexCoord;

    // Sample 3x3 cross neighborhood
    float3 c = SourceTexture.Sample(PointSampler, uv).rgb;
    float3 n = SourceTexture.Sample(PointSampler, uv + float2(0, -TexelSize.y)).rgb;
    float3 s = SourceTexture.Sample(PointSampler, uv + float2(0,  TexelSize.y)).rgb;
    float3 w = SourceTexture.Sample(PointSampler, uv + float2(-TexelSize.x, 0)).rgb;
    float3 e = SourceTexture.Sample(PointSampler, uv + float2( TexelSize.x, 0)).rgb;

    // Unsharp mask: sharpen = center + weight * (center - blur)
    float3 blur = 0.25 * (n + s + w + e);
    float3 sharpened = c + (c - blur) * Intensity;

    // Clamp to neighborhood min/max to prevent ringing artifacts
    float3 minColor = min(c, min(min(n, s), min(w, e)));
    float3 maxColor = max(c, max(max(n, s), max(w, e)));
    sharpened = clamp(sharpened, minColor, maxColor);

    return float4(max(sharpened, 0.0), 1.0);
}
