// Particle Render Fragment Shader
// Textured particles with soft depth fade
#pragma pack_matrix(row_major)

Texture2D ParticleTexture : register(t2);
Texture2D DepthTexture : register(t3);
SamplerState LinearSampler : register(s0);

cbuffer SoftParticleParams : register(b2)
{
    float SoftDistance;
    float NearPlane;
    float FarPlane;
    float _SoftPadding;
};

struct FragmentInput
{
    float4 Position : SV_Position;
    float2 TexCoord : TEXCOORD0;
    float4 Color : TEXCOORD1;
};

float LinearizeDepth(float depth, float near, float far)
{
    return near * far / (far - depth * (far - near));
}

float4 main(FragmentInput input) : SV_Target
{
    // Sample particle texture
    float4 texColor = ParticleTexture.Sample(LinearSampler, input.TexCoord);

    // Multiply by particle color
    float4 finalColor = texColor * input.Color;

    // Soft particle depth fade (when SoftDistance > 0)
    if (SoftDistance > 0.0)
    {
        float sceneDepth = DepthTexture.Load(int3(input.Position.xy, 0)).r;
        float linearScene = LinearizeDepth(sceneDepth, NearPlane, FarPlane);
        float linearFrag = LinearizeDepth(input.Position.z, NearPlane, FarPlane);
        float softFade = saturate((linearScene - linearFrag) / SoftDistance);
        finalColor.a *= softFade;
    }

    // Discard fully transparent pixels
    if (finalColor.a < 0.001)
        discard;

    // Premultiplied alpha output
    return float4(finalColor.rgb * finalColor.a, finalColor.a);
}
