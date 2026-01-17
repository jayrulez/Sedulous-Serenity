// GPU Skinning Compute Shader
// Transforms vertices by bone matrices on the GPU
#pragma pack_matrix(row_major)

// Input vertex format (must match source mesh)
struct SkinnedVertex
{
    float3 Position;
    float3 Normal;
    float4 Tangent;
    float2 TexCoord;
    uint4 BoneIndices;
    float4 BoneWeights;
};

// Output vertex format (skinned result)
struct OutputVertex
{
    float3 Position;
    float3 Normal;
    float4 Tangent;
    float2 TexCoord;
};

// Skinning parameters
cbuffer SkinningParams : register(b0)
{
    uint VertexCount;
    uint BoneCount;
    uint2 _Padding;
};

// Bone matrices (max 256 bones)
cbuffer BoneMatrices : register(b1)
{
    float4x4 Bones[256];
};

// Buffers
StructuredBuffer<SkinnedVertex> SourceVertices : register(t0);
RWStructuredBuffer<OutputVertex> OutputVertices : register(u0);

[numthreads(64, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint vertexIndex = DTid.x;
    if (vertexIndex >= VertexCount)
        return;

    SkinnedVertex input = SourceVertices[vertexIndex];
    OutputVertex output;

    // Calculate blended bone matrix
    float4x4 skinMatrix =
        Bones[input.BoneIndices.x] * input.BoneWeights.x +
        Bones[input.BoneIndices.y] * input.BoneWeights.y +
        Bones[input.BoneIndices.z] * input.BoneWeights.z +
        Bones[input.BoneIndices.w] * input.BoneWeights.w;

    // Transform position
    output.Position = mul(float4(input.Position, 1.0), skinMatrix).xyz;

    // Transform normal (assuming uniform scale)
    output.Normal = normalize(mul(float4(input.Normal, 0.0), skinMatrix).xyz);

    // Transform tangent
    output.Tangent.xyz = normalize(mul(float4(input.Tangent.xyz, 0.0), skinMatrix).xyz);
    output.Tangent.w = input.Tangent.w; // Preserve handedness

    // Pass through tex coords
    output.TexCoord = input.TexCoord;

    OutputVertices[vertexIndex] = output;
}
