// Sprite/Billboard Fragment Shader

struct PSInput
{
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
    float4 color : COLOR;
};

// Sprite texture
Texture2D spriteTexture : register(t0);
SamplerState spriteSampler : register(s0);

float4 main(PSInput input) : SV_Target
{
    float4 texColor = spriteTexture.Sample(spriteSampler, input.uv);
    float4 finalColor = texColor * input.color;

    // Alpha test - discard nearly transparent pixels
    if (finalColor.a < 0.01)
        discard;

    return finalColor;
}
