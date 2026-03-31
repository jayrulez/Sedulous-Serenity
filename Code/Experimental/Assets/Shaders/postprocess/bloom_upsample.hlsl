#pragma pack_matrix(row_major)

struct PSInput
{
    float4 Position : SV_Position;
    float2 TexCoord : TEXCOORD0;
};

Texture2D    CurrentMip    : register(t0);
Texture2D    PrevUpsample  : register(t1);
SamplerState LinearSampler : register(s2);

cbuffer BloomParams : register(b3)
{
    float  Threshold;
    float  SoftThreshold;
    float  Intensity;
    uint   MipLevel;
    float2 TexelSize;     // texel size of CurrentMip (source)
    uint   HasPrevUpsample;  // 0 = deepest level (no previous upsample)
    float  _pad;
};

PSInput VSMain(uint vertexID : SV_VertexID)
{
    PSInput output;
    output.TexCoord = float2((vertexID << 1) & 2, vertexID & 2);
    output.Position = float4(output.TexCoord * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
    return output;
}

float4 PSMain(PSInput input) : SV_Target0
{
    float2 uv = input.TexCoord;

    // 9-tap tent filter (3x3 bilinear taps, tent weights)
    // Weights: 1 2 1 / 2 4 2 / 1 2 1  (sum = 16)
    float3 result = float3(0, 0, 0);
    result += CurrentMip.SampleLevel(LinearSampler, uv + float2(-1, -1) * TexelSize, 0).rgb * 1.0;
    result += CurrentMip.SampleLevel(LinearSampler, uv + float2( 0, -1) * TexelSize, 0).rgb * 2.0;
    result += CurrentMip.SampleLevel(LinearSampler, uv + float2( 1, -1) * TexelSize, 0).rgb * 1.0;
    result += CurrentMip.SampleLevel(LinearSampler, uv + float2(-1,  0) * TexelSize, 0).rgb * 2.0;
    result += CurrentMip.SampleLevel(LinearSampler, uv                              , 0).rgb * 4.0;
    result += CurrentMip.SampleLevel(LinearSampler, uv + float2( 1,  0) * TexelSize, 0).rgb * 2.0;
    result += CurrentMip.SampleLevel(LinearSampler, uv + float2(-1,  1) * TexelSize, 0).rgb * 1.0;
    result += CurrentMip.SampleLevel(LinearSampler, uv + float2( 0,  1) * TexelSize, 0).rgb * 2.0;
    result += CurrentMip.SampleLevel(LinearSampler, uv + float2( 1,  1) * TexelSize, 0).rgb * 1.0;
    result /= 16.0;

    // Accumulate with previous upsample level
    if (HasPrevUpsample > 0)
        result += PrevUpsample.SampleLevel(LinearSampler, uv, 0).rgb;

    return float4(max(result, 0.0), 1.0);
}
