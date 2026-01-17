// Hi-Z Pyramid Build Compute Shader
// Generates hierarchical-Z buffer for occlusion culling
// Uses max reduction to find maximum depth in each 2x2 block

// Input depth buffer (mip level N)
Texture2D<float> InputDepth : register(t0);

// Output Hi-Z (mip level N+1)
RWTexture2D<float> OutputHiZ : register(u0);

// Sampler for depth reads
SamplerState DepthSampler : register(s0);

// Build parameters
cbuffer BuildParams : register(b0)
{
    uint2 InputSize;     // Size of input mip level
    uint2 OutputSize;    // Size of output mip level
    uint  MipLevel;      // Current mip level being generated
    uint  _Padding0;
    uint  _Padding1;
    uint  _Padding2;
};

// 8x8 thread group
[numthreads(8, 8, 1)]
void main(uint3 dispatchThreadId : SV_DispatchThreadID)
{
    // Output pixel coordinate
    uint2 outCoord = dispatchThreadId.xy;

    // Check bounds
    if (outCoord.x >= OutputSize.x || outCoord.y >= OutputSize.y)
        return;

    // Calculate input coordinates for 2x2 block
    uint2 inCoord = outCoord * 2;

    // Sample 4 depth values from input
    // For mip 0, we read from the depth buffer directly
    // For higher mips, we read from the previous Hi-Z mip
    float d00 = InputDepth[inCoord + uint2(0, 0)];
    float d10 = InputDepth[inCoord + uint2(1, 0)];
    float d01 = InputDepth[inCoord + uint2(0, 1)];
    float d11 = InputDepth[inCoord + uint2(1, 1)];

    // Handle edge cases where we might read outside bounds
    // Use the maximum representable depth (1.0) for out-of-bounds
    if (inCoord.x + 1 >= InputSize.x)
    {
        d10 = d00;
        d11 = d01;
    }
    if (inCoord.y + 1 >= InputSize.y)
    {
        d01 = d00;
        d11 = d10;
    }

    // Max reduction - we want the MAXIMUM depth in the block
    // Objects are occluded if their min depth > Hi-Z max depth
    float maxDepth = max(max(d00, d10), max(d01, d11));

    // Write to output
    OutputHiZ[outCoord] = maxDepth;
}
