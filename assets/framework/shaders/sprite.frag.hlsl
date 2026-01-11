// Sprite/Billboard Fragment Shader
// Textured sprite with color tint

struct PSInput
{
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
    float4 color : COLOR;
};

// Texture and sampler (binding 0 in texture/sampler space)
Texture2D spriteTexture : register(t0);
SamplerState spriteSampler : register(s0);

float4 main(PSInput input) : SV_Target
{
    // Sample texture and multiply by tint color
    float4 texColor = spriteTexture.Sample(spriteSampler, input.uv);
    return texColor * input.color;
}
