// CAS-style Adaptive Sharpening Fragment Shader
// Contrast Adaptive Sharpening to counteract TAA softening.

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

float Luminance(float3 color)
{
    return dot(color, float3(0.2126, 0.7152, 0.0722));
}

float4 main(FragmentInput input) : SV_Target
{
    float2 uv = input.TexCoord;

    // Sample 3x3 neighborhood (cross pattern + center)
    float3 c  = SourceTexture.Sample(PointSampler, uv).rgb;
    float3 n  = SourceTexture.Sample(PointSampler, uv + float2(0, -TexelSize.y)).rgb;
    float3 s  = SourceTexture.Sample(PointSampler, uv + float2(0,  TexelSize.y)).rgb;
    float3 w  = SourceTexture.Sample(PointSampler, uv + float2(-TexelSize.x, 0)).rgb;
    float3 e  = SourceTexture.Sample(PointSampler, uv + float2( TexelSize.x, 0)).rgb;

    // Compute local contrast (min/max of cross neighborhood)
    float3 minColor = min(c, min(min(n, s), min(w, e)));
    float3 maxColor = max(c, max(max(n, s), max(w, e)));

    // Adaptive sharpening weight based on local contrast
    // Low contrast = sharpen more, high contrast = sharpen less (avoids ringing)
    float3 contrast = maxColor - minColor;
    float3 rcpMax = 1.0 / (maxColor + 0.001);
    float3 adaptiveWeight = saturate(1.0 - contrast * rcpMax);
    adaptiveWeight = adaptiveWeight * adaptiveWeight; // Quadratic falloff

    // Average adaptive weight across channels
    float weight = dot(adaptiveWeight, float3(0.333, 0.333, 0.334)) * Intensity;

    // Sharpening kernel: center * (1 + 4w) - w * (n + s + w + e)
    // This is an unsharp mask: original + weight * (original - blur)
    float3 blur = 0.25 * (n + s + w + e);
    float3 sharpened = c + weight * (c - blur);

    // Clamp to prevent negative values / excessive ringing
    sharpened = max(sharpened, 0.0);

    return float4(sharpened, 1.0);
}
