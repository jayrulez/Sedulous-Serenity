// Mipmap test fragment shader

Texture2D tex : register(t0);
SamplerState samp : register(s0);

struct PSInput
{
    float4 position : SV_Position;
    float2 texCoord : TEXCOORD0;
};

float4 main(PSInput input) : SV_Target
{
    return tex.Sample(samp, input.texCoord);
}
