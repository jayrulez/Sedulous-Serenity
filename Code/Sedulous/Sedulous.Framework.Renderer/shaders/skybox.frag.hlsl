// Skybox Fragment Shader

struct PSInput
{
    float4 position : SV_Position;
    float3 texCoord : TEXCOORD0;
};

// Skybox cubemap
TextureCube skyboxTexture : register(t0);
SamplerState skyboxSampler : register(s0);

float4 main(PSInput input) : SV_Target
{
    float3 color = skyboxTexture.Sample(skyboxSampler, input.texCoord).rgb;

    // Optional: simple exposure adjustment
    // color = color / (color + 1.0);

    return float4(color, 1.0);
}
