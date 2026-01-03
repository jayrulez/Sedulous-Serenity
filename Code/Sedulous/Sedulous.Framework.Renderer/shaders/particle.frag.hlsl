// Particle Fragment Shader

struct PSInput
{
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
    float4 color : COLOR;
};

// Particle texture
Texture2D particleTexture : register(t0);
SamplerState particleSampler : register(s0);

float4 main(PSInput input) : SV_Target
{
    float4 texColor = particleTexture.Sample(particleSampler, input.uv);
    float4 finalColor = texColor * input.color;

    // Premultiplied alpha for additive/soft blending
    // finalColor.rgb *= finalColor.a;

    return finalColor;
}
