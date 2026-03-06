// Curve decal vertex shader - transforms pre-generated strip vertices
#pragma pack_matrix(row_major)
#include "scene_uniforms.hlsli"

cbuffer CurveDecalParams : register(b0, space1)
{
    float4 DecalColor;
    float ProjectionDepth;
    float3 _Pad;
};

struct VSInput
{
    float3 Position : POSITION;
    float2 TexCoord : TEXCOORD0;
    float3 Normal : NORMAL;
};

struct VSOutput
{
    float4 Position : SV_POSITION;
    float2 TexCoord : TEXCOORD0;
    float3 WorldPos : TEXCOORD1;
    float3 Normal : TEXCOORD2;
};

VSOutput main(VSInput input)
{
    VSOutput output;

    // Vertices are already in world space
    output.WorldPos = input.Position;
    output.Position = mul(float4(input.Position, 1.0), ViewProjectionMatrix);
    output.TexCoord = input.TexCoord;
    output.Normal = input.Normal;

    return output;
}
