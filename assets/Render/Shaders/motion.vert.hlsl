// Motion Vector Vertex Shader
// Calculates current and previous frame positions for TAA/motion blur
#pragma pack_matrix(row_major)

#include "scene_uniforms.hlsli"

#include "object_uniforms.hlsli"

#ifdef SKINNED
#include "bone_uniforms.hlsli"

cbuffer PrevBoneUniforms : register(b3)
{
    float4x4 PrevBoneMatrices[256];
};
#endif

struct VertexInput
{
    float3 Position : TEXCOORD0;
    float3 Normal : TEXCOORD1;
    float2 TexCoord : TEXCOORD2;
    float4 Color : TEXCOORD3;
    float4 Tangent : TEXCOORD4;
#ifdef SKINNED
    uint4 BoneIndices : TEXCOORD5;
    float4 BoneWeights : TEXCOORD6;
#endif
};

struct VertexOutput
{
    float4 Position : SV_Position;
    float4 CurrentPos : TEXCOORD0;
    float4 PrevPos : TEXCOORD1;
#ifdef ALPHA_TEST
    float2 TexCoord : TEXCOORD2;
#endif
};

VertexOutput main(VertexInput input)
{
    VertexOutput output;

    float3 localPos = input.Position;
    float3 prevLocalPos = input.Position;

#ifdef SKINNED
    // Current frame skinning
    float4x4 skinMatrix =
        BoneMatrices[input.BoneIndices.x] * input.BoneWeights.x +
        BoneMatrices[input.BoneIndices.y] * input.BoneWeights.y +
        BoneMatrices[input.BoneIndices.z] * input.BoneWeights.z +
        BoneMatrices[input.BoneIndices.w] * input.BoneWeights.w;

    localPos = mul(float4(localPos, 1.0), skinMatrix).xyz;

    // Previous frame skinning
    float4x4 prevSkinMatrix =
        PrevBoneMatrices[input.BoneIndices.x] * input.BoneWeights.x +
        PrevBoneMatrices[input.BoneIndices.y] * input.BoneWeights.y +
        PrevBoneMatrices[input.BoneIndices.z] * input.BoneWeights.z +
        PrevBoneMatrices[input.BoneIndices.w] * input.BoneWeights.w;

    prevLocalPos = mul(float4(prevLocalPos, 1.0), prevSkinMatrix).xyz;
#endif

    // Current frame position
    float4 worldPos = mul(float4(localPos, 1.0), WorldMatrix);
    float4 clipPos = mul(worldPos, ViewProjectionMatrix);

    // Previous frame position
    float4 prevWorldPos = mul(float4(prevLocalPos, 1.0), PrevWorldMatrix);
    float4 prevClipPos = mul(prevWorldPos, PrevViewProjectionMatrix);

    output.Position = clipPos;
    output.CurrentPos = clipPos;
    output.PrevPos = prevClipPos;

#ifdef ALPHA_TEST
    output.TexCoord = input.TexCoord;
#endif

    return output;
}
