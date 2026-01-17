// Forward PBR Vertex Shader
// Full vertex transformation with normal/tangent for PBR lighting
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
    float4x4 NormalMatrix; // Transpose of inverse world matrix
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
#ifdef NORMAL_MAP
    float4 Tangent : TANGENT;
#endif
#ifdef SKINNED
    uint4 BoneIndices : BLENDINDICES;
    float4 BoneWeights : BLENDWEIGHT;
#endif
};

struct VertexOutput
{
    float4 Position : SV_Position;
    float3 WorldPosition : TEXCOORD0;
    float3 WorldNormal : TEXCOORD1;
    float2 TexCoord : TEXCOORD2;
#ifdef NORMAL_MAP
    float3 WorldTangent : TEXCOORD3;
    float3 WorldBitangent : TEXCOORD4;
#endif
#ifdef RECEIVE_SHADOWS
    float4 ShadowCoord : TEXCOORD5;
#endif
};

VertexOutput main(VertexInput input)
{
    VertexOutput output;

    float3 localPos = input.Position;
    float3 localNormal = input.Normal;
#ifdef NORMAL_MAP
    float3 localTangent = input.Tangent.xyz;
#endif

#ifdef SKINNED
    // Apply bone transforms
    float4x4 skinMatrix =
        BoneMatrices[input.BoneIndices.x] * input.BoneWeights.x +
        BoneMatrices[input.BoneIndices.y] * input.BoneWeights.y +
        BoneMatrices[input.BoneIndices.z] * input.BoneWeights.z +
        BoneMatrices[input.BoneIndices.w] * input.BoneWeights.w;

    localPos = mul(float4(localPos, 1.0), skinMatrix).xyz;
    localNormal = mul(float4(localNormal, 0.0), skinMatrix).xyz;
#ifdef NORMAL_MAP
    localTangent = mul(float4(localTangent, 0.0), skinMatrix).xyz;
#endif
#endif

    float4 worldPos = mul(float4(localPos, 1.0), WorldMatrix);
    output.Position = mul(worldPos, ViewProjectionMatrix);
    output.WorldPosition = worldPos.xyz;
    output.WorldNormal = normalize(mul(float4(localNormal, 0.0), NormalMatrix).xyz);
    output.TexCoord = input.TexCoord;

#ifdef NORMAL_MAP
    output.WorldTangent = normalize(mul(float4(localTangent, 0.0), NormalMatrix).xyz);
    output.WorldBitangent = cross(output.WorldNormal, output.WorldTangent) * input.Tangent.w;
#endif

    return output;
}
