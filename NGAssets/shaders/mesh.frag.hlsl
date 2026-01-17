// Unified mesh fragment shader for RendererNG
// Supports various material features via shader variants

#include "common.hlsli"

// ============================================================================
// Material Uniforms (Set 1 / space1 = per-material bind group)
// ============================================================================

cbuffer MaterialUniforms : register(b0, space1)
{
    float4 BaseColor;
    float Metallic;
    float Roughness;
    float AO;
    float AlphaCutoff;
    float4 EmissiveColor;
};

// ============================================================================
// Textures and Samplers (Set 1 / space1 = per-material bind group)
// ============================================================================

Texture2D AlbedoMap : register(t0, space1);
Texture2D NormalMap : register(t1, space1);
Texture2D MetallicRoughnessMap : register(t2, space1);
Texture2D EmissiveMap : register(t3, space1);
Texture2D AOMap : register(t4, space1);

SamplerState MaterialSampler : register(s0, space1);

// ============================================================================
// Lighting (Set 0 / space0 = scene bind group)
// ============================================================================

#define MAX_POINT_LIGHTS 4

struct DirectionalLight
{
    float3 Direction;
    float Intensity;
    float3 Color;
    float Padding;
};

struct PointLight
{
    float3 Position;
    float Range;
    float3 Color;
    float Intensity;
};

cbuffer LightingUniforms : register(b1, space0)
{
    DirectionalLight SunLight;
    float3 AmbientColor;
    float AmbientIntensity;
    PointLight PointLights[MAX_POINT_LIGHTS];
    int ActivePointLights;
    float3 _LightingPadding;
};

// ============================================================================
// Shadow Mapping (Set 0 / space0 = scene bind group)
// ============================================================================

#define CASCADE_COUNT 4

struct CascadeData
{
    float4x4 ViewProjection;
    float4 SplitDepth;     // x=near, y=far, z=1/width, w=1/height
    float4 Offset;         // xy=offset in atlas, zw=scale
};

cbuffer ShadowUniforms : register(b2, space0)
{
    CascadeData Cascades[CASCADE_COUNT];
    float4 ShadowParams;   // x=bias, y=normalBias, z=softness, w=cascadeCount
    float4 LightDirection; // xyz=direction, w=unused
};

Texture2DArray ShadowCascades : register(t0, space0);
SamplerComparisonState ShadowSampler : register(s0, space0);

// Shadow Debug Modes (set to 0 for normal rendering):
//   0 = Normal rendering (shadows applied)
//   1 = Show shadow UV coordinates as R=U, G=V (should be in [0,1] with smooth gradients)
//   2 = Show shadow clip-space depth as grayscale (0=near, 1=far)
//   3 = Show cascade index (Red=0, Green=1, Blue=2, Yellow=3)
//   4 = Show UV/depth validity (Green=valid, Magenta=UV out of bounds, Red=depth out of bounds)
//   5 = Show view-space depth for cascade selection
#define SHADOW_DEBUG_MODE 0

// Calculate shadow factor for cascaded shadow maps
float CalculateShadow(float3 worldPos, float3 normal)
{
    // Calculate view-space depth for cascade selection (matching old renderer approach)
    float4 viewPos = mul(float4(worldPos, 1.0), ViewMatrix);
    float depth = abs(viewPos.z);  // Use abs() like old renderer

    // Find which cascade to use
    int cascadeIndex = CASCADE_COUNT - 1;
    for (int i = 0; i < CASCADE_COUNT; i++)
    {
        if (depth < Cascades[i].SplitDepth.y)
        {
            cascadeIndex = i;
            break;
        }
    }

    // Transform to shadow space
    float4 shadowPos = mul(float4(worldPos, 1.0), Cascades[cascadeIndex].ViewProjection);
    shadowPos.xyz /= shadowPos.w;

    // Convert to [0, 1] UV coordinates (same as old renderer - no flip needed)
    float2 shadowUV = shadowPos.xy * 0.5 + 0.5;

    // Use saturate to clamp depth to [0,1] like the old renderer
    // Hardware depth bias is used instead of shader-based bias
    float compareDepth = saturate(shadowPos.z);

    // Sample shadow map with PCF
    float shadow = 0.0;
    float2 texelSize = float2(Cascades[cascadeIndex].SplitDepth.z, Cascades[cascadeIndex].SplitDepth.w);

    // 3x3 PCF
    for (int x = -1; x <= 1; x++)
    {
        for (int y = -1; y <= 1; y++)
        {
            float2 offset = float2(x, y) * texelSize;
            shadow += ShadowCascades.SampleCmpLevelZero(ShadowSampler,
                float3(shadowUV + offset, cascadeIndex), compareDepth);
        }
    }
    shadow /= 9.0;

    return shadow;
}

