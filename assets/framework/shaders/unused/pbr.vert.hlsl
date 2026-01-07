// PBR Vertex Shader - Metallic-Roughness Workflow
// Supports optional: SKINNED, INSTANCED variants

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

// Object uniform buffer (binding 2 - per-draw)
cbuffer ObjectUniforms : register(b2)
{
    float4x4 model;
    float4x4 normalMatrix;
};

#ifdef SKINNED
// Bone matrices (binding 3)
cbuffer BoneUniforms : register(b3)
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
    // Vertex skinning
    float4x4 skinMatrix =
        input.boneWeights.x * bones[input.boneIndices.x] +
        input.boneWeights.y * bones[input.boneIndices.y] +
        input.boneWeights.z * bones[input.boneIndices.z] +
        input.boneWeights.w * bones[input.boneIndices.w];

    localPos = mul(skinMatrix, localPos);
    localNormal = mul((float3x3)skinMatrix, localNormal);
#endif

    // Transform to world space
    float4 worldPos = mul(model, localPos);
    output.worldPos = worldPos.xyz;
    output.worldNormal = normalize(mul((float3x3)normalMatrix, localNormal));
    output.uv = input.uv;

    // Transform to clip space
    output.position = mul(viewProjection, worldPos);

    return output;
}
