// Shadow sampling utilities
// Provides PCF filtering for cascaded and atlas shadows

#ifndef SHADOW_SAMPLING_HLSLI
#define SHADOW_SAMPLING_HLSLI

// Shadow map comparison sampler (configured with LessEqual)
SamplerComparisonState shadowSampler : register(s0, space1);

// Cascaded shadow maps (2D array texture)
Texture2DArray<float> cascadeShadowMaps : register(t0, space1);

// Shadow atlas for spot/point lights
Texture2D<float> shadowAtlas : register(t1, space1);

// Point light shadow cubemaps
TextureCubeArray<float> pointLightShadows : register(t2, space1);

// Shadow uniforms
cbuffer ShadowSamplingUniforms : register(b0, space1)
{
    // CSM view-projection matrices
    float4x4 cascadeViewProjection[4];

    // Cascade split depths (view space)
    float4 cascadeSplits;

    // Shadow parameters
    float shadowBias;
    float shadowNormalBias;
    float shadowSoftness;
    float shadowTexelSize;

    // Number of active cascades
    uint cascadeCount;
    float3 _padding;
};

// --------------------------------------------------
// PCF Filtering - 3x3 kernel
// --------------------------------------------------

float PCF3x3(Texture2D<float> shadowMap, SamplerComparisonState sampler,
             float3 shadowCoord, float texelSize)
{
    float shadow = 0.0;
    float2 offset = float2(texelSize, texelSize);

    // Sample 3x3 kernel
    [unroll]
    for (int y = -1; y <= 1; y++)
    {
        [unroll]
        for (int x = -1; x <= 1; x++)
        {
            float2 samplePos = shadowCoord.xy + float2(x, y) * offset;
            shadow += shadowMap.SampleCmpLevelZero(sampler, samplePos, shadowCoord.z);
        }
    }

    return shadow / 9.0;
}

float PCF3x3Array(Texture2DArray<float> shadowMap, SamplerComparisonState sampler,
                  float3 shadowCoord, uint arrayIndex, float texelSize)
{
    float shadow = 0.0;
    float2 offset = float2(texelSize, texelSize);

    // Sample 3x3 kernel
    [unroll]
    for (int y = -1; y <= 1; y++)
    {
        [unroll]
        for (int x = -1; x <= 1; x++)
        {
            float3 samplePos = float3(shadowCoord.xy + float2(x, y) * offset, arrayIndex);
            shadow += shadowMap.SampleCmpLevelZero(sampler, samplePos, shadowCoord.z);
        }
    }

    return shadow / 9.0;
}

// --------------------------------------------------
// PCF Filtering - 5x5 kernel (higher quality)
// --------------------------------------------------

float PCF5x5(Texture2D<float> shadowMap, SamplerComparisonState sampler,
             float3 shadowCoord, float texelSize)
{
    float shadow = 0.0;
    float2 offset = float2(texelSize, texelSize);

    // Sample 5x5 kernel with distance-based weights
    [unroll]
    for (int y = -2; y <= 2; y++)
    {
        [unroll]
        for (int x = -2; x <= 2; x++)
        {
            float2 samplePos = shadowCoord.xy + float2(x, y) * offset;
            shadow += shadowMap.SampleCmpLevelZero(sampler, samplePos, shadowCoord.z);
        }
    }

    return shadow / 25.0;
}

// --------------------------------------------------
// Cascade selection for CSM
// --------------------------------------------------

uint SelectCascade(float viewDepth)
{
    uint cascade = 0;

    // Select cascade based on view-space depth
    if (viewDepth > cascadeSplits.x) cascade = 1;
    if (viewDepth > cascadeSplits.y) cascade = 2;
    if (viewDepth > cascadeSplits.z) cascade = 3;

    return min(cascade, cascadeCount - 1);
}

// --------------------------------------------------
// Sample cascaded shadow map
// --------------------------------------------------

float SampleCascadedShadow(float3 worldPos, float3 worldNormal, float viewDepth)
{
    // Select appropriate cascade
    uint cascade = SelectCascade(viewDepth);

    // Transform to shadow space
    float4 shadowPos = mul(float4(worldPos, 1.0), cascadeViewProjection[cascade]);
    shadowPos.xyz /= shadowPos.w;

    // Convert from NDC to texture coordinates
    float3 shadowCoord;
    shadowCoord.x = shadowPos.x * 0.5 + 0.5;
    shadowCoord.y = -shadowPos.y * 0.5 + 0.5; // Flip Y for texture space
    shadowCoord.z = shadowPos.z;

    // Apply bias
    float bias = shadowBias + shadowNormalBias * (1.0 - saturate(dot(worldNormal, normalize(-shadowPos.xyz))));
    shadowCoord.z -= bias;

    // Check bounds
    if (shadowCoord.x < 0.0 || shadowCoord.x > 1.0 ||
        shadowCoord.y < 0.0 || shadowCoord.y > 1.0 ||
        shadowCoord.z < 0.0 || shadowCoord.z > 1.0)
    {
        return 1.0; // Outside shadow map - fully lit
    }

    // Sample with PCF
    float shadow = PCF3x3Array(cascadeShadowMaps, shadowSampler, shadowCoord, cascade, shadowTexelSize);

    return shadow;
}

