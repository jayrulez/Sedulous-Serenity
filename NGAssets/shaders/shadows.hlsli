// Shadow sampling shader include for Sedulous.RendererNG
// Contains CSM and shadow atlas sampling functions

#ifndef SHADOWS_HLSLI
#define SHADOWS_HLSLI

// ============================================================================
// Constants
// ============================================================================

static const uint MAX_CASCADES = 4;
static const float SHADOW_BIAS_DEFAULT = 0.002;
static const float SHADOW_NORMAL_BIAS_DEFAULT = 0.02;

// ============================================================================
// Cascade Shadow Data (must match Beef structs)
// ============================================================================

struct CascadeData
{
    float4x4 ViewProjection;
    float4 SplitDepth;   // x=near, y=far, z=1/width, w=1/height
    float4 Offset;       // xy=offset in atlas, zw=scale
};

struct CascadeShadowParams
{
    CascadeData Cascades[MAX_CASCADES];
    float4 ShadowParams;   // x=bias, y=normalBias, z=softness, w=cascadeCount
    float4 LightDirection; // xyz=direction, w=unused
};

// Local shadow data
struct LocalShadowData
{
    float4x4 ViewProjection;
    float4 UVTransform; // xy=offset, zw=scale
    float4 ShadowParams; // x=near, y=far, z=bias, w=unused
};

// ============================================================================
// Uniform Buffers
// ============================================================================

cbuffer CascadeShadowBuffer : register(b4)
{
    CascadeShadowParams g_CascadeShadows;
}

// ============================================================================
// Resources
// ============================================================================

Texture2DArray<float> g_CascadeShadowMaps : register(t8);
Texture2D<float> g_ShadowAtlas : register(t9);
SamplerComparisonState g_ShadowSampler : register(s1);

StructuredBuffer<LocalShadowData> g_LocalShadows : register(t10);

// ============================================================================
// Shadow Sampling Functions
// ============================================================================

// Basic shadow comparison
float SampleShadow(Texture2D<float> shadowMap, SamplerComparisonState shadowSampler,
                   float3 shadowCoord)
{
    return shadowMap.SampleCmpLevelZero(shadowSampler, shadowCoord.xy, shadowCoord.z);
}

// PCF 2x2 (hardware filtering with comparison sampler)
float SampleShadowPCF2x2(Texture2D<float> shadowMap, SamplerComparisonState shadowSampler,
                         float3 shadowCoord)
{
    return shadowMap.SampleCmpLevelZero(shadowSampler, shadowCoord.xy, shadowCoord.z);
}

// PCF 3x3 (9 samples)
float SampleShadowPCF3x3(Texture2D<float> shadowMap, SamplerComparisonState shadowSampler,
                         float3 shadowCoord, float2 texelSize)
{
    float shadow = 0.0;
    float2 offset = texelSize * 0.5;

    for (int y = -1; y <= 1; y++)
    {
        for (int x = -1; x <= 1; x++)
        {
            float2 uv = shadowCoord.xy + float2(x, y) * texelSize;
            shadow += shadowMap.SampleCmpLevelZero(shadowSampler, uv, shadowCoord.z);
        }
    }

    return shadow / 9.0;
}

// PCF 5x5 (25 samples) - higher quality
float SampleShadowPCF5x5(Texture2D<float> shadowMap, SamplerComparisonState shadowSampler,
                         float3 shadowCoord, float2 texelSize)
{
    float shadow = 0.0;

    for (int y = -2; y <= 2; y++)
    {
        for (int x = -2; x <= 2; x++)
        {
            float2 uv = shadowCoord.xy + float2(x, y) * texelSize;
            shadow += shadowMap.SampleCmpLevelZero(shadowSampler, uv, shadowCoord.z);
        }
    }

    return shadow / 25.0;
}

