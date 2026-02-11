// Unlit Vertex Shader
// Simple vertex transformation without lighting calculations
#pragma pack_matrix(row_major)

#include "scene_uniforms.hlsli"

#include "object_uniforms.hlsli"

struct VertexInput
{
    float3 Position : POSITION;
    float3 Normal : NORMAL;
    float2 TexCoord : TEXCOORD0;
#ifdef NORMAL_MAP
    float4 Tangent : TANGENT;
#endif
#ifdef INSTANCED
    float4 InstanceWorldRow0 : TEXCOORD3;
    float4 InstanceWorldRow1 : TEXCOORD4;
    float4 InstanceWorldRow2 : TEXCOORD5;
    float4 InstanceWorldRow3 : TEXCOORD6;
#endif
};

struct VertexOutput
{
    float4 Position : SV_Position;
    float2 TexCoord : TEXCOORD0;
#ifdef VERTEX_COLORS
    float4 Color : TEXCOORD1;
#endif
};

VertexOutput main(VertexInput input)
{
    VertexOutput output;

    float3 localPos = input.Position;

#ifdef INSTANCED
    float4x4 instanceWorldMatrix = float4x4(
        input.InstanceWorldRow0,
        input.InstanceWorldRow1,
        input.InstanceWorldRow2,
        input.InstanceWorldRow3
    );
    float4 worldPos = mul(float4(localPos, 1.0), instanceWorldMatrix);
#else
    float4 worldPos = mul(float4(localPos, 1.0), WorldMatrix);
#endif

    output.Position = mul(worldPos, ViewProjectionMatrix);
    output.TexCoord = input.TexCoord;

    return output;
}
