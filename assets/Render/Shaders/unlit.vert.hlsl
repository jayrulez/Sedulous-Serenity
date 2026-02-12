// Unlit Vertex Shader
// Simple vertex transformation without lighting calculations
//
// Variant flags:
//   VERTEX_COLORS - Enable vertex color output (must be set in pipeline ShaderFlags
//                   to use vertex colors in the unlit fragment shader)
//   SKINNED       - Enable GPU skinning with bone transforms
//   INSTANCED     - Enable GPU instancing with per-instance world matrices
#pragma pack_matrix(row_major)

#include "scene_uniforms.hlsli"

#include "object_uniforms.hlsli"

#ifdef SKINNED
#include "bone_uniforms.hlsli"
#endif

struct VertexInput
{
    float3 Position : POSITION;
    float3 Normal : NORMAL;
    float2 TexCoord : TEXCOORD0;
    float4 Color : COLOR0;
    float4 Tangent : TANGENT;   // Not used by unlit shader, but must be declared for layout consistency
#ifdef SKINNED
    uint4 BoneIndices : BLENDINDICES;
    float4 BoneWeights : BLENDWEIGHT;
#endif
#ifdef INSTANCED
    // Instance data: world matrix as 4 float4 rows at locations 5-8 (after Color=3, Tangent=4)
    float4 InstanceWorldRow0 : TEXCOORD5;
    float4 InstanceWorldRow1 : TEXCOORD6;
    float4 InstanceWorldRow2 : TEXCOORD7;
    float4 InstanceWorldRow3 : TEXCOORD8;
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

#ifdef SKINNED
    // Apply bone transforms
    float4x4 skinMatrix =
        BoneMatrices[input.BoneIndices.x] * input.BoneWeights.x +
        BoneMatrices[input.BoneIndices.y] * input.BoneWeights.y +
        BoneMatrices[input.BoneIndices.z] * input.BoneWeights.z +
        BoneMatrices[input.BoneIndices.w] * input.BoneWeights.w;

    localPos = mul(float4(localPos, 1.0), skinMatrix).xyz;
#endif

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
#ifdef VERTEX_COLORS
    output.Color = input.Color;
#endif

    return output;
}
