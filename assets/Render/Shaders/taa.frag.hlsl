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

    // Sample history at reprojected UV (bilinear for smooth reprojection)
    float3 historyColor = HistoryColor.Sample(LinearSampler, historyUV).rgb;

    // Neighborhood clamping: sample 3x3 cross (5 taps) of current color
    // This prevents ghosting by constraining history to plausible values
    float3 c0 = ReinhardTonemap(currentColor);
    float3 c1 = ReinhardTonemap(CurrentColor.Sample(PointSampler, uv + float2(-TexelSize.x, 0)).rgb);
    float3 c2 = ReinhardTonemap(CurrentColor.Sample(PointSampler, uv + float2(TexelSize.x, 0)).rgb);
    float3 c3 = ReinhardTonemap(CurrentColor.Sample(PointSampler, uv + float2(0, -TexelSize.y)).rgb);
    float3 c4 = ReinhardTonemap(CurrentColor.Sample(PointSampler, uv + float2(0, TexelSize.y)).rgb);

    float3 neighborMin = min(c0, min(min(c1, c2), min(c3, c4)));
    float3 neighborMax = max(c0, max(max(c1, c2), max(c3, c4)));

    // Clamp history to neighborhood bounds (in tonemapped space)
    float3 clampedHistory = clamp(ReinhardTonemap(historyColor), neighborMin, neighborMax);
    clampedHistory = ReinhardInverse(clampedHistory);

    // Blend factor: 0.9 for static, reduced for high-velocity pixels
    float speed = length(velocity) * 1000.0; // Scale to meaningful range
    float blendFactor = lerp(0.95, 0.5, saturate(speed));

    // Final blend
    float3 result = lerp(currentColor, clampedHistory, blendFactor);

    return float4(result, 1.0);
}
