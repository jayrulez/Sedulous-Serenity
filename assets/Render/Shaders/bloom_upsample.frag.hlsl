// Bloom Upsample Fragment Shader
// 9-tap tent filter for high quality upsampling + additive blend with previous level.

cbuffer BloomUpsampleParams : register(b0)
{
    float Intensity;    // Bloom intensity / blend factor
    float2 TexelSize;   // 1.0 / current source (lower mip) resolution
    float _Pad;
};

Texture2D CurrentMip : register(t0);     // The lower-res mip being upsampled
Texture2D PreviousLevel : register(t1);  // Higher-res result to blend with (or scene color for final)
SamplerState LinearSampler : register(s0);

struct FragmentInput
{
    float4 Position : SV_Position;
    float2 TexCoord : TEXCOORD0;
};

float4 main(FragmentInput input) : SV_Target
{
    float2 uv = input.TexCoord;
    float2 ts = TexelSize;

    // 9-tap tent filter (3x3 bilinear samples)
    // Produces smooth, artifact-free upsampling
    float3 bloom = float3(0, 0, 0);

    bloom += CurrentMip.Sample(LinearSampler, uv + float2(-1, -1) * ts).rgb * 1.0;
    bloom += CurrentMip.Sample(LinearSampler, uv + float2( 0, -1) * ts).rgb * 2.0;
    bloom += CurrentMip.Sample(LinearSampler, uv + float2( 1, -1) * ts).rgb * 1.0;

    bloom += CurrentMip.Sample(LinearSampler, uv + float2(-1,  0) * ts).rgb * 2.0;
    bloom += CurrentMip.Sample(LinearSampler, uv                      ).rgb * 4.0;
    bloom += CurrentMip.Sample(LinearSampler, uv + float2( 1,  0) * ts).rgb * 2.0;

    bloom += CurrentMip.Sample(LinearSampler, uv + float2(-1,  1) * ts).rgb * 1.0;
    bloom += CurrentMip.Sample(LinearSampler, uv + float2( 0,  1) * ts).rgb * 2.0;
    bloom += CurrentMip.Sample(LinearSampler, uv + float2( 1,  1) * ts).rgb * 1.0;

    bloom /= 16.0;

    // Blend with higher-resolution level
    float3 prev = PreviousLevel.Sample(LinearSampler, uv).rgb;

    return float4(prev + bloom * Intensity, 1.0);
}