// Poisson disk sampling for softer shadows
static const float2 POISSON_DISK[16] =
{
    float2(-0.94201624, -0.39906216),
    float2( 0.94558609, -0.76890725),
    float2(-0.09418410, -0.92938870),
    float2( 0.34495938,  0.29387760),
    float2(-0.91588581,  0.45771432),
    float2(-0.81544232, -0.87912464),
    float2(-0.38277543,  0.27676845),
    float2( 0.97484398,  0.75648379),
    float2( 0.44323325, -0.97511554),
    float2( 0.53742981, -0.47373420),
    float2(-0.26496911, -0.41893023),
    float2( 0.79197514,  0.19090188),
    float2(-0.24188840,  0.99706507),
    float2(-0.81409955,  0.91437590),
    float2( 0.19984126,  0.78641367),
    float2( 0.14383161, -0.14100790)
};

float SampleShadowPoisson(Texture2D<float> shadowMap, SamplerComparisonState shadowSampler,
                          float3 shadowCoord, float2 texelSize, float radius)
{
    float shadow = 0.0;

    for (int i = 0; i < 16; i++)
    {
        float2 uv = shadowCoord.xy + POISSON_DISK[i] * texelSize * radius;
        shadow += shadowMap.SampleCmpLevelZero(shadowSampler, uv, shadowCoord.z);
    }

    return shadow / 16.0;
}

// ============================================================================
// Cascaded Shadow Maps
// ============================================================================

// Get cascade index based on view depth
uint GetCascadeIndex(float viewDepth)
{
    uint cascadeCount = (uint)g_CascadeShadows.ShadowParams.w;

    for (uint i = 0; i < cascadeCount; i++)
    {
        if (viewDepth < g_CascadeShadows.Cascades[i].SplitDepth.y)
            return i;
    }

    return cascadeCount - 1;
}

// Transform world position to shadow map coordinates
float3 WorldToShadowCoord(float3 worldPos, uint cascadeIndex)
{
    float4x4 viewProj = g_CascadeShadows.Cascades[cascadeIndex].ViewProjection;
    float4 shadowPos = mul(float4(worldPos, 1.0), viewProj);

    // Perspective divide and transform to [0,1] UV space
    float3 shadowCoord;
    shadowCoord.xy = shadowPos.xy / shadowPos.w * 0.5 + 0.5;
    shadowCoord.y = 1.0 - shadowCoord.y; // Flip Y for texture coordinates
    shadowCoord.z = shadowPos.z / shadowPos.w;

    return shadowCoord;
}

// Apply normal-based bias to reduce shadow acne
float3 ApplyNormalBias(float3 worldPos, float3 normal, float3 lightDir, float normalBias)
{
    float NdotL = saturate(dot(normal, -lightDir));
    float bias = normalBias * (1.0 - NdotL);
    return worldPos + normal * bias;
}

// Sample cascaded shadow map
float SampleCascadeShadow(float3 worldPos, float3 normal, float viewDepth)
{
    uint cascadeIndex = GetCascadeIndex(viewDepth);

    float bias = g_CascadeShadows.ShadowParams.x;
    float normalBias = g_CascadeShadows.ShadowParams.y;
    float softness = g_CascadeShadows.ShadowParams.z;
    float3 lightDir = g_CascadeShadows.LightDirection.xyz;

    // Apply normal bias
    float3 biasedPos = ApplyNormalBias(worldPos, normal, lightDir, normalBias);

    // Transform to shadow coordinates
    float3 shadowCoord = WorldToShadowCoord(biasedPos, cascadeIndex);

    // Apply depth bias
    shadowCoord.z -= bias;

    // Check bounds
    if (any(shadowCoord.xy < 0.0) || any(shadowCoord.xy > 1.0))
        return 1.0; // Outside shadow map

    // Sample shadow
    float2 texelSize = g_CascadeShadows.Cascades[cascadeIndex].SplitDepth.zw;

    #ifdef SHADOW_PCF_3X3
        return SampleShadowPCF3x3(g_ShadowAtlas, g_ShadowSampler, shadowCoord, texelSize);
    #elif defined(SHADOW_PCF_5X5)
        return SampleShadowPCF5x5(g_ShadowAtlas, g_ShadowSampler, shadowCoord, texelSize);
    #elif defined(SHADOW_POISSON)
        return SampleShadowPoisson(g_ShadowAtlas, g_ShadowSampler, shadowCoord, texelSize, softness);
    #else
        // Hardware 2x2 PCF
        return g_CascadeShadowMaps.SampleCmpLevelZero(g_ShadowSampler,
            float3(shadowCoord.xy, (float)cascadeIndex), shadowCoord.z);
    #endif
}

