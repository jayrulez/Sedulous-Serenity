// Particle Fragment Shader
// Supports textured particles with atlas, procedural shapes, and soft particles

struct PSInput
{
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
    float4 color : COLOR;
    float4 screenPos : TEXCOORD1;  // Clip-space position for soft particles
};

// Particle uniform buffer (binding 1)
cbuffer ParticleUniforms : register(b1)
{
    // Render mode: 0=Billboard, 1=StretchedBillboard, 2=HorizontalBillboard, 3=VerticalBillboard
    uint renderMode;
    float stretchFactor;
    float minStretchLength;
    uint useTexture;         // 1 = sample texture, 0 = procedural

    // Soft particle parameters
    uint softParticlesEnabled;  // 1 = enable soft particles
    float softParticleDistance; // Distance over which to fade (world units)
    float nearPlane;            // Camera near plane
    float farPlane;             // Camera far plane
};

// Particle texture and sampler (bindings t0, s0)
Texture2D particleTexture : register(t0);
SamplerState particleSampler : register(s0);

// Depth texture for soft particles (binding t1)
Texture2D depthTexture : register(t1);
SamplerState depthSampler : register(s1);

// Linearize depth from NDC (0-1) to view space distance
float LinearizeDepth(float depth)
{
    // Standard perspective projection depth linearization
    // depth = (far * near) / (far - depth * (far - near))
    return (nearPlane * farPlane) / (farPlane - depth * (farPlane - nearPlane));
}

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

    // Apply soft particle depth fade
    if (softParticlesEnabled == 1 && softParticleDistance > 0.0)
    {
        // Convert clip-space to screen UV (0-1 range)
        float2 screenUV = input.screenPos.xy / input.screenPos.w;
        screenUV = screenUV * 0.5 + 0.5;  // NDC (-1 to 1) to UV (0 to 1)
        screenUV.y = 1.0 - screenUV.y;    // Flip Y for Vulkan

        // Sample scene depth
        float sceneDepth = depthTexture.Sample(depthSampler, screenUV).r;

        // Get particle depth (from SV_Position.z, already in 0-1 range)
        float particleDepth = input.position.z;

        // Linearize both depths for proper distance comparison
        float linearSceneDepth = LinearizeDepth(sceneDepth);
        float linearParticleDepth = LinearizeDepth(particleDepth);

        // Calculate depth difference (positive = particle is in front of scene)
        float depthDiff = linearSceneDepth - linearParticleDepth;

        // Fade based on distance to surface
        float softFade = saturate(depthDiff / softParticleDistance);

        finalColor.a *= softFade;
    }

    // Early out for fully transparent pixels
    if (finalColor.a < 0.001)
        discard;

    return finalColor;
}
