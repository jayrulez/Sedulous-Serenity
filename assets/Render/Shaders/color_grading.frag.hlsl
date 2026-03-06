// Color Grading Fragment Shader
// Applies a 3D LUT stored as a 2D atlas (32 slices of 32x32 = 1024x32).

cbuffer ColorGradingParams : register(b0)
{
    float LUTSize;       // number of slices (32)
    float InvLUTSize;    // 1.0 / LUTSize
    float2 _Pad;
};

Texture2D SourceTexture : register(t0);
Texture2D LUTTexture : register(t1);
SamplerState LinearSampler : register(s0);
SamplerState LUTSampler : register(s1);

struct FragmentInput
{
    float4 Position : SV_Position;
    float2 TexCoord : TEXCOORD0;
};

float3 SampleLUT(float3 color)
{
    // Clamp to valid range
    color = saturate(color);

    float maxIndex = LUTSize - 1.0;

    // Blue channel determines which slice pair to interpolate
    float blue = color.b * maxIndex;
    float slice0 = floor(blue);
    float slice1 = min(slice0 + 1.0, maxIndex);
    float blendFactor = blue - slice0;

    // Red channel maps to horizontal within a slice
    // Green channel maps to vertical
    // Half-texel offset for correct sampling
    float halfTexel = 0.5 * InvLUTSize;
    float scale = (maxIndex / LUTSize); // (LUTSize-1)/LUTSize for proper mapping

    float r = color.r * scale + halfTexel;
    float g = color.g * scale + halfTexel;

    // UV for each slice (slice occupies InvLUTSize width in atlas)
    float2 uv0 = float2((slice0 * InvLUTSize) + r * InvLUTSize, g);
    float2 uv1 = float2((slice1 * InvLUTSize) + r * InvLUTSize, g);

    // Sample both slices and interpolate
    float3 color0 = LUTTexture.Sample(LUTSampler, uv0).rgb;
    float3 color1 = LUTTexture.Sample(LUTSampler, uv1).rgb;

    return lerp(color0, color1, blendFactor);
}

float4 main(FragmentInput input) : SV_Target
{
    float3 color = SourceTexture.Sample(LinearSampler, input.TexCoord).rgb;

    // Apply LUT color grading
    color = SampleLUT(color);

    return float4(color, 1.0);
}
