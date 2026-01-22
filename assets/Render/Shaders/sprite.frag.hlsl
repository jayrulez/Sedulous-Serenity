// Sprite Fragment Shader
// Textured sprite with color tinting
#pragma pack_matrix(row_major)

Texture2D SpriteTexture : register(t0);
SamplerState LinearSampler : register(s0);

struct FragmentInput
{
    float4 Position : SV_Position;
    float2 TexCoord : TEXCOORD0;
    float4 Color : TEXCOORD1;
};

float4 main(FragmentInput input) : SV_Target
{
    // Sample sprite texture
    float4 texColor = SpriteTexture.Sample(LinearSampler, input.TexCoord);

    // Multiply by instance color
    float4 finalColor = texColor * input.Color;

    // Alpha test - discard fully transparent pixels
    if (finalColor.a < 0.001)
        discard;

    // Premultiplied alpha output
    return float4(finalColor.rgb * finalColor.a, finalColor.a);
}
