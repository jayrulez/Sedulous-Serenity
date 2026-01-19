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

// Compute cofactor matrix (adjugate) of upper 3x3 for normal transformation
// This correctly handles non-uniform scale without requiring matrix inverse
float3x3 ComputeCofactorMatrix(float4x4 m)
{
    float3x3 result;
    result[0][0] = m[1][1] * m[2][2] - m[1][2] * m[2][1];
    result[0][1] = m[1][2] * m[2][0] - m[1][0] * m[2][2];
    result[0][2] = m[1][0] * m[2][1] - m[1][1] * m[2][0];
    result[1][0] = m[0][2] * m[2][1] - m[0][1] * m[2][2];
    result[1][1] = m[0][0] * m[2][2] - m[0][2] * m[2][0];
    result[1][2] = m[0][1] * m[2][0] - m[0][0] * m[2][1];
    result[2][0] = m[0][1] * m[1][2] - m[0][2] * m[1][1];
    result[2][1] = m[0][2] * m[1][0] - m[0][0] * m[1][2];
    result[2][2] = m[0][0] * m[1][1] - m[0][1] * m[1][0];
    return result;
}

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
    // Compute normal matrix (cofactor/adjugate handles non-uniform scale)
    float3x3 instanceNormalMatrix = ComputeCofactorMatrix(instanceWorldMatrix);
    float3 worldNormal = normalize(mul(localNormal, instanceNormalMatrix));
#ifdef NORMAL_MAP
    float3 worldTangent = normalize(mul(localTangent, instanceNormalMatrix));
#endif
#else
    float4 worldPos = mul(float4(localPos, 1.0), WorldMatrix);
    float3 worldNormal = normalize(mul(float4(localNormal, 0.0), NormalMatrix).xyz);
#ifdef NORMAL_MAP
    float3 worldTangent = normalize(mul(float4(localTangent, 0.0), NormalMatrix).xyz);
#endif
#endif

    output.Position = mul(worldPos, ViewProjectionMatrix);
    output.WorldPosition = worldPos.xyz;
    output.WorldNormal = worldNormal;
    output.TexCoord = input.TexCoord;

#ifdef NORMAL_MAP
    output.WorldTangent = worldTangent;
    output.WorldBitangent = cross(output.WorldNormal, output.WorldTangent) * input.Tangent.w;
#endif

    return output;
}
