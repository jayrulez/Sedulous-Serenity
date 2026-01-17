// Hi-Z Occlusion Culling Compute Shader
// Tests AABB bounds against hierarchical-Z buffer for visibility

// Cull parameters
cbuffer CullParams : register(b0)
{
    float4x4 ViewProjection;  // View-projection matrix
    float2 ScreenSize;        // Screen dimensions
    float2 InvScreenSize;     // 1.0 / ScreenSize
    uint ObjectCount;         // Number of objects to cull
    uint HiZMipCount;         // Number of mip levels in Hi-Z
    uint _Padding0;
    uint _Padding1;
};

// AABB bounding box (24 bytes)
struct AABB
{
    float3 Min;
    float3 Max;
};

// Input: bounding boxes (read-only)
StructuredBuffer<AABB> InputBounds : register(t0);

// Hi-Z pyramid texture
Texture2D<float> HiZPyramid : register(t1);

// Hi-Z sampler (point filtering)
SamplerState HiZSampler : register(s0);

// Output: visibility flags (1 = visible, 0 = occluded)
RWStructuredBuffer<uint> OutputVisibility : register(u0);

// Transform a point from world space to NDC
float4 WorldToNDC(float3 worldPos)
{
    return mul(ViewProjection, float4(worldPos, 1.0));
}

// Convert NDC to screen coordinates
float2 NDCToScreen(float2 ndc)
{
    return (ndc * 0.5 + 0.5) * ScreenSize;
}

// Calculate the mip level based on screen-space size
uint CalculateMipLevel(float2 screenSize)
{
    // Use the larger dimension to select mip level
    float maxDim = max(screenSize.x, screenSize.y);

    // Calculate mip level: log2 of pixel count / thread group size
    // We want to sample at a level where the bound covers roughly one pixel
    uint mipLevel = (uint)max(0, ceil(log2(maxDim)));

    // Clamp to available mip levels
    return min(mipLevel, HiZMipCount - 1);
}

// Sample Hi-Z at a specific mip level
float SampleHiZ(float2 screenPos, uint mipLevel)
{
    // Calculate UV at the given mip level
    float2 mipSize = ScreenSize / pow(2.0, (float)mipLevel);
    float2 uv = screenPos / ScreenSize;

    // Use Load with mip level instead of Sample for precise mip access
    int2 texelCoord = int2(uv * mipSize);
    return HiZPyramid.Load(int3(texelCoord, mipLevel));
}

[numthreads(64, 1, 1)]
void main(uint3 dispatchThreadId : SV_DispatchThreadID)
{
    uint objectIndex = dispatchThreadId.x;

    // Bounds check
    if (objectIndex >= ObjectCount)
        return;

    AABB bounds = InputBounds[objectIndex];

    // Generate all 8 corners of the AABB
    float3 corners[8];
    corners[0] = float3(bounds.Min.x, bounds.Min.y, bounds.Min.z);
    corners[1] = float3(bounds.Max.x, bounds.Min.y, bounds.Min.z);
    corners[2] = float3(bounds.Min.x, bounds.Max.y, bounds.Min.z);
    corners[3] = float3(bounds.Max.x, bounds.Max.y, bounds.Min.z);
    corners[4] = float3(bounds.Min.x, bounds.Min.y, bounds.Max.z);
    corners[5] = float3(bounds.Max.x, bounds.Min.y, bounds.Max.z);
    corners[6] = float3(bounds.Min.x, bounds.Max.y, bounds.Max.z);
    corners[7] = float3(bounds.Max.x, bounds.Max.y, bounds.Max.z);

    // Transform corners to NDC and find screen-space bounds
    float minDepth = 1.0;  // Closest depth (smallest Z)
    float2 screenMin = float2(1e10, 1e10);
    float2 screenMax = float2(-1e10, -1e10);
    bool anyBehindCamera = false;
    bool allBehindCamera = true;

    [unroll]
    for (int i = 0; i < 8; i++)
    {
        float4 clip = WorldToNDC(corners[i]);

        // Check if behind camera (w <= 0)
        if (clip.w <= 0)
        {
            anyBehindCamera = true;
            continue;
        }

        allBehindCamera = false;

        // Perspective divide
        float3 ndc = clip.xyz / clip.w;

        // Update min depth (closest point)
        // NDC depth is 0 at near, 1 at far
        minDepth = min(minDepth, ndc.z);

        // Convert to screen coordinates
        float2 screen = NDCToScreen(ndc.xy);
        screenMin = min(screenMin, screen);
        screenMax = max(screenMax, screen);
    }

    // If all corners are behind camera, the object is not visible
    if (allBehindCamera)
    {
        OutputVisibility[objectIndex] = 0;
        return;
    }

    // If any corner is behind camera, conservatively mark as visible
    // (the object crosses the near plane, complex case)
    if (anyBehindCamera)
    {
        OutputVisibility[objectIndex] = 1;
        return;
    }

    // Clamp screen bounds to viewport
    screenMin = max(screenMin, float2(0, 0));
    screenMax = min(screenMax, ScreenSize);

    // Check if entirely off-screen
    if (screenMin.x >= ScreenSize.x || screenMin.y >= ScreenSize.y ||
        screenMax.x <= 0 || screenMax.y <= 0)
    {
        OutputVisibility[objectIndex] = 0;
        return;
    }

    // Check for invalid depth (behind far plane)
    if (minDepth >= 1.0)
    {
        OutputVisibility[objectIndex] = 0;
        return;
    }

    // Calculate screen-space size and mip level
    float2 screenSize = screenMax - screenMin;
    uint mipLevel = CalculateMipLevel(screenSize);

    // Sample Hi-Z at the 4 corners of the screen-space bounds
    // We need the maximum depth in the Hi-Z region
    float hiZMaxDepth = 0.0;

    // Sample at corners and center for better coverage
    float2 samplePoints[5];
    samplePoints[0] = screenMin;
    samplePoints[1] = float2(screenMax.x, screenMin.y);
    samplePoints[2] = float2(screenMin.x, screenMax.y);
    samplePoints[3] = screenMax;
    samplePoints[4] = (screenMin + screenMax) * 0.5;

    [unroll]
    for (int j = 0; j < 5; j++)
    {
        float hiZ = SampleHiZ(samplePoints[j], mipLevel);
        hiZMaxDepth = max(hiZMaxDepth, hiZ);
    }

    // Occlusion test:
    // If the object's closest depth is greater than the Hi-Z max depth,
    // the object is completely occluded
    bool isOccluded = (minDepth > hiZMaxDepth);

    OutputVisibility[objectIndex] = isOccluded ? 0 : 1;
}
