// Decal vertex shader - transforms unit cube vertices by decal world matrix
#pragma pack_matrix(row_major)
#include "scene_uniforms.hlsli"

cbuffer DecalUniforms : register(b0, space1)
{
    float4x4 DecalWorldMatrix;
    float4x4 DecalInvWorldMatrix;
    float4 DecalColor;
    float AngleFadeStart;
    float AngleFadeEnd;
    float2 _Pad0;
};

struct VSInput
{
    float3 Position : POSITION;
};

struct VSOutput
{
    float4 Position : SV_POSITION;
    float4 ScreenPos : TEXCOORD0;
};

VSOutput main(VSInput input)
{
    VSOutput output;

    // Transform unit cube vertex by decal world matrix, then by camera VP
    float4 worldPos = mul(float4(input.Position, 1.0), DecalWorldMatrix);
    output.Position = mul(worldPos, ViewProjectionMatrix);
    output.ScreenPos = output.Position;

    return output;
}
