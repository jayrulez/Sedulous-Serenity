// Unified mesh vertex shader for RendererNG
// Supports static and skinned meshes via shader variants

#include "common.hlsli"

// ============================================================================
// Instance Data (vertex buffer slot 1 when instanced)
// ============================================================================

#ifdef INSTANCED
struct InstanceInput
{
    float4x4 WorldMatrix : INSTANCE_TRANSFORM;
    float4x4 NormalMatrix : INSTANCE_NORMAL;
    float4 CustomData : INSTANCE_DATA;
};
#else
// Single object uniform when not instanced
cbuffer ObjectUniforms : register(b2)
{
    float4x4 WorldMatrix;
    float4x4 NormalMatrix;
    float4 CustomData;
};
#endif

// ============================================================================
// Skinning Function
// ============================================================================

#ifdef SKINNED
void ApplySkinning(
    inout float3 position,
    inout float3 normal,
    inout float3 tangent,
    uint4 boneIndices,
    float4 boneWeights)
{
    float4x4 skinMatrix =
        Bones[boneIndices.x] * boneWeights.x +
        Bones[boneIndices.y] * boneWeights.y +
        Bones[boneIndices.z] * boneWeights.z +
        Bones[boneIndices.w] * boneWeights.w;

    position = mul(float4(position, 1.0), skinMatrix).xyz;
    normal = normalize(mul(float4(normal, 0.0), skinMatrix).xyz);
    tangent = normalize(mul(float4(tangent, 0.0), skinMatrix).xyz);
}
#endif

// ============================================================================
// Main Vertex Shader
// ============================================================================

#if defined(SKINNED)
VS_OUTPUT main(VS_INPUT_SKINNED input
#ifdef INSTANCED
    , InstanceInput instance
#endif
    )
#else
// Default: use standard mesh format (48 bytes)
VS_OUTPUT main(VS_INPUT_MESH input
#ifdef INSTANCED
    , InstanceInput instance
#endif
    )
#endif
{
    VS_OUTPUT output = (VS_OUTPUT)0;

    float3 localPos = input.Position;
    float3 localNormal = input.Normal;
    // Geometry format always has tangent
    float3 localTangent = input.Tangent;
    float tangentSign = 1.0; // Geometry format has no handedness in tangent.w

#if defined(SKINNED)
    ApplySkinning(localPos, localNormal, localTangent, input.Joints, input.Weights);
#endif

    // Get world/normal matrices
#ifdef INSTANCED
    float4x4 world = instance.WorldMatrix;
    float4x4 normalMat = instance.NormalMatrix;
#else
    float4x4 world = WorldMatrix;
    float4x4 normalMat = NormalMatrix;
#endif

    // Transform to world space
    float4 worldPos = mul(float4(localPos, 1.0), world);
    output.WorldPos = worldPos.xyz;

    // Transform normal to world space
    output.Normal = normalize(mul(float4(localNormal, 0.0), normalMat).xyz);

    // Transform to clip space
    output.Position = mul(worldPos, ViewProjectionMatrix);

    // Pass through texture coordinates
    output.TexCoord = input.TexCoord;

#ifdef NORMAL_MAP
    // Transform tangent to world space and compute bitangent
    output.Tangent = normalize(mul(float4(localTangent, 0.0), world).xyz);
    output.Bitangent = cross(output.Normal, output.Tangent) * tangentSign;
#endif

    return output;
}
