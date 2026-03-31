#pragma pack_matrix(row_major)

// ---- Vertex Shader (fullscreen triangle) ----

struct PSInput
{
    float4 Position : SV_Position;
    float2 TexCoord : TEXCOORD0;
};

Texture2D    SceneColor    : register(t0);
Texture2D    History       : register(t1);
Texture2D    MotionVectors : register(t2);
Texture2D    DepthBuffer   : register(t3);
SamplerState LinearSampler : register(s4);
SamplerState PointSampler  : register(s5);

cbuffer TAAParams : register(b6)
{
    float  BlendFactor;       // Static blend (0.95 = 95% history)
    uint   FrameNumber;
    float2 ScreenSize;
    float2 JitterOffset;
    float2 PrevJitterOffset;
    uint   HistoryValid;
    float  VarianceClipGamma;
    float  VelocityWeightScale;
    float  JitterScale;
    float  _pad;
};

PSInput VSMain(uint vertexID : SV_VertexID)
{
    PSInput output;
    output.TexCoord = float2((vertexID << 1) & 2, vertexID & 2);
    output.Position = float4(output.TexCoord * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
    return output;
}

// ---- Helper Functions ----

float Luminance(float3 c)
{
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

// Reinhard tonemap / inverse for perceptual-space clamping.
// Compresses HDR so bright speculars don't dominate the AABB.
float3 Tonemap(float3 c) { return c / (1.0 + Luminance(c)); }
float3 TonemapInverse(float3 c) { return c / max(1.0 - Luminance(c), 0.001); }

// RGB <-> YCoCg (decorrelates channels for tighter variance clipping)
float3 RGBToYCoCg(float3 rgb)
{
    return float3(
         0.25 * rgb.r + 0.5 * rgb.g + 0.25 * rgb.b,
         0.5  * rgb.r                - 0.5  * rgb.b,
        -0.25 * rgb.r + 0.5 * rgb.g - 0.25 * rgb.b
    );
}

float3 YCoCgToRGB(float3 ycocg)
{
    return float3(
        ycocg.x + ycocg.y - ycocg.z,
        ycocg.x            + ycocg.z,
        ycocg.x - ycocg.y - ycocg.z
    );
}

// Catmull-Rom bicubic history sampling (5 bilinear taps from a 4x4 kernel).
// Much sharper than bilinear — prevents progressive blur from repeated
// bilinear resampling across frames.
float3 SampleHistoryCatmullRom(float2 uv)
{
    float2 texSize = ScreenSize;
    float2 position = uv * texSize;
    float2 centerPosition = floor(position - 0.5) + 0.5;
    float2 f = position - centerPosition;
    float2 f2 = f * f;
    float2 f3 = f * f2;

    // Catmull-Rom spline weights
    float2 w0 = -0.5 * f3 + f2 - 0.5 * f;
    float2 w1 =  1.5 * f3 - 2.5 * f2 + 1.0;
    float2 w2 = -1.5 * f3 + 2.0 * f2 + 0.5 * f;
    float2 w3 =  0.5 * f3 - 0.5 * f2;

    // Combine adjacent pairs for optimized bilinear fetches
    float2 w12 = w1 + w2;
    float2 offset12 = w2 / max(w12, 1e-6);

    float2 tc0  = (centerPosition - 1.0) / texSize;
    float2 tc3  = (centerPosition + 2.0) / texSize;
    float2 tc12 = (centerPosition + offset12) / texSize;

    // 5-tap cross pattern covering the 4x4 kernel
    float3 result =
        History.SampleLevel(LinearSampler, float2(tc12.x, tc12.y), 0).rgb * (w12.x * w12.y) +
        History.SampleLevel(LinearSampler, float2(tc0.x,  tc12.y), 0).rgb * (w0.x  * w12.y) +
        History.SampleLevel(LinearSampler, float2(tc3.x,  tc12.y), 0).rgb * (w3.x  * w12.y) +
        History.SampleLevel(LinearSampler, float2(tc12.x, tc0.y),  0).rgb * (w12.x * w0.y)  +
        History.SampleLevel(LinearSampler, float2(tc12.x, tc3.y),  0).rgb * (w12.x * w3.y);

    float totalWeight = (w12.x * w12.y) + (w0.x * w12.y) + (w3.x * w12.y) + (w12.x * w0.y) + (w12.x * w3.y);
    result /= totalWeight;

    return max(result, 0.0);
}

// ---- Pixel Shader ----

float4 PSMain(PSInput input) : SV_Target0
{
    float2 uv = input.TexCoord;
    float2 texelSize = 1.0 / ScreenSize;

    // Sample current frame at pixel center (jittered position).
    // We intentionally do NOT unjitter — each frame's unique sub-pixel
    // sample is what produces anti-aliasing through temporal accumulation.
    float3 currentColor = SceneColor.SampleLevel(PointSampler, uv, 0).rgb;

    // No valid history — output current directly
    if (HistoryValid == 0)
        return float4(currentColor, 1.0);

    // Find closest depth in 3x3 neighborhood (use that pixel's motion vector).
    // Reduces silhouette ghosting by picking foreground motion at edges.
    // Skip sky pixels (depth >= 1.0) to avoid bad reprojection at horizon.
    float closestDepth = 1.0;
    float2 closestOffset = float2(0.0, 0.0);

    [unroll]
    for (int y = -1; y <= 1; y++)
    {
        [unroll]
        for (int x = -1; x <= 1; x++)
        {
            float2 offset = float2(x, y) * texelSize;
            float d = DepthBuffer.SampleLevel(PointSampler, uv + offset, 0).r;
            if (d < closestDepth && d < 0.9999)
            {
                closestDepth = d;
                closestOffset = offset;
            }
        }
    }

    // Sample motion vector at closest depth pixel
    float2 velocity = MotionVectors.SampleLevel(PointSampler, uv + closestOffset, 0).rg;

    // Reproject to history UV (velocity is in pixel space, convert to UV)
    float2 historyUV = uv - velocity / ScreenSize;

    // Reject if history UV is out of bounds
    if (any(historyUV < 0.0) || any(historyUV > 1.0))
        return float4(currentColor, 1.0);

    // Sample history with Catmull-Rom bicubic (sharper than bilinear,
    // prevents progressive blur from repeated resampling across frames)
    float3 historyColor = SampleHistoryCatmullRom(historyUV);

    // Tonemap before neighborhood clamping (perceptual space)
    float3 currentTM = Tonemap(currentColor);
    float3 historyTM = Tonemap(historyColor);

    // Neighborhood clamping: 3x3 variance clipping in tonemapped YCoCg space
    float3 m1 = float3(0, 0, 0);
    float3 m2 = float3(0, 0, 0);

    [unroll]
    for (int ny = -1; ny <= 1; ny++)
    {
        [unroll]
        for (int nx = -1; nx <= 1; nx++)
        {
            float3 s = Tonemap(SceneColor.SampleLevel(PointSampler, uv + float2(nx, ny) * texelSize, 0).rgb);
            float3 sYCoCg = RGBToYCoCg(s);
            m1 += sYCoCg;
            m2 += sYCoCg * sYCoCg;
        }
    }

    float3 mean = m1 / 9.0;
    float3 stddev = sqrt(max(m2 / 9.0 - mean * mean, 0.0));

    float3 aabbMin = mean - VarianceClipGamma * stddev;
    float3 aabbMax = mean + VarianceClipGamma * stddev;

    // Clamp history to AABB
    float3 historyYCoCg = RGBToYCoCg(historyTM);
    float3 clampedYCoCg = clamp(historyYCoCg, aabbMin, aabbMax);
    float3 clampedTM = YCoCgToRGB(clampedYCoCg);

    // Blend factor: high for static (stable), reduced for fast motion
    // Legacy-style: lerp(0.95, 0.7, speed/20) with mild clip rejection
    float speed = length(velocity);  // pixel-space speed
    float blendFactor = lerp(BlendFactor, max(BlendFactor - 0.25, 0.5), saturate(speed / 20.0));

    // Mild history rejection when heavily clipped (up to 30% reduction)
    float clipDist = length(historyYCoCg - clampedYCoCg);
    float clipRejection = saturate(clipDist * 4.0);
    blendFactor *= (1.0 - clipRejection * 0.3);

    // Blend in tonemapped space, then inverse tonemap back to HDR
    float3 blendedTM = lerp(currentTM, clampedTM, blendFactor);
    float3 result = TonemapInverse(blendedTM);

    return float4(max(result, 0.0), 1.0);
}
