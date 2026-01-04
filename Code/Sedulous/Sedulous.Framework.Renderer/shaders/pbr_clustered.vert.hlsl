// PBR Vertex Shader with Clustered Lighting Support
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
    float4 clipPos : TEXCOORD3;  // For cluster lookup
};

// Camera uniform buffer (binding 0)
cbuffer CameraUniforms : register(b0)
{
    column_major float4x4 viewProjection;
    column_major float4x4 view;
    column_major float4x4 projection;
    float3 cameraPosition;
    float _pad0;
};

// Object uniform buffer (binding 3 - per-draw, b2 is lighting)
cbuffer ObjectUniforms : register(b3)
{
    column_major float4x4 model;
    column_major float4x4 normalMatrix;
};

#ifdef SKINNED
// Bone matrices (binding 4)
cbuffer BoneUniforms : register(b4)
{
    column_major float4x4 bones[256];
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
    output.clipPos = output.position;

    return output;
}
