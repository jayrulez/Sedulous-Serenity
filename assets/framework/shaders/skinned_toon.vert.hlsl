// Skinned Toon Material Vertex Shader
// Applies skeletal animation with toon shading support
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
    float3 worldPos : TEXCOORD0;
    float3 worldNormal : TEXCOORD1;
    float2 uv : TEXCOORD2;
    float3 tint : COLOR0;
    float viewZ : TEXCOORD3;
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
    float4 tintColor;  // xyz = tint color, w = unused
};

// Bone transforms - up to 128 bones (binding 2)
cbuffer BoneBuffer : register(b2, space1)
{
    float4x4 boneMatrices[128];
};

VSOutput main(VSInput input)
{
    VSOutput output;

    // Compute skinned position and normal
    float4 skinnedPos = float4(0, 0, 0, 0);
    float3 skinnedNormal = float3(0, 0, 0);

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
            skinnedNormal += weight * mul(input.normal, (float3x3)bone);
        }
    }

    // Transform to world space (row-vector math)
    float4 worldPos = mul(skinnedPos, model);
    output.worldPos = worldPos.xyz;

    // Transform normal to world space
    float3x3 normalMatrix = (float3x3)model;
    output.worldNormal = normalize(mul(skinnedNormal, normalMatrix));

    output.uv = input.texCoord;
    output.tint = tintColor.xyz;

    // Compute view-space Z for shadow cascade selection
    float4 viewPos = mul(worldPos, view);
    output.viewZ = viewPos.z;

    // Transform to clip space
    output.position = mul(worldPos, viewProjection);

    return output;
}
