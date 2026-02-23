// Textured quad fragment shader
// Samples texture using provided UV coordinates

struct PSInput
{
    float4 position : SV_Position;
    float2 texCoord : TEXCOORD0;
};

// Texture and sampler bindings
// Bindings determined by DXC -fvk-t-shift and -fvk-s-shift options
Texture2D diffuseTexture : register(t0);
SamplerState diffuseSampler : register(s0);

float4 main(PSInput input) : SV_Target
{
    return diffuseTexture.Sample(diffuseSampler, input.texCoord);
}
