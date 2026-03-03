// SSAO Apply Fragment Shader
// Applies bilateral-blurred AO to the scene color.

cbuffer SSAOApplyParams : register(b0)
{
    float2 TexelSize;
    float2 _Pad;
};

Texture2D SceneColor : register(t0);
Texture2D AOTexture : register(t1);
Texture2D DepthTexture : register(t2);
SamplerState PointSampler : register(s0);

struct FragmentInput
{
    float4 Position : SV_Position;
    float2 TexCoord : TEXCOORD0;
};

float4 main(FragmentInput input) : SV_Target
{
    float2 uv = input.TexCoord;

    float3 sceneColor = SceneColor.Sample(PointSampler, uv).rgb;

    // Sample center AO and depth
    float centerAO = AOTexture.Sample(PointSampler, uv).r;
    float centerDepth = DepthTexture.Sample(PointSampler, uv).r;

    // Skip sky pixels
    if (centerDepth >= 1.0)
        return float4(sceneColor, 1.0);

    // Bilateral blur: 4 cardinal neighbors + center
    float totalAO = centerAO;
    float totalWeight = 1.0;

    // Depth-aware weighting scale
    float depthScale = 500.0;

    // Cardinal neighbor offsets
    static const float2 offsets[4] = {
        float2(-1, 0), float2(1, 0), float2(0, -1), float2(0, 1)
    };

    [unroll]
    for (int i = 0; i < 4; i++)
    {
        float2 neighborUV = uv + offsets[i] * TexelSize;
        float neighborAO = AOTexture.Sample(PointSampler, neighborUV).r;
        float neighborDepth = DepthTexture.Sample(PointSampler, neighborUV).r;

        // Bilateral weight: similar depth = high weight, different depth = low weight
        float weight = exp(-abs(centerDepth - neighborDepth) * depthScale);
        totalAO += neighborAO * weight;
        totalWeight += weight;
    }

    float blurredAO = totalAO / totalWeight;

    // Multiply scene color by AO
    return float4(sceneColor * blurredAO, 1.0);
}
