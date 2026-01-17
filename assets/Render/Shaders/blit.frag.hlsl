// Fullscreen Blit Fragment Shader
// Simple texture copy with optional tone mapping

Texture2D SourceTexture : register(t0);
SamplerState LinearSampler : register(s0);

struct FragmentInput
{
    float4 Position : SV_Position;
    float2 TexCoord : TEXCOORD0;
};

float4 main(FragmentInput input) : SV_Target
{
    // Sample source texture
    float4 color = SourceTexture.Sample(LinearSampler, input.TexCoord);

    // Simple Reinhard tone mapping (HDR to LDR)
    color.rgb = color.rgb / (color.rgb + 1.0);

    // Gamma correction (linear to sRGB)
    color.rgb = pow(color.rgb, 1.0 / 2.2);

    return float4(color.rgb, 1.0);
}
