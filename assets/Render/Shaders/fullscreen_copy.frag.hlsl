// Fullscreen Copy Fragment Shader
// Minimal passthrough for copying textures (e.g., TAA history buffer update).

Texture2D SourceTexture : register(t0);
SamplerState PointSampler : register(s0);

struct FragmentInput
{
    float4 Position : SV_Position;
    float2 TexCoord : TEXCOORD0;
};

float4 main(FragmentInput input) : SV_Target
{
    return SourceTexture.Sample(PointSampler, input.TexCoord);
}
