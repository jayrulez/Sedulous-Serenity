// Fullscreen Blit Fragment Shader
// Copies scene color to swapchain with optional tone mapping.
// When Passthrough=1 (PostProcess tonemap active), just copies the already-tonemapped LDR result.
// When Passthrough=0 (no PostProcess tonemap), applies ACES filmic tonemapping as fallback.
// NOTE: Output goes to sRGB swapchain - GPU applies gamma automatically

cbuffer BlitParams : register(b0)
{
    float Exposure;
    int Passthrough;  // 1 = skip tonemapping (already done by PostProcess)
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

// ACES filmic tone mapping curve (fallback when no PostProcess tonemap)
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
    // Sample source texture
    float4 color = SourceTexture.Sample(LinearSampler, input.TexCoord);

    if (Passthrough == 0)
    {
        // No PostProcess tonemapping — apply built-in ACES as fallback
        color.rgb *= Exposure;
        color.rgb = ACESFilm(color.rgb);
    }
    // else: PostProcess tonemap already applied, just pass through

    return float4(color.rgb, 1.0);
}
