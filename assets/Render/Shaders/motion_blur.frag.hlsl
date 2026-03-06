// Motion Blur Fragment Shader
// Per-pixel directional blur along motion vector velocity.

cbuffer MotionBlurParams : register(b0)
{
    float Intensity;       // velocity multiplier
    float MaxBlurPixels;   // max blur length in pixels (default 20)
    float2 TexelSize;      // 1/width, 1/height
};

Texture2D SourceTexture : register(t0);
Texture2D MotionVectors : register(t1);
SamplerState LinearSampler : register(s0);
SamplerState PointSampler : register(s1);

struct FragmentInput
{
    float4 Position : SV_Position;
    float2 TexCoord : TEXCOORD0;
};

static const int SampleCount = 9;

float4 main(FragmentInput input) : SV_Target
{
    float2 uv = input.TexCoord;

    // Read per-pixel velocity (NDC space, RG16Float)
    float2 velocity = MotionVectors.Sample(PointSampler, uv).rg * Intensity;

    // Clamp velocity length to MaxBlurPixels in UV space
    float velLen = length(velocity / TexelSize); // in pixels
    if (velLen > MaxBlurPixels)
    {
        velocity *= MaxBlurPixels / velLen;
    }

    // Skip blur for nearly static pixels
    if (length(velocity) < TexelSize.x * 0.5)
    {
        return float4(SourceTexture.Sample(LinearSampler, uv).rgb, 1.0);
    }

    // Sample along velocity direction
    float3 colorAccum = float3(0.0, 0.0, 0.0);

    for (int i = 0; i < SampleCount; i++)
    {
        // Distribute samples from -0.5..+0.5 of the velocity range
        float t = (float(i) / float(SampleCount - 1)) - 0.5;
        float2 sampleUV = uv + velocity * t;
        colorAccum += SourceTexture.Sample(LinearSampler, sampleUV).rgb;
    }

    colorAccum /= float(SampleCount);
    return float4(colorAccum, 1.0);
}