// --------------------------------------------------
// Cascade blending for smooth transitions
// --------------------------------------------------

float SampleCascadedShadowBlended(float3 worldPos, float3 worldNormal, float viewDepth)
{
    // Select cascades for blending
    uint cascade = SelectCascade(viewDepth);
    uint nextCascade = min(cascade + 1, cascadeCount - 1);

    // Calculate blend factor based on distance to cascade boundary
    float cascadeStart = (cascade == 0) ? 0.0 :
                         (cascade == 1) ? cascadeSplits.x :
                         (cascade == 2) ? cascadeSplits.y : cascadeSplits.z;

    float cascadeEnd = (cascade == 0) ? cascadeSplits.x :
                       (cascade == 1) ? cascadeSplits.y :
                       (cascade == 2) ? cascadeSplits.z : cascadeSplits.w;

    float blendRegion = (cascadeEnd - cascadeStart) * 0.1; // Blend in 10% of cascade range
    float blendStart = cascadeEnd - blendRegion;
    float blendFactor = saturate((viewDepth - blendStart) / blendRegion);

    // Sample current cascade
    float4 shadowPos = mul(float4(worldPos, 1.0), cascadeViewProjection[cascade]);
    shadowPos.xyz /= shadowPos.w;

    float3 shadowCoord;
    shadowCoord.x = shadowPos.x * 0.5 + 0.5;
    shadowCoord.y = -shadowPos.y * 0.5 + 0.5;
    shadowCoord.z = shadowPos.z - shadowBias;

    float shadow1 = 1.0;
    if (shadowCoord.x >= 0.0 && shadowCoord.x <= 1.0 &&
        shadowCoord.y >= 0.0 && shadowCoord.y <= 1.0 &&
        shadowCoord.z >= 0.0 && shadowCoord.z <= 1.0)
    {
        shadow1 = PCF3x3Array(cascadeShadowMaps, shadowSampler, shadowCoord, cascade, shadowTexelSize);
    }

    // Sample next cascade for blending
    float shadow2 = shadow1;
    if (blendFactor > 0.0 && nextCascade != cascade)
    {
        shadowPos = mul(float4(worldPos, 1.0), cascadeViewProjection[nextCascade]);
        shadowPos.xyz /= shadowPos.w;

        shadowCoord.x = shadowPos.x * 0.5 + 0.5;
        shadowCoord.y = -shadowPos.y * 0.5 + 0.5;
        shadowCoord.z = shadowPos.z - shadowBias;

        if (shadowCoord.x >= 0.0 && shadowCoord.x <= 1.0 &&
            shadowCoord.y >= 0.0 && shadowCoord.y <= 1.0 &&
            shadowCoord.z >= 0.0 && shadowCoord.z <= 1.0)
        {
            shadow2 = PCF3x3Array(cascadeShadowMaps, shadowSampler, shadowCoord, nextCascade, shadowTexelSize);
        }
    }

    // Blend between cascades
    return lerp(shadow1, shadow2, blendFactor);
}

// --------------------------------------------------
// Sample spot light shadow from atlas
// --------------------------------------------------

float SampleSpotLightShadow(float3 worldPos, float4x4 lightViewProj, float4 uvOffsetScale)
{
    // Transform to light space
    float4 shadowPos = mul(float4(worldPos, 1.0), lightViewProj);
    shadowPos.xyz /= shadowPos.w;

    // Convert to shadow map UV with atlas offset/scale
    float3 shadowCoord;
    shadowCoord.x = (shadowPos.x * 0.5 + 0.5) * uvOffsetScale.z + uvOffsetScale.x;
    shadowCoord.y = (-shadowPos.y * 0.5 + 0.5) * uvOffsetScale.w + uvOffsetScale.y;
    shadowCoord.z = shadowPos.z - shadowBias;

    // Bounds check
    if (shadowCoord.x < uvOffsetScale.x || shadowCoord.x > uvOffsetScale.x + uvOffsetScale.z ||
        shadowCoord.y < uvOffsetScale.y || shadowCoord.y > uvOffsetScale.y + uvOffsetScale.w ||
        shadowCoord.z < 0.0 || shadowCoord.z > 1.0)
    {
        return 1.0;
    }

    // PCF sample
    return PCF3x3(shadowAtlas, shadowSampler, shadowCoord, shadowTexelSize * uvOffsetScale.z);
}

// --------------------------------------------------
// Sample point light shadow from cubemap
// --------------------------------------------------

float SamplePointLightShadow(float3 worldPos, float3 lightPos, float lightRange, uint lightIndex)
{
    // Direction from light to fragment
    float3 lightToFrag = worldPos - lightPos;
    float distance = length(lightToFrag);

    // Normalize depth to 0-1 range based on light range
    float normalizedDepth = distance / lightRange - shadowBias;

    // Sample cubemap array with PCF
    // Using hardware comparison sampler
    float4 sampleDir = float4(lightToFrag, lightIndex);
    float shadow = pointLightShadows.SampleCmpLevelZero(shadowSampler, sampleDir, normalizedDepth);

    return shadow;
}

#endif // SHADOW_SAMPLING_HLSLI
