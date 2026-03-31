#pragma pack_matrix(row_major)

struct PSInput
{
    float4 Position : SV_Position;
    float2 TexCoord : TEXCOORD0;
};

Texture2D    SceneColor    : register(t0);
Texture2D    BloomResult   : register(t1);
SamplerState LinearSampler : register(s2);

cbuffer BloomParams : register(b3)
{
    float Intensity;
    float3 _pad;
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
    float3 scene = SceneColor.SampleLevel(LinearSampler, input.TexCoord, 0).rgb;
    float3 bloom = BloomResult.SampleLevel(LinearSampler, input.TexCoord, 0).rgb;
    return float4(scene + bloom * Intensity, 1.0);
}
