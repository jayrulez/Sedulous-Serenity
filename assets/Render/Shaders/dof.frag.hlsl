// Depth of Field Fragment Shader
// Single-pass Poisson disc gather blur based on circle-of-confusion from depth.

cbuffer DOFParams : register(b0)
{
    float FocusDistance;   // world-space focus distance
    float FocusRange;      // transition width (sharp → full blur)
    float BokehSize;       // max blur radius in pixels
    float NearPlane;
    float FarPlane;
    float2 TexelSize;      // 1/width, 1/height
    float _Pad;
};

Texture2D SourceTexture : register(t0);
Texture2D DepthTexture : register(t1);
SamplerState LinearSampler : register(s0);
SamplerState PointSampler : register(s1);

struct FragmentInput
{
    float4 Position : SV_Position;
    float2 TexCoord : TEXCOORD0;
};

// Linearize depth from [0,1] to view-space distance
float LinearizeDepth(float d)
{
    return NearPlane * FarPlane / (FarPlane - d * (FarPlane - NearPlane));
}

// 16-sample Poisson disc (unit radius, pre-normalized)
static const float2 PoissonDisc[16] =
{
    float2(-0.94201624, -0.39906216),
    float2( 0.94558609, -0.76890725),
    float2(-0.09418410, -0.92938870),
    float2( 0.34495938,  0.29387760),
    float2(-0.91588581,  0.45771432),
    float2(-0.81544232, -0.87912464),
    float2(-0.38277543,  0.27676845),
    float2( 0.97484398,  0.75648379),
    float2( 0.44323325, -0.97511554),
    float2( 0.53742981, -0.47373420),
    float2(-0.26496911, -0.41893023),
    float2( 0.79197514,  0.19090188),
    float2(-0.24188840,  0.99706507),
    float2(-0.81409955,  0.91437590),
    float2( 0.19984126,  0.78641367),
    float2( 0.14383161, -0.14100790)
};

float4 main(FragmentInput input) : SV_Target
{
    float2 uv = input.TexCoord;

    // Center pixel
    float3 centerColor = SourceTexture.Sample(LinearSampler, uv).rgb;
    float centerDepth = LinearizeDepth(DepthTexture.Sample(PointSampler, uv).r);

    // Circle of confusion: signed (-1 near, +1 far), 0 = in focus
    float coc = clamp((centerDepth - FocusDistance) / max(FocusRange, 0.001), -1.0, 1.0);
    float absCoc = abs(coc);

    // Skip blur if in focus
    if (absCoc < 0.01)
        return float4(centerColor, 1.0);

    // Blur radius in UV space
    float2 blurRadius = absCoc * BokehSize * TexelSize;

    // Gather samples
    float3 colorAccum = centerColor;
    float weightAccum = 1.0;

    for (int i = 0; i < 16; i++)
    {
        float2 sampleUV = uv + PoissonDisc[i] * blurRadius;
        float3 sampleColor = SourceTexture.Sample(LinearSampler, sampleUV).rgb;
        float sampleDepth = LinearizeDepth(DepthTexture.Sample(PointSampler, sampleUV).r);
        float sampleCoc = clamp((sampleDepth - FocusDistance) / max(FocusRange, 0.001), -1.0, 1.0);

        // Weight: far-field samples only contribute if they're also out of focus
        // Near-field samples bleed onto sharp neighbors (foreground blur)
        float weight = 1.0;
        if (sampleCoc > 0.0 && coc < 0.0)
        {
            // Far sample on near pixel — don't bleed background onto foreground
            weight = 0.0;
        }
        else if (sampleCoc < 0.0)
        {
            // Near-field: always bleeds (foreground bokeh)
            weight = abs(sampleCoc);
        }
        else
        {
            weight = abs(sampleCoc);
        }

        colorAccum += sampleColor * weight;
        weightAccum += weight;
    }

    float3 blurred = colorAccum / max(weightAccum, 0.001);
    return float4(blurred, 1.0);
}
