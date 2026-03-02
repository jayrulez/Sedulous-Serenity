// Auto-Exposure: Adaptation Compute Shader
// Scans the histogram to find weighted average luminance,
// then computes adapted exposure with temporal smoothing.
// [numthreads(256,1,1)] — one thread per histogram bin

cbuffer AdaptParams : register(b0)
{
    float MinLogLuminance;
    float LogLuminanceRange;
    float DeltaTime;
    float AdaptSpeed;
    float MinExposure;
    float MaxExposure;
    float PixelCount;       // Total pixel count for normalization
    float _Pad;
};

ByteAddressBuffer Histogram : register(t0);          // 256 x uint32
RWByteAddressBuffer ExposureBuffer : register(u0);   // [0]=current exposure, [4]=target exposure (as float bits)

// Shared memory for parallel reduction
groupshared uint gs_Histogram[256];
groupshared float gs_PartialSum[256];

[numthreads(256, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID, uint GI : SV_GroupIndex)
{
    // Load histogram bin count into shared memory
    uint binCount = Histogram.Load(GI * 4);
    gs_Histogram[GI] = binCount;

    GroupMemoryBarrierWithGroupSync();

    // Exclude darkest/brightest 5% of pixels
    // First: compute total pixel count from histogram (more accurate than PixelCount param)
    gs_PartialSum[GI] = (float)binCount;
    GroupMemoryBarrierWithGroupSync();

    // Parallel reduction for total count
    [unroll]
    for (uint s = 128; s > 0; s >>= 1)
    {
        if (GI < s)
            gs_PartialSum[GI] += gs_PartialSum[GI + s];
        GroupMemoryBarrierWithGroupSync();
    }

    float totalPixels = gs_PartialSum[0];
    GroupMemoryBarrierWithGroupSync();

    if (totalPixels < 1.0)
    {
        // No pixels processed; keep current exposure
        if (GI == 0)
        {
            float currentExposure = asfloat(ExposureBuffer.Load(0));
            if (currentExposure <= 0.0)
                currentExposure = 1.0;
            ExposureBuffer.Store(0, asuint(currentExposure));
        }
        return;
    }

    // Compute weighted average log-luminance, excluding bottom/top 5%
    float lowThreshold = totalPixels * 0.05;
    float highThreshold = totalPixels * 0.95;

    // Each thread computes contribution of its bin
    float runningCount = 0.0;
    for (uint i = 0; i < GI; i++)
        runningCount += (float)gs_Histogram[i];

    float binStart = runningCount;
    float binEnd = runningCount + (float)gs_Histogram[GI];

    // Clamp to the [lowThreshold, highThreshold] range
    float clampedStart = max(binStart, lowThreshold);
    float clampedEnd = min(binEnd, highThreshold);
    float effectiveCount = max(clampedEnd - clampedStart, 0.0);

    // Log-luminance at the center of this bin
    float binCenter = (GI == 0) ? MinLogLuminance : (MinLogLuminance + ((float)GI - 0.5) / 254.0 * LogLuminanceRange);
    float weightedLum = binCenter * effectiveCount;

    gs_PartialSum[GI] = weightedLum;
    GroupMemoryBarrierWithGroupSync();

    // Parallel reduction for weighted sum
    [unroll]
    for (uint s2 = 128; s2 > 0; s2 >>= 1)
    {
        if (GI < s2)
            gs_PartialSum[GI] += gs_PartialSum[GI + s2];
        GroupMemoryBarrierWithGroupSync();
    }

    // Thread 0 computes final exposure
    if (GI == 0)
    {
        float validPixels = max(highThreshold - lowThreshold, 1.0);
        float avgLogLum = gs_PartialSum[0] / validPixels;
        float avgLum = exp2(avgLogLum);

        // Target exposure: expose for 18% grey (key value 0.18)
        float targetExposure = 0.18 / max(avgLum, 0.001);
        targetExposure = clamp(targetExposure, MinExposure, MaxExposure);

        // Temporal adaptation
        float currentExposure = asfloat(ExposureBuffer.Load(0));
        if (currentExposure <= 0.0)
            currentExposure = 1.0; // Initialize on first frame

        float adaptedExposure = currentExposure + (targetExposure - currentExposure) * saturate(1.0 - exp(-DeltaTime * AdaptSpeed));

        ExposureBuffer.Store(0, asuint(adaptedExposure));
        ExposureBuffer.Store(4, asuint(targetExposure));
    }
}
