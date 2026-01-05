// Skybox Fragment Shader
// Samples cubemap based on view direction

struct PSInput
{
    float4 position : SV_Position;
    float3 texCoord : TEXCOORD0;
};

TextureCube skyboxTexture : register(t0);
SamplerState skyboxSampler : register(s0);

float4 main(PSInput input) : SV_Target
{
    // Sample the cubemap texture using view direction
    float3 dir = normalize(input.texCoord);
    float3 color = skyboxTexture.Sample(skyboxSampler, dir).rgb;

    return float4(color, 1.0);
}
