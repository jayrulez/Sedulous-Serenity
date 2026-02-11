// Fullscreen Blit Fragment Shader
// Simple texture copy with tone mapping
// NOTE: Output goes to sRGB swapchain - GPU applies gamma automatically

cbuffer BlitParams : register(b0)
{
    float Exposure;
    float _Pad0;
    float _Pad1;
    float _Pad2;
};

Texture2D SourceTexture : register(t0);
SamplerState LinearSampler : register(s0);

struct FragmentInput
{
    float4 Position : SV_Position;
    float2 TexCoord : TEXCOORD0;
};

// ACES filmic tone mapping curve
float3 ACESFilm(float3 x)
{
    float a = 2.51;
    float b = 0.03;
    float c = 2.43;
    float d = 0.59;
    float e = 0.14;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

float4 main(FragmentInput input) : SV_Target
{
    // Sample source texture (HDR linear)
    float4 color = SourceTexture.Sample(LinearSampler, input.TexCoord);

    // Apply exposure before tone mapping
    color.rgb *= Exposure;

    // Simple Reinhard tone mapping (HDR to LDR)
    // Output remains in linear space - sRGB target applies gamma
    //color.rgb = color.rgb / (color.rgb + 1.0);

    // ACES alternative (more vibrant):
     color.rgb = ACESFilm(color.rgb);

    // Pass-through (clamp to LDR range)
    //color.rgb = saturate(color.rgb);

    return float4(color.rgb, 1.0);
}