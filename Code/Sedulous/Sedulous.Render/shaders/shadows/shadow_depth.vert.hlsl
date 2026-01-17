// Shadow depth vertex shader with variant support
// Variants: SKINNED (bone transforms), INSTANCED (per-instance matrices)

#pragma pack_matrix(row_major)

#ifdef SKINNED
#define MAX_BONES 256
#define MAX_BONE_INFLUENCE 4
#endif

// --------------------------------------------------
// Input structures
// --------------------------------------------------

struct VSInput
{
    float3 position : POSITION;

#ifdef SKINNED
    uint4 boneIndices : BLENDINDICES;
    float4 boneWeights : BLENDWEIGHT;
#endif

#ifdef INSTANCED
    // Per-instance world matrix rows
    float4 instanceRow0 : TEXCOORD3;
    float4 instanceRow1 : TEXCOORD4;
    float4 instanceRow2 : TEXCOORD5;
    float4 instanceRow3 : TEXCOORD6;
#endif
};

struct VSOutput
{
    float4 position : SV_Position;
#ifdef ALPHA_TEST
    float2 uv : TEXCOORD0;
#endif
};

// --------------------------------------------------
// Uniform buffers
// --------------------------------------------------

cbuffer ShadowUniforms : register(b0)
{
    float4x4 lightViewProjection;
#ifndef INSTANCED
    float4x4 worldMatrix;
#endif
};

#ifdef SKINNED
cbuffer BoneUniforms : register(b1)
{
    float4x4 boneMatrices[MAX_BONES];
};
#endif

// --------------------------------------------------
// Main
// --------------------------------------------------

VSOutput main(VSInput input)
{
    VSOutput output;
    float4 localPos = float4(input.position, 1.0);

#ifdef SKINNED
    // Apply bone transforms
    float4 skinnedPos = float4(0.0, 0.0, 0.0, 0.0);

    [unroll]
    for (int i = 0; i < MAX_BONE_INFLUENCE; i++)
    {
        if (input.boneWeights[i] > 0.0)
        {
            uint boneIndex = input.boneIndices[i];
            float weight = input.boneWeights[i];

            float4 bonePos = mul(localPos, boneMatrices[boneIndex]);
            skinnedPos += bonePos * weight;
        }
    }

    // Normalize in case weights don't sum to 1
    skinnedPos.w = 1.0;
    localPos = skinnedPos;
#endif

#ifdef INSTANCED
    // Reconstruct world matrix from instance rows
    float4x4 world = float4x4(
        input.instanceRow0,
        input.instanceRow1,
        input.instanceRow2,
        input.instanceRow3
    );

    float4 worldPos = mul(localPos, world);
#else
    float4 worldPos = mul(localPos, worldMatrix);
#endif

    // Transform to light space
    output.position = mul(worldPos, lightViewProjection);

    return output;
}
