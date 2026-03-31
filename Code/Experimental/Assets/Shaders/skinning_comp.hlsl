// GPU Skinning Compute Shader
// Transforms SkinnedVertex (72 bytes) → StaticMeshVertex (48 bytes)
// Also outputs previous-frame skinned positions for motion vectors.
//
// Uses ByteAddressBuffer for all storage buffers:
// - Vertex data: explicit byte offsets avoid HLSL struct alignment/padding issues.
// - Bone matrices: ByteAddressBuffer with manual float4x4 loading instead of
//   StructuredBuffer<float4x4> because #pragma pack_matrix(row_major) does not
//   apply to StructuredBuffer reads on DX12/DXIL (only affects cbuffers).
//   DXIL defaults to column-major interpretation, causing incorrect skinning.
//   SPIR-V correctly applies the RowMajor decoration, so Vulkan works either way.
//   Manual row loading via ByteAddressBuffer is correct on both backends.
//
// Bone buffer layout: [current matrices: BoneCount × 64B] [previous matrices: BoneCount × 64B]
// Previous matrices are at offset BoneCount in LoadBoneMatrix index space.
#pragma pack_matrix(row_major)

cbuffer SkinningParams : register(b0)
{
    uint VertexCount;
    uint BoneCount;
    uint2 _Padding;
};

// Bone matrices (current + previous skinning matrices)
// Register numbers match bind group layout binding indices.
// DXC applies SPIR-V shifts: t→+1000, u→+2000.
ByteAddressBuffer BoneMatrices : register(t1);

// Source vertices: SkinnedVertex layout (72 bytes per vertex)
ByteAddressBuffer SourceVertices : register(t2);

// Output vertices: StaticMeshVertex layout (48 bytes per vertex)
RWByteAddressBuffer OutputVertices : register(u3);

// Previous-frame skinned positions for motion vectors (12 bytes per vertex, float3)
RWByteAddressBuffer PrevOutputPositions : register(u4);

float4x4 LoadBoneMatrix(uint index)
{
    uint off = index * 64;
    float4 r0 = asfloat(BoneMatrices.Load4(off +  0));
    float4 r1 = asfloat(BoneMatrices.Load4(off + 16));
    float4 r2 = asfloat(BoneMatrices.Load4(off + 32));
    float4 r3 = asfloat(BoneMatrices.Load4(off + 48));
    return float4x4(r0, r1, r2, r3);
}

[numthreads(64, 1, 1)]
void CSMain(uint3 dtid : SV_DispatchThreadID)
{
    uint vid = dtid.x;
    if (vid >= VertexCount)
        return;

    uint srcBase = vid * 72;
    uint dstBase = vid * 48;

    // Read source vertex
    float3 position = asfloat(SourceVertices.Load3(srcBase + 0));
    float3 normal   = asfloat(SourceVertices.Load3(srcBase + 12));
    float2 texCoord = asfloat(SourceVertices.Load2(srcBase + 24));
    uint   color    = SourceVertices.Load(srcBase + 32);
    float3 tangent  = asfloat(SourceVertices.Load3(srcBase + 36));

    // Unpack bone indices: 4x uint16 packed into 2x uint32
    uint2 jointsPacked = SourceVertices.Load2(srcBase + 48);
    uint4 joints = uint4(
        jointsPacked.x & 0xFFFF,
        jointsPacked.x >> 16,
        jointsPacked.y & 0xFFFF,
        jointsPacked.y >> 16
    );

    float4 weights = asfloat(SourceVertices.Load4(srcBase + 56));

    // Blend current bone matrices (indices 0..BoneCount-1)
    float4x4 skinMatrix =
        LoadBoneMatrix(joints.x) * weights.x +
        LoadBoneMatrix(joints.y) * weights.y +
        LoadBoneMatrix(joints.z) * weights.z +
        LoadBoneMatrix(joints.w) * weights.w;

    // Transform position (w=1 for translation)
    float3 skinnedPos = mul(float4(position, 1.0), skinMatrix).xyz;

    // Transform normal and tangent (w=0, no translation, assumes uniform scale)
    float3 skinnedNormal  = normalize(mul(float4(normal, 0.0), skinMatrix).xyz);
    float3 skinnedTangent = normalize(mul(float4(tangent, 0.0), skinMatrix).xyz);

    // Write current-frame output vertex (48 bytes)
    OutputVertices.Store3(dstBase + 0,  asuint(skinnedPos));
    OutputVertices.Store3(dstBase + 12, asuint(skinnedNormal));
    OutputVertices.Store2(dstBase + 24, asuint(texCoord));
    OutputVertices.Store(dstBase + 32,  color);
    OutputVertices.Store3(dstBase + 36, asuint(skinnedTangent));

    // Blend previous bone matrices (indices BoneCount..2*BoneCount-1)
    float4x4 prevSkinMatrix =
        LoadBoneMatrix(joints.x + BoneCount) * weights.x +
        LoadBoneMatrix(joints.y + BoneCount) * weights.y +
        LoadBoneMatrix(joints.z + BoneCount) * weights.z +
        LoadBoneMatrix(joints.w + BoneCount) * weights.w;

    // Write previous-frame skinned position (12 bytes)
    float3 prevPos = mul(float4(position, 1.0), prevSkinMatrix).xyz;
    PrevOutputPositions.Store3(vid * 12, asuint(prevPos));
}
