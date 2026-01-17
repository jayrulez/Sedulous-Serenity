// Particle Render Fragment Shader
// Textured particles with soft blending
#pragma pack_matrix(row_major)

Texture2D ParticleTexture : register(t2);
SamplerState LinearSampler : register(s0);

#ifdef SOFT_PARTICLES
Texture2D DepthTexture : register(t3);

cbuffer SoftParticleParams : register(b2)
{
    float SoftDistance;
    float3 _SoftPadding;
};
#endif

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

#ifdef SOFT_PARTICLES
    // Soft particle depth fade
    float sceneDepth = DepthTexture.Load(int3(input.Position.xy, 0)).r;
    float particleDepth = input.Position.z;

    // Linear depth comparison
    float depthDiff = sceneDepth - particleDepth;
    float softFade = saturate(depthDiff / SoftDistance);
    finalColor.a *= softFade;
#endif

    // Premultiplied alpha output
    return float4(finalColor.rgb * finalColor.a, finalColor.a);
}
