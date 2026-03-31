// Hi-Z (Hierarchical-Z) Pyramid Generator
//
// Two modes controlled by HIZ_MIP0 define:
// - HIZ_MIP0: Reads depth buffer as Texture2D (SHADER_READ_ONLY layout), writes Hi-Z mip 0
// - Default:  Reads previous Hi-Z mip as RWTexture2D (GENERAL layout), writes next mip
//
// This split avoids per-mip layout transition issues on Vulkan. The depth buffer
// is in SHADER_READ_ONLY (from the render graph), while Hi-Z mips stay in GENERAL.

cbuffer HiZParams : register(b0)
{
    uint2 OutputSize;
    uint2 InputSize;
    uint  MipLevel;
    uint3 _pad;
};

#ifdef HIZ_MIP0
// Mip 0: read depth buffer as sampled texture (SHADER_READ_ONLY layout)
Texture2D<float> InputDepth : register(t1);
#else
// Mip 1+: read previous Hi-Z mip as storage image (GENERAL layout)
RWTexture2D<float> InputMip : register(u1);
#endif

// Output: current mip level
RWTexture2D<float> OutputMip : register(u2);

[numthreads(8, 8, 1)]
void CSMain(uint3 dtid : SV_DispatchThreadID)
{
    if (dtid.x >= OutputSize.x || dtid.y >= OutputSize.y)
        return;

    uint2 srcBase = dtid.xy * 2;

    // Clamp source coordinates to input size
    uint2 s00 = min(srcBase + uint2(0, 0), InputSize - 1);
    uint2 s10 = min(srcBase + uint2(1, 0), InputSize - 1);
    uint2 s01 = min(srcBase + uint2(0, 1), InputSize - 1);
    uint2 s11 = min(srcBase + uint2(1, 1), InputSize - 1);

#ifdef HIZ_MIP0
    float d00 = InputDepth.Load(int3(s00, 0));
    float d10 = InputDepth.Load(int3(s10, 0));
    float d01 = InputDepth.Load(int3(s01, 0));
    float d11 = InputDepth.Load(int3(s11, 0));
#else
    float d00 = InputMip[s00];
    float d10 = InputMip[s10];
    float d01 = InputMip[s01];
    float d11 = InputMip[s11];
#endif

    // Max = conservative (furthest depth)
    float maxDepth = max(max(d00, d10), max(d01, d11));

    OutputMip[dtid.xy] = maxDepth;
}
