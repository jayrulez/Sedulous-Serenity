// Unlit Fragment Shader - Simple textured rendering

struct PSInput
{
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
};

// Material uniform buffer (binding 1)
cbuffer MaterialUniforms : register(b1)
{
    float4 color;
};

// Textures
Texture2D mainTexture : register(t0);

// Samplers
SamplerState mainSampler : register(s0);

float4 main(PSInput input) : SV_Target
{
    float4 texColor = mainTexture.Sample(mainSampler, input.uv);
    return texColor * color;
}
