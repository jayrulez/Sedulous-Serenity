// Debug text fragment shader
// Samples font atlas and applies vertex color

Texture2D fontTexture : register(t0);
SamplerState fontSampler : register(s0);

struct PSInput
{
    float4 position : SV_Position;
    float2 texCoord : TEXCOORD0;
    float4 color : COLOR;
};

float4 main(PSInput input) : SV_Target
{
    // Sample font atlas (grayscale alpha)
    float alpha = fontTexture.Sample(fontSampler, input.texCoord).r;

    // Apply vertex color with font alpha
    return float4(input.color.rgb, input.color.a * alpha);
}
