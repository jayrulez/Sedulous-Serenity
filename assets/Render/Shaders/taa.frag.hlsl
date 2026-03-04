// TAA Resolve Fragment Shader
// Temporal anti-aliasing via motion-vector reprojection with neighborhood clamping.

cbuffer TAAParams : register(b0)
{
    float2 TexelSize;
    float FirstFrame; // 1.0 = first frame (no history), 0.0 = normal
    float _Pad;
};

Texture2D CurrentColor : register(t0);
Texture2D HistoryColor : register(t1);
Texture2D MotionVectors : register(t2);

SamplerState LinearSampler : register(s0);
SamplerState PointSampler : register(s1);

struct FragmentInput
{
    float4 Position : SV_Position;
    float2 TexCoord : TEXCOORD0;
};

// Convert RGB to luminance for weighting
float Luminance(float3 color)
{
    return dot(color, float3(0.2126, 0.7152, 0.0722));
}

// Tonemap for neighborhood clamping in perceptual space (reduces flickering)
float3 ReinhardTonemap(float3 c) { return c / (1.0 + Luminance(c)); }
float3 ReinhardInverse(float3 c) { return c / (1.0 - Luminance(c)); }

// Catmull-Rom bicubic history sampling (5 bilinear taps from a 4x4 kernel).
// Much sharper than bilinear — prevents the progressive blur from repeated
// bilinear resampling across frames.
float3 SampleHistoryCatmullRom(float2 uv)
{
    float2 position = uv / TexelSize;
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

    float2 tc0  = (centerPosition - 1.0) * TexelSize;
    float2 tc3  = (centerPosition + 2.0) * TexelSize;
    float2 tc12 = (centerPosition + offset12) * TexelSize;

    // 5-tap cross pattern covering the 4x4 kernel
    float3 result =
        HistoryColor.SampleLevel(LinearSampler, float2(tc12.x, tc12.y), 0).rgb * (w12.x * w12.y) +
        HistoryColor.SampleLevel(LinearSampler, float2(tc0.x,  tc12.y), 0).rgb * (w0.x  * w12.y) +
        HistoryColor.SampleLevel(LinearSampler, float2(tc3.x,  tc12.y), 0).rgb * (w3.x  * w12.y) +
        HistoryColor.SampleLevel(LinearSampler, float2(tc12.x, tc0.y),  0).rgb * (w12.x * w0.y)  +
        HistoryColor.SampleLevel(LinearSampler, float2(tc12.x, tc3.y),  0).rgb * (w12.x * w3.y);

    float totalWeight = (w12.x * w12.y) + (w0.x * w12.y) + (w3.x * w12.y) + (w12.x * w0.y) + (w12.x * w3.y);
    result /= totalWeight;

    return max(result, 0.0);
}

float4 main(FragmentInput input) : SV_Target
{
    float2 uv = input.TexCoord;

    // Sample current color (point sample for exact texel)
    float3 currentColor = CurrentColor.Sample(PointSampler, uv).rgb;

    // First frame — no history, use current color directly
    if (FirstFrame > 0.5)
        return float4(currentColor, 1.0);

    // Read motion vector (point sample for exact velocity)
    float2 velocity = MotionVectors.Sample(PointSampler, uv).rg;

    // Reproject: motion vector is (currentNDC - prevNDC) * 0.5 which maps to UV offset
    float2 historyUV = uv - velocity;

    // If reprojected UV is outside the screen, use current color
    if (historyUV.x < 0.0 || historyUV.x > 1.0 || historyUV.y < 0.0 || historyUV.y > 1.0)
        return float4(currentColor, 1.0);

    // Sample history with Catmull-Rom bicubic (sharper than bilinear)
    float3 historyColor = SampleHistoryCatmullRom(historyUV);

    // Neighborhood clamping: 3x3 box (9 taps) of current color in tonemapped space
    // More stable than 5-tap cross — reduces frame-to-frame oscillation
    float3 c0 = ReinhardTonemap(currentColor);
    float3 c1 = ReinhardTonemap(CurrentColor.Sample(PointSampler, uv + float2(-TexelSize.x, -TexelSize.y)).rgb);
    float3 c2 = ReinhardTonemap(CurrentColor.Sample(PointSampler, uv + float2(           0, -TexelSize.y)).rgb);
    float3 c3 = ReinhardTonemap(CurrentColor.Sample(PointSampler, uv + float2( TexelSize.x, -TexelSize.y)).rgb);
    float3 c4 = ReinhardTonemap(CurrentColor.Sample(PointSampler, uv + float2(-TexelSize.x,            0)).rgb);
    float3 c5 = ReinhardTonemap(CurrentColor.Sample(PointSampler, uv + float2( TexelSize.x,            0)).rgb);
    float3 c6 = ReinhardTonemap(CurrentColor.Sample(PointSampler, uv + float2(-TexelSize.x,  TexelSize.y)).rgb);
    float3 c7 = ReinhardTonemap(CurrentColor.Sample(PointSampler, uv + float2(           0,  TexelSize.y)).rgb);
    float3 c8 = ReinhardTonemap(CurrentColor.Sample(PointSampler, uv + float2( TexelSize.x,  TexelSize.y)).rgb);

    // Use variance clip: mean + stddev based clipping for smoother results
    float3 mean = (c0 + c1 + c2 + c3 + c4 + c5 + c6 + c7 + c8) / 9.0;
    float3 sq = (c0*c0 + c1*c1 + c2*c2 + c3*c3 + c4*c4 + c5*c5 + c6*c6 + c7*c7 + c8*c8) / 9.0;
    float3 stddev = sqrt(max(sq - mean * mean, 0.0));

    // Clip history to mean +/- 1.25 stddev (wider = more stable, less flickering)
    float3 neighborMin = mean - stddev * 1.25;
    float3 neighborMax = mean + stddev * 1.25;

    float3 historyTM = ReinhardTonemap(historyColor);
    float3 clampedHistory = clamp(historyTM, neighborMin, neighborMax);

    // Reduce blend when history was clipped significantly (reject stale data)
    float clipDist = length(clampedHistory - historyTM);
    float clipRejection = saturate(clipDist * 4.0); // 0 = no clip, 1 = heavily clipped

    clampedHistory = ReinhardInverse(clampedHistory);

    // Blend factor: 0.95 for static (5% current = stable), reduced for fast motion
    float speed = length(velocity / TexelSize); // pixel-space speed
    float blendFactor = lerp(0.95, 0.7, saturate(speed / 20.0));
    blendFactor *= (1.0 - clipRejection * 0.3); // Mild history rejection when clipped

    // Final blend
    float3 result = lerp(currentColor, clampedHistory, blendFactor);

    return float4(result, 1.0);
}
