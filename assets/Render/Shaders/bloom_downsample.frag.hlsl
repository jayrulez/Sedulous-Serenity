// Bloom Downsample Fragment Shader
// 13-tap downsampling filter based on Jimenez 2014 (Call of Duty: Advanced Warfare).
// First pass applies brightness threshold; subsequent passes just downsample.

cbuffer BloomDownsampleParams : register(b0)
{
    float Threshold;     // Brightness threshold (first pass only)
    float2 TexelSize;    // 1.0 / source resolution
    float IsFirstPass;   // 1.0 = apply threshold, 0.0 = just downsample
};

Texture2D SourceTexture : register(t0);
SamplerState LinearSampler : register(s0);

struct FragmentInput
{
    float4 Position : SV_Position;
    float2 TexCoord : TEXCOORD0;
};

// Soft threshold: smoothly transitions around the threshold value
float3 SoftThreshold(float3 color, float threshold)
{
    float brightness = max(color.r, max(color.g, color.b));
    float knee = threshold * 0.5;
    float soft = brightness - threshold + knee;
    soft = clamp(soft, 0.0, 2.0 * knee);
    soft = soft * soft / (4.0 * knee + 0.00001);
    float contribution = max(soft, brightness - threshold) / max(brightness, 0.00001);
    return color * max(contribution, 0.0);
}

float4 main(FragmentInput input) : SV_Target
{
    float2 uv = input.TexCoord;
    float2 ts = TexelSize;

    // 13-tap downsample filter (Jimenez 2014)
    // Five 2x2 bilinear taps arranged in overlapping quads.
    //
    //   a . b . c
    //   . d . e .
    //   f . g . h
    //   . i . j .
    //   k . l . m

    float3 a = SourceTexture.Sample(LinearSampler, uv + float2(-2, -2) * ts).rgb;
    float3 b = SourceTexture.Sample(LinearSampler, uv + float2( 0, -2) * ts).rgb;
    float3 c = SourceTexture.Sample(LinearSampler, uv + float2( 2, -2) * ts).rgb;
    float3 d = SourceTexture.Sample(LinearSampler, uv + float2(-1, -1) * ts).rgb;
    float3 e = SourceTexture.Sample(LinearSampler, uv + float2( 1, -1) * ts).rgb;
    float3 f = SourceTexture.Sample(LinearSampler, uv + float2(-2,  0) * ts).rgb;
    float3 g = SourceTexture.Sample(LinearSampler, uv                      ).rgb;
    float3 h = SourceTexture.Sample(LinearSampler, uv + float2( 2,  0) * ts).rgb;
    float3 i = SourceTexture.Sample(LinearSampler, uv + float2(-1,  1) * ts).rgb;
    float3 j = SourceTexture.Sample(LinearSampler, uv + float2( 1,  1) * ts).rgb;
    float3 k = SourceTexture.Sample(LinearSampler, uv + float2(-2,  2) * ts).rgb;
    float3 l = SourceTexture.Sample(LinearSampler, uv + float2( 0,  2) * ts).rgb;
    float3 m = SourceTexture.Sample(LinearSampler, uv + float2( 2,  2) * ts).rgb;

    // Standard 13-tap weights (Jimenez 2014)
    // Center quad: 0.5, four corners: 0.125 each = 1.0 total
    float3 result = (d + e + i + j) * 0.125;          // Center: 0.5 / 4
    result += (a + c + k + m) * 0.03125;               // 4 outer corners: 0.125 / 4
    result += (b + f + h + l) * 0.0625;                // 4 outer edges: 0.25 / 4
    result += g * 0.125;                               // Center sample

    // Apply threshold on first pass
    if (IsFirstPass > 0.5)
        result = SoftThreshold(result, Threshold);

    return float4(result, 1.0);
}
