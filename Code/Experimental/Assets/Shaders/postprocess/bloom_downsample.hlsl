#pragma pack_matrix(row_major)

struct PSInput
{
    float4 Position : SV_Position;
    float2 TexCoord : TEXCOORD0;
};

Texture2D    InputTex      : register(t0);
SamplerState LinearSampler : register(s1);

cbuffer BloomParams : register(b2)
{
    float  Threshold;
    float  SoftThreshold;
    float  Intensity;
    uint   MipLevel;
    float2 TexelSize;
    float2 _pad;
};

PSInput VSMain(uint vertexID : SV_VertexID)
{
    PSInput output;
    output.TexCoord = float2((vertexID << 1) & 2, vertexID & 2);
    output.Position = float4(output.TexCoord * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
    return output;
}

float Luminance(float3 c)
{
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

// Soft threshold: smooth transition around the threshold value
float3 ApplyThreshold(float3 color)
{
    float luma = Luminance(color);
    float knee = Threshold * SoftThreshold;
    float soft = luma - Threshold + knee;
    soft = clamp(soft, 0.0, 2.0 * knee);
    soft = soft * soft / (4.0 * knee + 0.00001);
    float contribution = max(soft, luma - Threshold) / max(luma, 0.00001);
    return color * max(contribution, 0.0);
}

// Karis average weight: 1/(1+luma) per sample group.
// Suppresses firefly pixels by reducing the weight of very bright samples.
float KarisWeight(float3 c)
{
    return 1.0 / (1.0 + Luminance(c));
}

float4 PSMain(PSInput input) : SV_Target0
{
    float2 uv = input.TexCoord;

    // 13-tap downsample filter (Call of Duty: Advanced Warfare pattern)
    // 4 groups of bilinear taps + center, energy preserving
    //
    //  a . b . c
    //  . d . e .
    //  f . g . h
    //  . i . j .
    //  k . l . m
    //
    // Groups:
    //   A = (d+e+i+j)/4  (inner box)
    //   B = (a+b+f+g)/4  (top-left)
    //   C = (b+c+g+h)/4  (top-right)
    //   D = (f+g+k+l)/4  (bottom-left)
    //   E = (g+h+l+m)/4  (bottom-right)
    //
    // Result = A*0.5 + (B+C+D+E)*0.125

    float3 a = InputTex.SampleLevel(LinearSampler, uv + float2(-2, -2) * TexelSize, 0).rgb;
    float3 b = InputTex.SampleLevel(LinearSampler, uv + float2( 0, -2) * TexelSize, 0).rgb;
    float3 c = InputTex.SampleLevel(LinearSampler, uv + float2( 2, -2) * TexelSize, 0).rgb;
    float3 d = InputTex.SampleLevel(LinearSampler, uv + float2(-1, -1) * TexelSize, 0).rgb;
    float3 e = InputTex.SampleLevel(LinearSampler, uv + float2( 1, -1) * TexelSize, 0).rgb;
    float3 f = InputTex.SampleLevel(LinearSampler, uv + float2(-2,  0) * TexelSize, 0).rgb;
    float3 g = InputTex.SampleLevel(LinearSampler, uv,                               0).rgb;
    float3 h = InputTex.SampleLevel(LinearSampler, uv + float2( 2,  0) * TexelSize, 0).rgb;
    float3 i = InputTex.SampleLevel(LinearSampler, uv + float2(-1,  1) * TexelSize, 0).rgb;
    float3 j = InputTex.SampleLevel(LinearSampler, uv + float2( 1,  1) * TexelSize, 0).rgb;
    float3 k = InputTex.SampleLevel(LinearSampler, uv + float2(-2,  2) * TexelSize, 0).rgb;
    float3 l = InputTex.SampleLevel(LinearSampler, uv + float2( 0,  2) * TexelSize, 0).rgb;
    float3 m = InputTex.SampleLevel(LinearSampler, uv + float2( 2,  2) * TexelSize, 0).rgb;

    float3 result;

    if (MipLevel == 0)
    {
        // First downsample: apply threshold + Karis average to suppress fireflies
        float3 groupA = (d + e + i + j) * 0.25;
        float3 groupB = (a + b + f + g) * 0.25;
        float3 groupC = (b + c + g + h) * 0.25;
        float3 groupD = (f + g + k + l) * 0.25;
        float3 groupE = (g + h + l + m) * 0.25;

        // Karis weighted average per group
        float wA = KarisWeight(groupA);
        float wB = KarisWeight(groupB);
        float wC = KarisWeight(groupC);
        float wD = KarisWeight(groupD);
        float wE = KarisWeight(groupE);

        result = (groupA * wA + groupB * wB + groupC * wC + groupD * wD + groupE * wE)
               / (wA + wB + wC + wD + wE);

        if (Threshold > 0.0)
            result = ApplyThreshold(result);
    }
    else
    {
        // Subsequent downsamples: standard 13-tap filter
        float3 groupA = (d + e + i + j) * 0.25;
        float3 groupB = (a + b + f + g) * 0.25;
        float3 groupC = (b + c + g + h) * 0.25;
        float3 groupD = (f + g + k + l) * 0.25;
        float3 groupE = (g + h + l + m) * 0.25;
        result = groupA * 0.5 + (groupB + groupC + groupD + groupE) * 0.125;
    }

    return float4(max(result, 0.0), 1.0);
}
