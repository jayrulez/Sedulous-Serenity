// Auto-Exposure: Luminance Histogram Compute Shader
// Reads scene color, computes log-luminance, atomically increments 256-bin histogram.
// [numthreads(16,16,1)]

cbuffer HistogramParams : register(b0)
{
    uint Width;
    uint Height;
    float MinLogLuminance;  // e.g. -8.0
    float LogLuminanceRange; // e.g. 16.0 (covers -8 to +8)
};

Texture2D<float4> SceneColor : register(t0);
RWByteAddressBuffer Histogram : register(u0); // 256 x uint32 = 1024 bytes

// Luminance from linear RGB (Rec. 709)
float Luminance(float3 color)
{
    return dot(color, float3(0.2126, 0.7152, 0.0722));
}

[numthreads(16, 16, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    if (DTid.x >= Width || DTid.y >= Height)
        return;

    float3 color = SceneColor.Load(int3(DTid.xy, 0)).rgb;
    float lum = Luminance(color);

    // Map luminance to histogram bin
    uint bin;
    if (lum < 0.001)
    {
        // Very dark pixels go to bin 0
        bin = 0;
    }
    else
    {
        float logLum = log2(lum);
        float normalized = (logLum - MinLogLuminance) / LogLuminanceRange;
        normalized = saturate(normalized);
        bin = (uint)(normalized * 254.0 + 1.0); // Bins 1-255 for valid luminance
    }

    // Atomic increment
    Histogram.InterlockedAdd(bin * 4, 1u);
}
