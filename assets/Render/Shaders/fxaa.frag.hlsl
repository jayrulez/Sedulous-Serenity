// FXAA 3.11 Quality Fragment Shader
// Fast Approximate Anti-Aliasing based on the NVIDIA FXAA 3.11 algorithm.

cbuffer FXAAParams : register(b0)
{
    float2 TexelSize;
    float SubpixelQuality;  // 0.0 = off, 0.75 = default, 1.0 = max
    float EdgeThreshold;    // 0.166 = default, lower = more edges detected
};

Texture2D SourceTexture : register(t0);
SamplerState LinearSampler : register(s0);

struct FragmentInput
{
    float4 Position : SV_Position;
    float2 TexCoord : TEXCOORD0;
};

// Compute perceptual luminance from linear RGB
float FxaaLuma(float3 rgb)
{
    return dot(rgb, float3(0.299, 0.587, 0.114));
}

float4 main(FragmentInput input) : SV_Target
{
    float2 uv = input.TexCoord;

    // Sample center and 4 neighbors
    float3 rgbM  = SourceTexture.Sample(LinearSampler, uv).rgb;
    float3 rgbN  = SourceTexture.Sample(LinearSampler, uv + float2(0, -TexelSize.y)).rgb;
    float3 rgbS  = SourceTexture.Sample(LinearSampler, uv + float2(0,  TexelSize.y)).rgb;
    float3 rgbW  = SourceTexture.Sample(LinearSampler, uv + float2(-TexelSize.x, 0)).rgb;
    float3 rgbE  = SourceTexture.Sample(LinearSampler, uv + float2( TexelSize.x, 0)).rgb;

    float lumaM = FxaaLuma(rgbM);
    float lumaN = FxaaLuma(rgbN);
    float lumaS = FxaaLuma(rgbS);
    float lumaW = FxaaLuma(rgbW);
    float lumaE = FxaaLuma(rgbE);

    // Find min/max luma in the cross neighborhood
    float lumaMin = min(lumaM, min(min(lumaN, lumaS), min(lumaW, lumaE)));
    float lumaMax = max(lumaM, max(max(lumaN, lumaS), max(lumaW, lumaE)));
    float lumaRange = lumaMax - lumaMin;

    // Skip AA if contrast is below threshold (not an edge)
    float edgeThresholdMin = 0.0312; // Minimum edge detection threshold
    if (lumaRange < max(edgeThresholdMin, lumaMax * EdgeThreshold))
        return float4(rgbM, 1.0);

    // Sample diagonal neighbors for sub-pixel quality
    float3 rgbNW = SourceTexture.Sample(LinearSampler, uv + float2(-TexelSize.x, -TexelSize.y)).rgb;
    float3 rgbNE = SourceTexture.Sample(LinearSampler, uv + float2( TexelSize.x, -TexelSize.y)).rgb;
    float3 rgbSW = SourceTexture.Sample(LinearSampler, uv + float2(-TexelSize.x,  TexelSize.y)).rgb;
    float3 rgbSE = SourceTexture.Sample(LinearSampler, uv + float2( TexelSize.x,  TexelSize.y)).rgb;

    float lumaNW = FxaaLuma(rgbNW);
    float lumaNE = FxaaLuma(rgbNE);
    float lumaSW = FxaaLuma(rgbSW);
    float lumaSE = FxaaLuma(rgbSE);

    // Compute sub-pixel aliasing factor
    float lumaL = (lumaN + lumaS + lumaW + lumaE) * 0.25;
    float rangeL = abs(lumaL - lumaM);
    float blendL = max(0.0, (rangeL / lumaRange) - SubpixelQuality * 0.5);
    blendL = min(blendL * (1.0 / (1.0 - SubpixelQuality * 0.5)), 1.0);

    // Determine edge direction (horizontal vs vertical)
    float edgeH = abs(lumaNW + lumaNE - 2.0 * lumaN)
                + abs(lumaW  + lumaE  - 2.0 * lumaM) * 2.0
                + abs(lumaSW + lumaSE - 2.0 * lumaS);
    float edgeV = abs(lumaNW + lumaSW - 2.0 * lumaW)
                + abs(lumaN  + lumaS  - 2.0 * lumaM) * 2.0
                + abs(lumaNE + lumaSE - 2.0 * lumaE);

    bool isHorizontal = (edgeH >= edgeV);

    // Choose step direction along the edge
    float stepLength = isHorizontal ? TexelSize.y : TexelSize.x;

    float luma1 = isHorizontal ? lumaN : lumaW;
    float luma2 = isHorizontal ? lumaS : lumaE;
    float gradient1 = abs(luma1 - lumaM);
    float gradient2 = abs(luma2 - lumaM);

    bool is1Steeper = gradient1 >= gradient2;
    float gradientScaled = 0.25 * max(gradient1, gradient2);

    // Step perpendicular to the edge
    if (!is1Steeper) stepLength = -stepLength;

    float lumaLocalAverage = 0.0;
    if (is1Steeper)
        lumaLocalAverage = 0.5 * (luma1 + lumaM);
    else
        lumaLocalAverage = 0.5 * (luma2 + lumaM);

    // Shift UV to the edge
    float2 currentUV = uv;
    if (isHorizontal)
        currentUV.y += stepLength * 0.5;
    else
        currentUV.x += stepLength * 0.5;

    // Edge search along the detected edge direction
    float2 offset = isHorizontal ? float2(TexelSize.x, 0) : float2(0, TexelSize.y);

    float2 uv1 = currentUV - offset;
    float2 uv2 = currentUV + offset;

    float lumaEnd1 = FxaaLuma(SourceTexture.Sample(LinearSampler, uv1).rgb) - lumaLocalAverage;
    float lumaEnd2 = FxaaLuma(SourceTexture.Sample(LinearSampler, uv2).rgb) - lumaLocalAverage;

    bool reached1 = abs(lumaEnd1) >= gradientScaled;
    bool reached2 = abs(lumaEnd2) >= gradientScaled;
    bool reachedBoth = reached1 && reached2;

    // Search up to 12 steps along the edge
    static const int SEARCH_STEPS = 12;
    static const float QUALITY[12] = { 1.0, 1.0, 1.0, 1.0, 1.0, 1.5, 2.0, 2.0, 2.0, 2.0, 4.0, 8.0 };

    [unroll]
    for (int i = 0; i < SEARCH_STEPS && !reachedBoth; i++)
    {
        if (!reached1) {
            uv1 -= offset * QUALITY[i];
            lumaEnd1 = FxaaLuma(SourceTexture.Sample(LinearSampler, uv1).rgb) - lumaLocalAverage;
        }
        if (!reached2) {
            uv2 += offset * QUALITY[i];
            lumaEnd2 = FxaaLuma(SourceTexture.Sample(LinearSampler, uv2).rgb) - lumaLocalAverage;
        }
        reached1 = abs(lumaEnd1) >= gradientScaled;
        reached2 = abs(lumaEnd2) >= gradientScaled;
        reachedBoth = reached1 && reached2;
    }

    // Compute distance to edge endpoints
    float distance1 = isHorizontal ? (uv.x - uv1.x) : (uv.y - uv1.y);
    float distance2 = isHorizontal ? (uv2.x - uv.x) : (uv2.y - uv.y);

    bool isDirection1 = distance1 < distance2;
    float distanceFinal = min(distance1, distance2);
    float edgeLength = distance1 + distance2;

    // Sub-pixel offset along the edge
    float pixelOffset = -distanceFinal / edgeLength + 0.5;

    // Check if the luma at the closest end is in the correct direction
    bool isLumaCenterSmaller = lumaM < lumaLocalAverage;
    bool correctVariation = ((isDirection1 ? lumaEnd1 : lumaEnd2) < 0.0) != isLumaCenterSmaller;

    float finalOffset = correctVariation ? pixelOffset : 0.0;

    // Sub-pixel quality: blend toward average if aliased
    float lumaAverage = (1.0 / 12.0) * (2.0 * (lumaN + lumaS + lumaW + lumaE)
        + lumaNW + lumaNE + lumaSW + lumaSE);
    float subPixelOffset1 = saturate(abs(lumaAverage - lumaM) / lumaRange);
    float subPixelOffset2 = (-2.0 * subPixelOffset1 + 3.0) * subPixelOffset1 * subPixelOffset1;
    float subPixelOffsetFinal = subPixelOffset2 * subPixelOffset2 * SubpixelQuality;

    finalOffset = max(finalOffset, subPixelOffsetFinal);

    // Final UV offset and sample
    float2 finalUV = uv;
    if (isHorizontal)
        finalUV.y += finalOffset * stepLength;
    else
        finalUV.x += finalOffset * stepLength;

    float3 finalColor = SourceTexture.Sample(LinearSampler, finalUV).rgb;
    return float4(finalColor, 1.0);
}
