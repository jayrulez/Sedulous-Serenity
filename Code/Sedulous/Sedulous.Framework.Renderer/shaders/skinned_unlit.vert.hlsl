// Skinned Unlit Vertex Shader
// Applies skeletal animation without lighting calculations
// Uses 3 bind groups: Scene (0), Object+Bones (1), Material (2)

#pragma pack_matrix(row_major)

struct VSInput
{
    float3 position : POSITION;
    float3 normal : NORMAL;
    float2 texCoord : TEXCOORD0;
    uint color : COLOR;
    float3 tangent : TANGENT;
    uint4 joints : BLENDINDICES;
    float4 weights : BLENDWEIGHT;
};

struct VSOutput
{
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
};

// ==================== Bind Group 0: Scene Resources ====================

// Camera uniform buffer (binding 0)
cbuffer CameraUniforms : register(b0, space0)
{
    float4x4 viewProjection;
    float4x4 view;
    float4x4 projection;
    float3 cameraPosition;
    float _pad0;
};

// ==================== Bind Group 1: Object + Bones ====================

// Object uniform buffer (binding 1)
cbuffer ObjectBuffer : register(b1, space1)
{
    float4x4 model;
    float4 reserved;  // Padding to match PBR layout
};

// Bone transforms - up to 128 bones (binding 2)
cbuffer BoneBuffer : register(b2, space1)
{
    float4x4 boneMatrices[128];
};

VSOutput main(VSInput input)
{
    VSOutput output;

    // Compute skinned position
    float4 skinnedPos = float4(0, 0, 0, 0);

    // Apply bone transforms weighted by blend weights
    [unroll]
    for (int i = 0; i < 4; i++)
    {
        float weight = input.weights[i];
        if (weight > 0.0)
        {
            uint boneIndex = input.joints[i];
            float4x4 bone = boneMatrices[boneIndex];

            // Row-major: multiply vector * matrix
            skinnedPos += weight * mul(float4(input.position, 1.0), bone);
        }
    }

    // Transform to world space (row-vector math)
    float4 worldPos = mul(skinnedPos, model);

    output.uv = input.texCoord;

    // Transform to clip space
    output.position = mul(worldPos, viewProjection);

    return output;
}
