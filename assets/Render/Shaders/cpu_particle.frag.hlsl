// CPU Particle Render Fragment Shader
// Textured particles with optional soft particle depth fade
#pragma pack_matrix(row_major)

Texture2D ParticleTexture : register(t0);
SamplerState LinearSampler : register(s0);

struct FragmentInput
{
    float4 Position : SV_Position;
    float2 TexCoord : TEXCOORD0;
    float4 Color : TEXCOORD1;
};

float4 main(FragmentInput input) : SV_Target
{
    // Sample particle texture
    float4 texColor = ParticleTexture.Sample(LinearSampler, input.TexCoord);

    // Multiply by particle color
    float4 finalColor = texColor * input.Color;

    // Discard fully transparent pixels
    if (finalColor.a < 0.001)
        discard;

    // Premultiplied alpha output
    return float4(finalColor.rgb * finalColor.a, finalColor.a);
}
