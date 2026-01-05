// Particle Fragment Shader for Sample
// Simple colored particles with soft circular shape

struct PSInput
{
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
    float4 color : COLOR;
};

float4 main(PSInput input) : SV_Target
{
    // Create a circular particle with solid center and soft edge
    float2 center = input.uv - 0.5;
    float dist = length(center) * 2.0;

    // Sharper falloff - solid center with soft edge
    float alpha = saturate(1.0 - dist);
    alpha = smoothstep(0.0, 0.5, alpha); // Sharper transition

    float4 finalColor = input.color;
    finalColor.a *= alpha;

    // Discard nearly transparent pixels
    if (finalColor.a < 0.02)
        discard;

    return finalColor;
}
