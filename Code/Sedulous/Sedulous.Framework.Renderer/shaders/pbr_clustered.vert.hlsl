// PBR Vertex Shader with Clustered Lighting Support
// Supports optional: SKINNED, INSTANCED variants
// Uses row-major matrices with row-vector math: mul(vector, matrix)

#pragma pack_matrix(row_major)

struct VSInput
{
    float3 position : POSITION;
    float3 normal : NORMAL;
    float2 uv : TEXCOORD0;
#ifdef SKINNED
    float4 boneWeights : BLENDWEIGHT;
    uint4 boneIndices : BLENDINDICES;
#endif
};

struct VSOutput
{
    float4 position : SV_Position;
    float3 worldPos : TEXCOORD0;
    float3 worldNormal : TEXCOORD1;
    float2 uv : TEXCOORD2;
    float4 clipPos : TEXCOORD3;  // For cluster lookup
};

// Camera uniform buffer (binding 0)
cbuffer CameraUniforms : register(b0)
{
    float4x4 viewProjection;
    float4x4 view;
    float4x4 projection;
    float3 cameraPosition;
    float _pad0;
};

// Object uniform buffer (binding 3 - per-draw, b2 is lighting)
cbuffer ObjectUniforms : register(b3)
{
    float4x4 model;
    float4x4 normalMatrix;
};

#ifdef SKINNED
// Bone matrices (binding 4)
cbuffer BoneUniforms : register(b4)
{
    float4x4 bones[256];
};
#endif

VSOutput main(VSInput input
#ifdef INSTANCED
    , uint instanceID : SV_InstanceID
#endif
)
{
    VSOutput output;

    float4 localPos = float4(input.position, 1.0);
    float3 localNormal = input.normal;

#ifdef SKINNED
    // Vertex skinning (row-vector: pos * bone)
    float4x4 skinMatrix =
        input.boneWeights.x * bones[input.boneIndices.x] +
        input.boneWeights.y * bones[input.boneIndices.y] +
        input.boneWeights.z * bones[input.boneIndices.z] +
        input.boneWeights.w * bones[input.boneIndices.w];

    localPos = mul(localPos, skinMatrix);
    localNormal = mul(localNormal, (float3x3)skinMatrix);
#endif

    // Transform to world space (row-vector: pos * matrix)
    float4 worldPos = mul(localPos, model);
    output.worldPos = worldPos.xyz;
    output.worldNormal = normalize(mul(localNormal, (float3x3)normalMatrix));
    output.uv = input.uv;

    // Transform to clip space (row-vector: pos * matrix)
    output.position = mul(worldPos, viewProjection);
    output.clipPos = output.position;

    return output;
}
