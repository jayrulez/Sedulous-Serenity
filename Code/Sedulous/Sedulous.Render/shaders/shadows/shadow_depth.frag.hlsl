// Shadow depth fragment shader
// Only needed for alpha-tested geometry; depth-only passes can skip this

#ifdef ALPHA_TEST

Texture2D<float4> albedoTexture : register(t0);
SamplerState linearSampler : register(s0);

cbuffer MaterialUniforms : register(b2)
{
    float alphaThreshold;
    float3 _padding;
};

struct PSInput
{
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
};

void main(PSInput input)
{
    float alpha = albedoTexture.Sample(linearSampler, input.uv).a;

    // Discard if below alpha threshold
    if (alpha < alphaThreshold)
        discard;

    // No color output - depth only
}

#else

// No alpha test - just output depth (empty shader body)
void main()
{
}

#endif