// Debug function to visualize shadow data
float3 DebugShadow(float3 worldPos, float3 normal)
{
    float4 viewPos = mul(float4(worldPos, 1.0), ViewMatrix);
    float depth = -viewPos.z;

    int cascadeIndex = CASCADE_COUNT - 1;
    for (int i = 0; i < CASCADE_COUNT; i++)
    {
        if (depth < Cascades[i].SplitDepth.y)
        {
            cascadeIndex = i;
            break;
        }
    }

    float4 shadowPos = mul(float4(worldPos, 1.0), Cascades[cascadeIndex].ViewProjection);
    shadowPos.xyz /= shadowPos.w;
    // Convert to [0, 1] UV coordinates (must match CalculateShadow exactly)
    float2 shadowUV = shadowPos.xy * 0.5 + 0.5;

#if SHADOW_DEBUG_MODE == 1
    // Show UV coordinates as color (R=U, G=V, B=0)
    // Values should be in [0,1] range - red/green show UV coverage
    return float3(shadowUV.x, shadowUV.y, 0.0);
#elif SHADOW_DEBUG_MODE == 2
    // Show shadow clip-space depth as grayscale
    // Should be in [0,1] range - 0=near, 1=far
    float d = saturate(shadowPos.z);
    return float3(d, d, d);
#elif SHADOW_DEBUG_MODE == 3
    // Show cascade index as color
    float3 cascadeColors[4] = {
        float3(1, 0, 0),  // Red = cascade 0
        float3(0, 1, 0),  // Green = cascade 1
        float3(0, 0, 1),  // Blue = cascade 2
        float3(1, 1, 0)   // Yellow = cascade 3
    };
    return cascadeColors[cascadeIndex];
#elif SHADOW_DEBUG_MODE == 4
    // Show if UVs are out of bounds (should be in [0,1])
    // Green = valid UV, Red/Magenta = out of bounds
    if (shadowUV.x < 0.0 || shadowUV.x > 1.0 || shadowUV.y < 0.0 || shadowUV.y > 1.0)
        return float3(1, 0, 1);  // Magenta = UV out of bounds
    if (shadowPos.z < 0.0 || shadowPos.z > 1.0)
        return float3(1, 0, 0);  // Red = depth out of bounds
    return float3(0, 1, 0);  // Green = all values in valid range
#elif SHADOW_DEBUG_MODE == 5
    // Show view-space depth for cascade selection
    return float3(depth / 100.0, 0.0, 0.0);  // Scale by far plane for visibility
#else
    return float3(0, 0, 0);
#endif
}

// Point light attenuation (inverse square with range clamping)
float CalculateAttenuation(float distance, float range)
{
    float attenuation = saturate(1.0 - (distance / range));
    return attenuation * attenuation;
}

// ============================================================================
// PBR Functions
// ============================================================================

// Fresnel-Schlick approximation
float3 FresnelSchlick(float cosTheta, float3 F0)
{
    return F0 + (1.0 - F0) * pow(saturate(1.0 - cosTheta), 5.0);
}

// GGX/Trowbridge-Reitz normal distribution
float DistributionGGX(float3 N, float3 H, float roughness)
{
    float a = roughness * roughness;
    float a2 = a * a;
    float NdotH = max(dot(N, H), 0.0);
    float NdotH2 = NdotH * NdotH;

    float num = a2;
    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    denom = PI * denom * denom;

    return num / denom;
}

// Smith's Schlick-GGX geometry function
float GeometrySchlickGGX(float NdotV, float roughness)
{
    float r = roughness + 1.0;
    float k = (r * r) / 8.0;

    float num = NdotV;
    float denom = NdotV * (1.0 - k) + k;

    return num / denom;
}

float GeometrySmith(float3 N, float3 V, float3 L, float roughness)
{
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    float ggx2 = GeometrySchlickGGX(NdotV, roughness);
    float ggx1 = GeometrySchlickGGX(NdotL, roughness);

    return ggx1 * ggx2;
}

