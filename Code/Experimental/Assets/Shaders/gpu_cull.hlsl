// GPU Frustum + Hi-Z Occlusion Culling Compute Shader
// Tests each object against frustum planes and the Hi-Z depth pyramid.
// Visible objects atomically increment their draw group's indirect command.
#pragma pack_matrix(row_major)

cbuffer GPUCullUniforms : register(b0)
{
    float4 FrustumPlanes[6];   // xyz = normal, w = distance (normalized)
    float4x4 ViewProjection;   // for projecting AABB to screen space
    float2 HiZSize;            // Hi-Z mip 0 dimensions
    uint ObjectCount;
    uint DrawGroupCount;
    uint HiZMipCount;          // number of mip levels in Hi-Z pyramid
    uint EnableOcclusion;      // 0 = frustum only, 1 = frustum + Hi-Z
    uint2 _pad;
};

// Per-object data (GPUObjectData, 256 bytes each)
ByteAddressBuffer ObjectData : register(t1);

// Indirect draw commands — pre-filled with mesh info, we increment instanceCount
RWByteAddressBuffer IndirectCommands : register(u2);

// Instance mapping: objectIndex per visible instance
RWByteAddressBuffer InstanceMapping : register(u3);

// Hi-Z depth pyramid (read-only, for occlusion test)
Texture2D<float> HiZPyramid : register(t4);
SamplerState HiZSampler : register(s5);

// Object data byte offsets (must match GPUObjectData layout)
static const uint OBJ_STRIDE = 256;
static const uint OBJ_BOUNDS_MIN = 192;
static const uint OBJ_BOUNDS_MAX = 208;
static const uint OBJ_FLAGS = 232;
static const uint OBJ_DRAW_GROUP = 236;

// Indirect command byte offsets
static const uint CMD_STRIDE = 20;
static const uint CMD_INSTANCE_COUNT = 4;

// StaticMeshFlags.Visible = 1
static const uint FLAG_VISIBLE = 1;

// Frustum test: AABB (world-space min/max) against 6 planes
bool FrustumTestAABB(float3 bmin, float3 bmax)
{
    for (uint i = 0; i < 6; i++)
    {
        float3 n = FrustumPlanes[i].xyz;
        float  d = FrustumPlanes[i].w;

        float3 pVertex = float3(
            (n.x >= 0) ? bmax.x : bmin.x,
            (n.y >= 0) ? bmax.y : bmin.y,
            (n.z >= 0) ? bmax.z : bmin.z
        );

        if (dot(n, pVertex) + d < 0)
            return false;
    }
    return true;
}

// Hi-Z occlusion test: project AABB to screen, sample Hi-Z at appropriate mip
bool HiZTestAABB(float3 bmin, float3 bmax)
{
    // Project all 8 AABB corners to clip space
    float3 corners[8] = {
        float3(bmin.x, bmin.y, bmin.z),
        float3(bmax.x, bmin.y, bmin.z),
        float3(bmin.x, bmax.y, bmin.z),
        float3(bmax.x, bmax.y, bmin.z),
        float3(bmin.x, bmin.y, bmax.z),
        float3(bmax.x, bmin.y, bmax.z),
        float3(bmin.x, bmax.y, bmax.z),
        float3(bmax.x, bmax.y, bmax.z)
    };

    float2 screenMin = float2(1e10, 1e10);
    float2 screenMax = float2(-1e10, -1e10);
    float nearestZ = 1.0; // Furthest possible (standard depth: near=0, far=1)
    bool anyBehind = false;

    for (uint i = 0; i < 8; i++)
    {
        float4 clip = mul(float4(corners[i], 1.0), ViewProjection);

        // If any corner is behind the near plane, don't occlude (conservative)
        if (clip.w <= 0.0001)
        {
            anyBehind = true;
            continue;
        }

        float3 ndc = clip.xyz / clip.w;
        float2 screen = ndc.xy * 0.5 + 0.5;
        screen.y = 1.0 - screen.y; // Flip Y (NDC Y+ is up, UV Y+ is down)

        screenMin = min(screenMin, screen);
        screenMax = max(screenMax, screen);
        nearestZ = min(nearestZ, ndc.z);
    }

    // If any corner was behind the camera, be conservative
    if (anyBehind)
        return true;

    // If the AABB projects to nothing on screen, it's not visible
    if (screenMin.x >= screenMax.x || screenMin.y >= screenMax.y)
        return true; // Degenerate — be conservative

    // Clamp to [0,1]
    screenMin = saturate(screenMin);
    screenMax = saturate(screenMax);

    // Compute screen-space size in Hi-Z texels
    float2 sizePixels = (screenMax - screenMin) * HiZSize;
    float maxDim = max(sizePixels.x, sizePixels.y);

    // Objects smaller than 1 Hi-Z texel — can't reliably test, be conservative
    if (maxDim < 1.0)
        return true;

    // Select mip level where the AABB fits in ~1 texel
    float mipLevel = ceil(log2(maxDim));
    mipLevel = clamp(mipLevel, 0, (float)(HiZMipCount - 1));

    // Sample Hi-Z at all 4 corners of the screen rect for robustness.
    // Take the MAX of all samples — the most conservative depth.
    float h00 = HiZPyramid.SampleLevel(HiZSampler, float2(screenMin.x, screenMin.y), mipLevel);
    float h10 = HiZPyramid.SampleLevel(HiZSampler, float2(screenMax.x, screenMin.y), mipLevel);
    float h01 = HiZPyramid.SampleLevel(HiZSampler, float2(screenMin.x, screenMax.y), mipLevel);
    float h11 = HiZPyramid.SampleLevel(HiZSampler, float2(screenMax.x, screenMax.y), mipLevel);
    float hiZDepth = max(max(h00, h10), max(h01, h11));

    // Object's nearest depth > Hi-Z max depth → fully behind occluder → culled
    // Standard depth: near=0, far=1
    // Object's nearest depth > Hi-Z max depth → fully behind occluder → culled
    if (nearestZ > hiZDepth)
        return false; // Occluded

    return true; // Visible
}

[numthreads(64, 1, 1)]
void CSMain(uint3 dtid : SV_DispatchThreadID)
{
    uint objIdx = dtid.x;
    if (objIdx >= ObjectCount)
        return;

    uint objBase = objIdx * OBJ_STRIDE;

    // Load flags — skip invisible objects
    uint flags = ObjectData.Load(objBase + OBJ_FLAGS);
    if ((flags & FLAG_VISIBLE) == 0)
        return;

    // Load world-space AABB
    float3 boundsMin = asfloat(ObjectData.Load3(objBase + OBJ_BOUNDS_MIN));
    float3 boundsMax = asfloat(ObjectData.Load3(objBase + OBJ_BOUNDS_MAX));

    // Frustum culling
    if (!FrustumTestAABB(boundsMin, boundsMax))
        return;

    // Hi-Z occlusion culling
    if (EnableOcclusion != 0)
    {
        if (!HiZTestAABB(boundsMin, boundsMax))
            return;
    }

    // Object is visible — enable its indirect draw command.
    // Each object has its own command slot (pre-filled by CPU with mesh info, instanceCount=0).
    // GPU cull just sets instanceCount=1 for visible objects.
    // The command's firstInstance = objIdx, so the identity instance buffer provides ObjectIndex.
    IndirectCommands.Store(objIdx * CMD_STRIDE + CMD_INSTANCE_COUNT, 1);
}
