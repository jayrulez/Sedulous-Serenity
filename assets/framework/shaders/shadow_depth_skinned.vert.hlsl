// Shadow Depth Vertex Shader - Skinned Mesh Variant
// Renders depth only for shadow map generation with skeletal animation
// Uses row-major matrices with row-vector math: mul(vector, matrix)

#pragma pack_matrix(row_major)

struct VSInput
{
    float3 position : POSITION;
    float3 normal : NORMAL;
    float2 uv : TEXCOORD0;
    float4 boneWeights : BLENDWEIGHT;
    uint4 boneIndices : BLENDINDICES;
};

struct VSOutput
{
    float4 position : SV_Position;
};

// Shadow pass uniforms
cbuffer ShadowPassUniforms : register(b0)
{
    float4x4 g_LightViewProjection;
    float4 g_DepthBias;
};

// Per-object transform
cbuffer ObjectUniforms : register(b1)
{
    float4x4 g_Model;
};

// Bone matrices
cbuffer BoneUniforms : register(b2)
{
    float4x4 g_Bones[256];
};

VSOutput main(VSInput input)
{
    VSOutput output;

    // Compute skinned position (row-vector: pos * bone)
    float4x4 skinMatrix =
        input.boneWeights.x * g_Bones[input.boneIndices.x] +
        input.boneWeights.y * g_Bones[input.boneIndices.y] +
        input.boneWeights.z * g_Bones[input.boneIndices.z] +
        input.boneWeights.w * g_Bones[input.boneIndices.w];

    float4 skinnedPos = mul(float4(input.position, 1.0), skinMatrix);
    float4 worldPos = mul(skinnedPos, g_Model);
    output.position = mul(worldPos, g_LightViewProjection);

    return output;
}
