// Film Grain Fragment Shader
// Hash-based noise overlay modulated by luminance (more grain in shadows).

cbuffer FilmGrainParams : register(b0)
{
    float Intensity;
    float Time;          // animated seed from engine time
    float2 ScreenSize;   // viewport resolution for pixel-scale noise
};

Texture2D SourceTexture : register(t0);
SamplerState LinearSampler : register(s0);

struct FragmentInput
{
    float4 Position : SV_Position;
    float2 TexCoord : TEXCOORD0;
};

// Hash-based pseudo-random noise (deterministic from 2D input)
float Hash(float2 p)
{
    float3 p3 = frac(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.x + p3.y) * p3.z);
}

float4 main(FragmentInput input) : SV_Target
{
    float3 color = SourceTexture.Sample(LinearSampler, input.TexCoord).rgb;

    // Pixel-space coordinates with temporal offset for animation
    float2 pixelCoord = input.TexCoord * ScreenSize + Time * 1000.0;

    // Generate noise (-0.5 to +0.5 range)
    float noise = Hash(pixelCoord) - 0.5;

    // Luminance-weighted: more grain in darker areas
    float luminance = dot(color, float3(0.2126, 0.7152, 0.0722));
    float grainWeight = 1.0 - luminance * 0.5;

    // Apply grain
    color += noise * Intensity * grainWeight;

    return float4(max(color, 0.0), 1.0);
}
