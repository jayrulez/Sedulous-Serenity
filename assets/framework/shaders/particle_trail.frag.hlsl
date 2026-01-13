// Particle Trail Fragment Shader
// Renders trail ribbons with optional texture and soft edges

struct PSInput
{
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
    float4 color : COLOR;
};

// Trail uniforms (binding 1)
cbuffer TrailUniforms : register(b1)
{
    float4 trailParams; // x = useTexture, y = softEdge, z = unused, w = unused
};

// Trail texture and sampler (bindings t0, s0)
Texture2D trailTexture : register(t0);
SamplerState trailSampler : register(s0);

float4 main(PSInput input) : SV_Target
{
    float4 finalColor;

    bool useTexture = trailParams.x > 0.5;
    float softEdge = trailParams.y;

    if (useTexture)
    {
        // Sample trail texture
        float4 texColor = trailTexture.Sample(trailSampler, input.uv);
        finalColor = texColor * input.color;
    }
    else
    {
        // Procedural trail with soft edges
        finalColor = input.color;

        // Soft edge falloff (V coordinate is 0-1 across the trail width)
        float edgeDist = abs(input.uv.y - 0.5) * 2.0; // 0 at center, 1 at edges

        if (softEdge > 0)
        {
            float edgeAlpha = 1.0 - smoothstep(1.0 - softEdge, 1.0, edgeDist);
            finalColor.a *= edgeAlpha;
        }
    }

    return finalColor;
}
