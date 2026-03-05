// Water Scene Color Copy - Fragment Shader
// Passthrough blit of SceneColor to a copy texture for refraction sampling.

Texture2D<float4> SceneColorInput : register(t0);
SamplerState CopySampler : register(s0);

struct FragmentInput
{
    float4 Position : SV_Position;
    float2 TexCoord : TEXCOORD0;
};

float4 main(FragmentInput input) : SV_Target0
{
    return SceneColorInput.Sample(CopySampler, input.TexCoord);
}
