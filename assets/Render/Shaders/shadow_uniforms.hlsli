// Shadow uniforms, resources, and sampling helper
// Layout MUST match ShadowUniforms struct in CascadedShadowMaps.bf (336 bytes)
// Requires: scene_uniforms.hlsli (for ViewMatrix)

#ifdef RECEIVE_SHADOWS

Texture2DArray ShadowMap : register(t7);
SamplerComparisonState ShadowSampler : register(s1);

cbuffer ShadowUniforms : register(b5)
{
    float4x4 ShadowViewProjection[4];
    float4 CascadeSplits;
    uint CascadeCount;
    float ShadowBias;
    float ShadowNormalBias;
    uint _ShadowPad0;
    float2 ShadowMapSize;
    float2 _ShadowPad1;
    float4 ShadowLightDirection;   // xyz = normalized light direction
    float4 CascadeTexelSizes;     // world-space texel size per cascade
};

// Standard cascaded shadow map sampling with PCF and normal offset bias.
// Returns 0.0 (fully shadowed) to 1.0 (fully lit).
float SampleShadowMap(float3 worldPos, float3 N)
{
    float viewZ = abs(mul(float4(worldPos, 1.0), ViewMatrix).z);

    uint cascadeIndex = CascadeCount - 1;
    for (uint i = 0; i < CascadeCount; i++)
    {
        if (viewZ < CascadeSplits[i])
        {
            cascadeIndex = i;
            break;
        }
    }

    // Normal offset bias
    float3 lightDir = ShadowLightDirection.xyz;
    float NdotL = saturate(dot(N, -lightDir));
    float texelSize = CascadeTexelSizes[cascadeIndex];
    float3 offsetPos = worldPos + N * (ShadowNormalBias * texelSize * (1.0 - NdotL));

    float4 shadowCoord = mul(float4(offsetPos, 1.0), ShadowViewProjection[cascadeIndex]);
    shadowCoord.xyz /= shadowCoord.w;
    shadowCoord.xy = shadowCoord.xy * 0.5 + 0.5;
    shadowCoord.z = saturate(shadowCoord.z);

    shadowCoord.y = 1.0 - shadowCoord.y;

    if (any(shadowCoord.xy < 0.0) || any(shadowCoord.xy > 1.0))
        return 1.0;

    shadowCoord.z -= ShadowBias;

    // 5x5 PCF
    float shadow = 0.0;
    float2 texelSizeUV = 1.0 / ShadowMapSize;
    for (int x = -2; x <= 2; x++)
    {
        for (int y = -2; y <= 2; y++)
        {
            float2 offset = float2(x, y) * texelSizeUV;
            float3 sampleCoord = float3(shadowCoord.xy + offset, (float)cascadeIndex);
            shadow += ShadowMap.SampleCmpLevelZero(ShadowSampler, sampleCoord, shadowCoord.z);
        }
    }
    return shadow / 25.0;
}

#endif // RECEIVE_SHADOWS
