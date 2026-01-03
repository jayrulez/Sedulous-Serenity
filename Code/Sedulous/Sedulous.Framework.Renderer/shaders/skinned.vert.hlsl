// Skinned Vertex Shader - Skeletal animation with up to 4 bone influences

#define MAX_BONES 128

struct VSInput
{
    float3 position : POSITION;
    float3 normal : NORMAL;
    float2 uv : TEXCOORD0;
    uint4 joints : BLENDINDICES;  // Bone indices (packed as uint16x4)
    float4 weights : BLENDWEIGHT; // Bone weights
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

// Object uniform buffer (binding 2)
cbuffer ObjectUniforms : register(b2)
{
    float4x4 model;
    float4x4 normalMatrix;
};

// Bone matrices buffer (binding 3)
cbuffer BoneMatrices : register(b3)
{
    float4x4 bones[MAX_BONES];
};

VSOutput main(VSInput input)
{
    VSOutput output;

    // Compute skinned position and normal
    float4x4 skinMatrix =
        bones[input.joints.x] * input.weights.x +
        bones[input.joints.y] * input.weights.y +
        bones[input.joints.z] * input.weights.z +
        bones[input.joints.w] * input.weights.w;

    float4 skinnedPos = mul(skinMatrix, float4(input.position, 1.0));
    float3 skinnedNormal = mul((float3x3)skinMatrix, input.normal);

    // Apply model transform
    float4 worldPos = mul(model, skinnedPos);
    output.position = mul(viewProjection, worldPos);
    output.worldPos = worldPos.xyz;
    output.worldNormal = mul((float3x3)normalMatrix, skinnedNormal);
    output.uv = input.uv;

    return output;
}
