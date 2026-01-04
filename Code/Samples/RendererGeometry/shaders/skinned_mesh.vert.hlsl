// Skinned Mesh Vertex Shader
// Applies skeletal animation bone transforms to vertices

cbuffer CameraBuffer : register(b0)
{
    column_major float4x4 viewProjection;
    column_major float4x4 view;
    column_major float4x4 projection;
    float3 cameraPosition;
    float _pad0;
};

cbuffer ObjectBuffer : register(b1)
{
    column_major float4x4 model;
    float4 baseColor;
};

// Bone transforms - up to 128 bones
// Use column_major to match our Matrix4x4 storage format
cbuffer BoneBuffer : register(b2)
{
    column_major float4x4 boneMatrices[128];
};

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

struct PSInput
{
    float4 position : SV_Position;
    float3 worldNormal : NORMAL;
    float2 texCoord : TEXCOORD0;
    float3 worldPos : TEXCOORD1;
};

PSInput main(VSInput input)
{
    PSInput output;

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

            skinnedPos += weight * mul(bone, float4(input.position, 1.0));
            skinnedNormal += weight * mul((float3x3)bone, input.normal);
        }
    }

    // Transform to world space
    float4 worldPos = mul(model, skinnedPos);
    output.position = mul(viewProjection, worldPos);
    output.worldPos = worldPos.xyz;

    // Transform normal to world space
    float3x3 normalMatrix = (float3x3)model;
    output.worldNormal = normalize(mul(normalMatrix, skinnedNormal));

    output.texCoord = input.texCoord;

    return output;
}
