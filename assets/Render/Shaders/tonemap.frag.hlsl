// Tonemap Fragment Shader
// Applies configurable tonemapping to HDR scene color.
// Output is LDR linear — sRGB conversion handled by swapchain or later pass.

cbuffer TonemapParams : register(b0)
{
    float Exposure;
    int Operator;    // 0 = ACES, 1 = Reinhard, 2 = Uncharted2
    float2 _Pad;
};

Texture2D SourceTexture : register(t0);
SamplerState LinearSampler : register(s0);

struct FragmentInput
{
    float4 Position : SV_Position;
    float2 TexCoord : TEXCOORD0;
};

// ACES filmic tone mapping (Narkowicz approximation)
float3 ACESFilm(float3 x)
{
    float a = 2.51;
    float b = 0.03;
    float c = 2.43;
    float d = 0.59;
    float e = 0.14;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

// Reinhard tone mapping
float3 ReinhardTonemap(float3 x)
{
    return x / (x + 1.0);
}

// Uncharted 2 filmic curve helper
float3 Uncharted2Helper(float3 x)
{
    float A = 0.15; // Shoulder strength
    float B = 0.50; // Linear strength
    float C = 0.10; // Linear angle
    float D = 0.20; // Toe strength
    float E = 0.02; // Toe numerator
    float F = 0.30; // Toe denominator
    return ((x * (A * x + C * B) + D * E) / (x * (A * x + B) + D * F)) - E / F;
}

// Uncharted 2 filmic tone mapping
float3 Uncharted2Tonemap(float3 color)
{
    float W = 11.2; // Linear white point
    float3 curr = Uncharted2Helper(color);
    float3 whiteScale = 1.0 / Uncharted2Helper(W.xxx);
    return curr * whiteScale;
}

float4 main(FragmentInput input) : SV_Target
{
    // Sample source texture (HDR linear)
    float4 color = SourceTexture.Sample(LinearSampler, input.TexCoord);

    // Apply exposure before tone mapping
    color.rgb *= Exposure;

    // Apply selected tonemapping operator
    if (Operator == 1)
        color.rgb = ReinhardTonemap(color.rgb);
    else if (Operator == 2)
        color.rgb = Uncharted2Tonemap(color.rgb);
    else
        color.rgb = ACESFilm(color.rgb);

    return float4(color.rgb, 1.0);
}