// Sample cascade shadow with cascade blending
float SampleCascadeShadowBlended(float3 worldPos, float3 normal, float viewDepth)
{
    uint cascadeIndex = GetCascadeIndex(viewDepth);
    uint cascadeCount = (uint)g_CascadeShadows.ShadowParams.w;

    float shadow = SampleCascadeShadow(worldPos, normal, viewDepth);

    // Blend between cascades at boundaries
    if (cascadeIndex < cascadeCount - 1)
    {
        float splitNear = g_CascadeShadows.Cascades[cascadeIndex].SplitDepth.x;
        float splitFar = g_CascadeShadows.Cascades[cascadeIndex].SplitDepth.y;
        float blendRange = (splitFar - splitNear) * 0.1; // 10% blend zone

        if (viewDepth > splitFar - blendRange)
        {
            float blendFactor = (viewDepth - (splitFar - blendRange)) / blendRange;

            // Sample next cascade
            float3 biasedPos = ApplyNormalBias(worldPos, normal,
                g_CascadeShadows.LightDirection.xyz,
                g_CascadeShadows.ShadowParams.y);
            float3 nextShadowCoord = WorldToShadowCoord(biasedPos, cascadeIndex + 1);
            nextShadowCoord.z -= g_CascadeShadows.ShadowParams.x;

            float nextShadow = g_CascadeShadowMaps.SampleCmpLevelZero(g_ShadowSampler,
                float3(nextShadowCoord.xy, (float)(cascadeIndex + 1)), nextShadowCoord.z);

            shadow = lerp(shadow, nextShadow, blendFactor);
        }
    }

    return shadow;
}

// ============================================================================
// Shadow Atlas (Local Lights)
// ============================================================================

// Sample shadow for a local light (point/spot)
float SampleLocalShadow(uint shadowIndex, float3 worldPos, float bias)
{
    LocalShadowData shadowData = g_LocalShadows[shadowIndex];

    // Transform to shadow space
    float4 shadowPos = mul(float4(worldPos, 1.0), shadowData.ViewProjection);
    float3 shadowCoord;
    shadowCoord.xy = shadowPos.xy / shadowPos.w * 0.5 + 0.5;
    shadowCoord.y = 1.0 - shadowCoord.y;
    shadowCoord.z = shadowPos.z / shadowPos.w - bias;

    // Transform UV to atlas region
    shadowCoord.xy = shadowCoord.xy * shadowData.UVTransform.zw + shadowData.UVTransform.xy;

    // Check bounds
    if (any(shadowCoord.xy < shadowData.UVTransform.xy) ||
        any(shadowCoord.xy > shadowData.UVTransform.xy + shadowData.UVTransform.zw))
        return 1.0;

    return g_ShadowAtlas.SampleCmpLevelZero(g_ShadowSampler, shadowCoord.xy, shadowCoord.z);
}

// ============================================================================
// Debug Visualization
// ============================================================================

// Get cascade debug color
float3 GetCascadeDebugColor(uint cascadeIndex)
{
    float3 colors[4] =
    {
        float3(1, 0, 0), // Red
        float3(0, 1, 0), // Green
        float3(0, 0, 1), // Blue
        float3(1, 1, 0)  // Yellow
    };
    return colors[cascadeIndex % 4];
}

// Apply cascade debug visualization
float3 ApplyCascadeDebug(float3 color, float viewDepth, float intensity)
{
    uint cascadeIndex = GetCascadeIndex(viewDepth);
    return lerp(color, color * GetCascadeDebugColor(cascadeIndex), intensity);
}

#endif // SHADOWS_HLSLI
