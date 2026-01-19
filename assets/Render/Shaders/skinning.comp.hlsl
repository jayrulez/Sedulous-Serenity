// GPU Skinning Compute Shader
// Transforms vertices by bone matrices on the GPU
// Uses ByteAddressBuffer to avoid HLSL struct alignment/padding issues
#pragma pack_matrix(row_major)

// DEBUG: Uncomment to bypass skinning and just pass through vertices
//#define DEBUG_BYPASS_SKINNING 1

// Skinning parameters
cbuffer SkinningParams : register(b0)
{
    uint VertexCount;
    uint BoneCount;
    uint2 _Padding;
};

// Buffers - using ByteAddressBuffer for explicit layout control
StructuredBuffer<float4x4> BoneMatrices : register(t0);  // Bone matrices
ByteAddressBuffer SourceVertices : register(t1);          // Source vertices (72 bytes each)
RWByteAddressBuffer OutputVertices : register(u0);        // Output vertices (48 bytes each)

// Input vertex layout (Sedulous.Geometry.SkinnedVertex - 72 bytes packed):
// Offset 0:  Position (float3, 12 bytes)
// Offset 12: Normal (float3, 12 bytes)
// Offset 24: TexCoord (float2, 8 bytes)
// Offset 32: Color (uint, 4 bytes)
// Offset 36: Tangent (float3, 12 bytes)
// Offset 48: BoneIndices (uint2, 8 bytes - 4 x uint16 packed)
// Offset 56: BoneWeights (float4, 16 bytes)

// Output vertex layout (VertexLayoutHelper.Mesh - 48 bytes packed):
// Offset 0:  Position (float3, 12 bytes)
// Offset 12: Normal (float3, 12 bytes)
// Offset 24: TexCoord (float2, 8 bytes)
// Offset 32: Color (uint, 4 bytes)
// Offset 36: Tangent (float3, 12 bytes)

[numthreads(64, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint vertexIndex = DTid.x;
    if (vertexIndex >= VertexCount)
        return;

    // Calculate byte offsets
    uint srcOffset = vertexIndex * 72;
    uint dstOffset = vertexIndex * 48;

    // Read input vertex data with explicit offsets
    float3 position = asfloat(SourceVertices.Load3(srcOffset + 0));
    float3 normal = asfloat(SourceVertices.Load3(srcOffset + 12));
    float2 texCoord = asfloat(SourceVertices.Load2(srcOffset + 24));
    uint color = SourceVertices.Load(srcOffset + 32);
    float3 tangent = asfloat(SourceVertices.Load3(srcOffset + 36));
    uint2 boneIndicesPacked = SourceVertices.Load2(srcOffset + 48);
    float4 boneWeights = asfloat(SourceVertices.Load4(srcOffset + 56));

    float3 outPosition;
    float3 outNormal;
    float3 outTangent;

#ifdef DEBUG_BYPASS_SKINNING
    // DEBUG: Just copy vertices without skinning transformation
    outPosition = position;
    outNormal = normal;
    outTangent = tangent;
#else
    // Unpack bone indices from 2 uint32s containing 4 uint16s
    uint boneIndex0 = boneIndicesPacked.x & 0xFFFF;
    uint boneIndex1 = (boneIndicesPacked.x >> 16) & 0xFFFF;
    uint boneIndex2 = boneIndicesPacked.y & 0xFFFF;
    uint boneIndex3 = (boneIndicesPacked.y >> 16) & 0xFFFF;

    // Calculate blended bone matrix
    float4x4 skinMatrix =
        BoneMatrices[boneIndex0] * boneWeights.x +
        BoneMatrices[boneIndex1] * boneWeights.y +
        BoneMatrices[boneIndex2] * boneWeights.z +
        BoneMatrices[boneIndex3] * boneWeights.w;

    // Transform position
    outPosition = mul(float4(position, 1.0), skinMatrix).xyz;

    // Transform normal (assuming uniform scale)
    outNormal = normalize(mul(float4(normal, 0.0), skinMatrix).xyz);

    // Transform tangent
    outTangent = normalize(mul(float4(tangent, 0.0), skinMatrix).xyz);
#endif

    // Write output vertex with explicit offsets
    OutputVertices.Store3(dstOffset + 0, asuint(outPosition));
    OutputVertices.Store3(dstOffset + 12, asuint(outNormal));
    OutputVertices.Store2(dstOffset + 24, asuint(texCoord));
    OutputVertices.Store(dstOffset + 32, color);
    OutputVertices.Store3(dstOffset + 36, asuint(outTangent));
}
