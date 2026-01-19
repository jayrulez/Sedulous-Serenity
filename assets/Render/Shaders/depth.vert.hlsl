// Depth Prepass Vertex Shader
// Renders depth-only for early-z and occlusion
#pragma pack_matrix(row_major)

// Camera uniform buffer
cbuffer CameraUniforms : register(b0)
{
    float4x4 ViewMatrix;
    float4x4 ProjectionMatrix;
    float4x4 ViewProjectionMatrix;
    float4x4 InvViewMatrix;
    float4x4 InvProjectionMatrix;
    float3 CameraPosition;
    float NearPlane;
    float3 CameraForward;
    float FarPlane;
};

// Per-object uniform buffer
cbuffer ObjectUniforms : register(b1)
{
    float4x4 WorldMatrix;
    float4x4 PrevWorldMatrix;
    float4x4 NormalMatrix; // Must match CPU struct layout (even if unused)
    uint ObjectID;
    uint MaterialID;
    float2 _Padding;
};

#ifdef SKINNED
// Bone transforms for skinned meshes
cbuffer BoneUniforms : register(b2)
{
    float4x4 BoneMatrices[256];
};
#endif

struct VertexInput
{
    float3 Position : POSITION;
    float3 Normal : NORMAL;
    float2 TexCoord : TEXCOORD0;
#ifdef SKINNED
    uint4 BoneIndices : BLENDINDICES;
    float4 BoneWeights : BLENDWEIGHT;
#endif
#ifdef INSTANCED
    // Instance data: world matrix as 4 float4 rows
    // DXC maps TEXCOORD3-6 to locations 5-8
    float4 InstanceWorldRow0 : TEXCOORD3;
    float4 InstanceWorldRow1 : TEXCOORD4;
    float4 InstanceWorldRow2 : TEXCOORD5;
    float4 InstanceWorldRow3 : TEXCOORD6;
#endif
};

struct VertexOutput
{
    float4 Position : SV_Position;
#ifdef ALPHA_TEST
    float2 TexCoord : TEXCOORD0;
#endif
};

VertexOutput main(VertexInput input)
{
    VertexOutput output;

    float3 localPos = input.Position;

#ifdef SKINNED
    // Apply bone transforms
    float4x4 skinMatrix =
        BoneMatrices[input.BoneIndices.x] * input.BoneWeights.x +
        BoneMatrices[input.BoneIndices.y] * input.BoneWeights.y +
        BoneMatrices[input.BoneIndices.z] * input.BoneWeights.z +
        BoneMatrices[input.BoneIndices.w] * input.BoneWeights.w;

    localPos = mul(float4(localPos, 1.0), skinMatrix).xyz;
#endif

#ifdef INSTANCED
    // Reconstruct world matrix from instance vertex attributes (rows)
    // Row-vector transform: pos * model
    float4x4 instanceWorldMatrix = float4x4(
        input.InstanceWorldRow0,
        input.InstanceWorldRow1,
        input.InstanceWorldRow2,
        input.InstanceWorldRow3
    );
    float4 worldPos = mul(float4(localPos, 1.0), instanceWorldMatrix);
#else
    float4 worldPos = mul(float4(localPos, 1.0), WorldMatrix);
#endif

    output.Position = mul(worldPos, ViewProjectionMatrix);

#ifdef ALPHA_TEST
    output.TexCoord = input.TexCoord;
#endif

    return output;
}
