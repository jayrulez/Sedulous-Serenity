// Particle Fragment Shader
// Supports textured particles with atlas and procedural shapes

struct PSInput
{
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
    float4 color : COLOR;
};

// Particle uniform buffer (binding 1)
cbuffer ParticleUniforms : register(b1)
{
    // Render mode: 0=Billboard, 1=StretchedBillboard, 2=HorizontalBillboard, 3=VerticalBillboard
    uint renderMode;
    float stretchFactor;
    float minStretchLength;
    uint useTexture;         // 1 = sample texture, 0 = procedural
};

// Particle texture and sampler (bindings t0, s0)
Texture2D particleTexture : register(t0);
SamplerState particleSampler : register(s0);

float4 main(PSInput input) : SV_Target
{
    float4 finalColor;

    if (useTexture == 1)
    {
        // Sample particle texture
        float4 texColor = particleTexture.Sample(particleSampler, input.uv);
        finalColor = texColor * input.color;
    }
    else
    {
        // Procedural circular particle with soft edge
        float2 center = input.uv - 0.5;
        float dist = length(center) * 2.0;

        // Sharper falloff - solid center with soft edge
        float alpha = saturate(1.0 - dist);
        alpha = smoothstep(0.0, 0.5, alpha);

        finalColor = input.color;
        finalColor.a *= alpha;
    }

    // Let alpha blending handle transparency (no discard)
    return finalColor;
}