// Calculate direct lighting contribution
float3 CalculateDirectLight(float3 N, float3 V, float3 L, float3 radiance,
                            float3 albedo, float metallic, float roughness)
{
    float3 H = normalize(V + L);

    // Fresnel reflectance at normal incidence
    float3 F0 = lerp(float3(0.04, 0.04, 0.04), albedo, metallic);

    // Cook-Torrance BRDF
    float NDF = DistributionGGX(N, H, roughness);
    float G = GeometrySmith(N, V, L, roughness);
    float3 F = FresnelSchlick(max(dot(H, V), 0.0), F0);

    float3 numerator = NDF * G * F;
    float denominator = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.0001;
    float3 specular = numerator / denominator;

    // Energy conservation
    float3 kS = F;
    float3 kD = (1.0 - kS) * (1.0 - metallic);

    float NdotL = max(dot(N, L), 0.0);
    return (kD * albedo / PI + specular) * radiance * NdotL;
}

// ============================================================================
// Main Fragment Shader
// ============================================================================

float4 main(VS_OUTPUT input) : SV_TARGET
{
    // Sample base color
    float4 albedo = BaseColor;
#ifdef HAS_ALBEDO_MAP
    albedo *= AlbedoMap.Sample(MaterialSampler, input.TexCoord);
#endif

#ifdef ALPHA_TEST
    if (albedo.a < AlphaCutoff)
        discard;
#endif

    // Sample metallic/roughness
    float metallic = Metallic;
    float roughness = Roughness;
#ifdef HAS_METALLIC_ROUGHNESS_MAP
    float2 mr = MetallicRoughnessMap.Sample(MaterialSampler, input.TexCoord).bg;
    metallic *= mr.x;
    roughness *= mr.y;
#endif

    // Sample AO
    float ao = AO;
#ifdef HAS_AO_MAP
    ao *= AOMap.Sample(MaterialSampler, input.TexCoord).r;
#endif

    // Get normal
    float3 N = normalize(input.Normal);
#ifdef NORMAL_MAP
#ifdef HAS_NORMAL_MAP
    float3 tangentNormal = NormalMap.Sample(MaterialSampler, input.TexCoord).xyz;
    tangentNormal = UnpackNormal(tangentNormal);
    float3x3 TBN = float3x3(input.Tangent, input.Bitangent, input.Normal);
    N = normalize(mul(tangentNormal, TBN));
#endif
#endif

    // View direction
    float3 V = normalize(CameraPosition - input.WorldPos);

    // Calculate lighting
    float3 Lo = float3(0, 0, 0);

    // Directional light (sun) with shadows
    {
        float3 L = normalize(-SunLight.Direction);
        float3 radiance = SunLight.Color * SunLight.Intensity;

        // Calculate shadow (1.0 = fully lit, 0.0 = fully shadowed)
        float shadow = 1.0;
#ifdef RECEIVE_SHADOWS
        shadow = CalculateShadow(input.WorldPos, N);

        // Debug visualization - uncomment to debug shadow issues
        // Change SHADOW_DEBUG_MODE at top of file: 1=UV, 2=depth, 3=cascade
#if SHADOW_DEBUG_MODE != 0
        return float4(DebugShadow(input.WorldPos, N), 1.0);
#endif
#endif

        Lo += CalculateDirectLight(N, V, L, radiance * shadow, albedo.rgb, metallic, roughness);
    }

    // Point lights
    for (int i = 0; i < ActivePointLights && i < MAX_POINT_LIGHTS; i++)
    {
        float3 lightVec = PointLights[i].Position - input.WorldPos;
        float distance = length(lightVec);

        if (distance < PointLights[i].Range)
        {
            float3 L = lightVec / distance;
            float attenuation = CalculateAttenuation(distance, PointLights[i].Range);
            float3 radiance = PointLights[i].Color * PointLights[i].Intensity * attenuation;
            Lo += CalculateDirectLight(N, V, L, radiance, albedo.rgb, metallic, roughness);
        }
    }

    // Ambient lighting (simplified IBL approximation)
    float3 F0 = lerp(float3(0.04, 0.04, 0.04), albedo.rgb, metallic);
    float3 F = FresnelSchlick(max(dot(N, V), 0.0), F0);
    float3 kD = (1.0 - F) * (1.0 - metallic);
    float3 ambient = (kD * albedo.rgb * AmbientColor * AmbientIntensity) * ao;

    float3 color = ambient + Lo;

    // Add emissive
#ifdef EMISSIVE
    float3 emissive = EmissiveColor.rgb;
#ifdef HAS_EMISSIVE_MAP
    emissive *= EmissiveMap.Sample(MaterialSampler, input.TexCoord).rgb;
#endif
    color += emissive;
#endif

    return float4(color, albedo.a);
}
