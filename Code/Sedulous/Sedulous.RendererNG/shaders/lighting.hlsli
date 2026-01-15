// Lighting shader include for Sedulous.RendererNG
// Contains PBR lighting calculations and clustered light access

#ifndef LIGHTING_HLSLI
#define LIGHTING_HLSLI

// ============================================================================
// Constants
// ============================================================================

static const float PI = 3.14159265359;
static const float INV_PI = 0.31830988618;
static const uint LIGHT_TYPE_DIRECTIONAL = 0;
static const uint LIGHT_TYPE_POINT = 1;
static const uint LIGHT_TYPE_SPOT = 2;
static const uint MAX_LIGHTS_PER_CLUSTER = 256;

// ============================================================================
// Light Data Structures (must match Beef structs)
// ============================================================================

struct LightData
{
    float3 Position;
    float Range;

    float3 Direction;
    float SpotInnerAngle;

    float3 Color;
    float Intensity;

    uint Type;
    float SpotOuterAngle;
    uint ShadowIndex;
    uint Padding;
};

struct LightingParams
{
    float3 AmbientColor;
    float AmbientIntensity;

    float3 SunDirection;
    float SunIntensity;

    float3 SunColor;
    uint LightCount;

    float4 FogParams; // x=start, y=end, z=density, w=mode
    float3 FogColor;
    float Padding;
};

struct ClusterData
{
    uint Offset;
    uint Count;
};

// ============================================================================
// Uniform Buffers
// ============================================================================

cbuffer LightingParamsBuffer : register(b2)
{
    LightingParams g_LightingParams;
}

// ============================================================================
// Resources
// ============================================================================

StructuredBuffer<LightData> g_Lights : register(t4);
StructuredBuffer<ClusterData> g_ClusterLightData : register(t5);
StructuredBuffer<uint> g_LightIndices : register(t6);

// ============================================================================
// PBR Functions
// ============================================================================

// Normal Distribution Function (GGX/Trowbridge-Reitz)
float DistributionGGX(float3 N, float3 H, float roughness)
{
    float a = roughness * roughness;
    float a2 = a * a;
    float NdotH = max(dot(N, H), 0.0);
    float NdotH2 = NdotH * NdotH;

    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    denom = PI * denom * denom;

    return a2 / max(denom, 0.0001);
}

// Geometry Function (Schlick-GGX)
float GeometrySchlickGGX(float NdotV, float roughness)
{
    float r = roughness + 1.0;
    float k = (r * r) / 8.0;
    return NdotV / (NdotV * (1.0 - k) + k);
}

// Geometry Function (Smith's method)
float GeometrySmith(float3 N, float3 V, float3 L, float roughness)
{
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    float ggx1 = GeometrySchlickGGX(NdotV, roughness);
    float ggx2 = GeometrySchlickGGX(NdotL, roughness);
    return ggx1 * ggx2;
}

// Fresnel Function (Schlick approximation)
float3 FresnelSchlick(float cosTheta, float3 F0)
{
    return F0 + (1.0 - F0) * pow(saturate(1.0 - cosTheta), 5.0);
}

// Fresnel with roughness for ambient
float3 FresnelSchlickRoughness(float cosTheta, float3 F0, float roughness)
{
    float3 oneMinusRough = float3(1.0 - roughness, 1.0 - roughness, 1.0 - roughness);
    return F0 + (max(oneMinusRough, F0) - F0) * pow(saturate(1.0 - cosTheta), 5.0);
}

// ============================================================================
// Attenuation
// ============================================================================

// Smooth distance attenuation (UE4-style)
float DistanceAttenuation(float distance, float range)
{
    float d = distance / range;
    float d2 = d * d;
    float d4 = d2 * d2;
    float falloff = saturate(1.0 - d4);
    return (falloff * falloff) / (distance * distance + 1.0);
}

// Spot light angular attenuation
float SpotAttenuation(float3 L, float3 spotDir, float innerAngle, float outerAngle)
{
    float cosOuter = cos(outerAngle);
    float cosInner = cos(innerAngle);
    float cosAngle = dot(-L, spotDir);
    return saturate((cosAngle - cosOuter) / (cosInner - cosOuter));
}

// ============================================================================
// PBR Direct Lighting
// ============================================================================

float3 CalculateDirectLighting(
    float3 N, float3 V, float3 L, float3 lightColor, float lightIntensity,
    float3 albedo, float metallic, float roughness, float3 F0)
{
    float3 H = normalize(V + L);
    float NdotL = max(dot(N, L), 0.0);

    if (NdotL <= 0.0)
        return float3(0, 0, 0);

    // Cook-Torrance BRDF
    float D = DistributionGGX(N, H, roughness);
    float G = GeometrySmith(N, V, L, roughness);
    float3 F = FresnelSchlick(max(dot(H, V), 0.0), F0);

    float3 numerator = D * G * F;
    float denominator = 4.0 * max(dot(N, V), 0.0) * NdotL + 0.0001;
    float3 specular = numerator / denominator;

    // Energy conservation
    float3 kS = F;
    float3 kD = (1.0 - kS) * (1.0 - metallic);

    float3 diffuse = kD * albedo * INV_PI;

    return (diffuse + specular) * lightColor * lightIntensity * NdotL;
}

// ============================================================================
// Light Evaluation
// ============================================================================

float3 EvaluateDirectionalLight(
    LightData light, float3 worldPos, float3 N, float3 V,
    float3 albedo, float metallic, float roughness, float3 F0)
{
    float3 L = normalize(-light.Direction);
    return CalculateDirectLighting(N, V, L, light.Color, light.Intensity,
                                   albedo, metallic, roughness, F0);
}

float3 EvaluatePointLight(
    LightData light, float3 worldPos, float3 N, float3 V,
    float3 albedo, float metallic, float roughness, float3 F0)
{
    float3 toLight = light.Position - worldPos;
    float distance = length(toLight);

    if (distance > light.Range)
        return float3(0, 0, 0);

    float3 L = toLight / distance;
    float attenuation = DistanceAttenuation(distance, light.Range);

    return CalculateDirectLighting(N, V, L, light.Color, light.Intensity * attenuation,
                                   albedo, metallic, roughness, F0);
}

float3 EvaluateSpotLight(
    LightData light, float3 worldPos, float3 N, float3 V,
    float3 albedo, float metallic, float roughness, float3 F0)
{
    float3 toLight = light.Position - worldPos;
    float distance = length(toLight);

    if (distance > light.Range)
        return float3(0, 0, 0);

    float3 L = toLight / distance;
    float distAtten = DistanceAttenuation(distance, light.Range);
    float spotAtten = SpotAttenuation(L, light.Direction, light.SpotInnerAngle, light.SpotOuterAngle);
    float attenuation = distAtten * spotAtten;

    if (attenuation <= 0.0)
        return float3(0, 0, 0);

    return CalculateDirectLighting(N, V, L, light.Color, light.Intensity * attenuation,
                                   albedo, metallic, roughness, F0);
}

float3 EvaluateLight(
    LightData light, float3 worldPos, float3 N, float3 V,
    float3 albedo, float metallic, float roughness, float3 F0)
{
    switch (light.Type)
    {
    case LIGHT_TYPE_DIRECTIONAL:
        return EvaluateDirectionalLight(light, worldPos, N, V, albedo, metallic, roughness, F0);
    case LIGHT_TYPE_POINT:
        return EvaluatePointLight(light, worldPos, N, V, albedo, metallic, roughness, F0);
    case LIGHT_TYPE_SPOT:
        return EvaluateSpotLight(light, worldPos, N, V, albedo, metallic, roughness, F0);
    default:
        return float3(0, 0, 0);
    }
}

// ============================================================================
// Sun Light (Main Directional)
// ============================================================================

float3 EvaluateSunLight(
    float3 worldPos, float3 N, float3 V,
    float3 albedo, float metallic, float roughness, float3 F0)
{
    if (g_LightingParams.SunIntensity <= 0.0)
        return float3(0, 0, 0);

    float3 L = normalize(-g_LightingParams.SunDirection);
    return CalculateDirectLighting(N, V, L, g_LightingParams.SunColor, g_LightingParams.SunIntensity,
                                   albedo, metallic, roughness, F0);
}

// ============================================================================
// Ambient Lighting
// ============================================================================

float3 CalculateAmbient(float3 N, float3 V, float3 albedo, float metallic, float roughness, float ao)
{
    float3 F0 = lerp(float3(0.04, 0.04, 0.04), albedo, metallic);
    float3 F = FresnelSchlickRoughness(max(dot(N, V), 0.0), F0, roughness);

    float3 kS = F;
    float3 kD = (1.0 - kS) * (1.0 - metallic);

    float3 ambient = kD * albedo * g_LightingParams.AmbientColor * g_LightingParams.AmbientIntensity;
    return ambient * ao;
}

// ============================================================================
// Fog
// ============================================================================

float3 ApplyFog(float3 color, float viewDistance)
{
    float fogMode = g_LightingParams.FogParams.w;

    if (fogMode < 0.5)
        return color; // No fog

    float fogFactor = 0.0;
    float fogStart = g_LightingParams.FogParams.x;
    float fogEnd = g_LightingParams.FogParams.y;
    float fogDensity = g_LightingParams.FogParams.z;

    if (fogMode < 1.5) // Linear
    {
        fogFactor = saturate((viewDistance - fogStart) / (fogEnd - fogStart));
    }
    else if (fogMode < 2.5) // Exponential
    {
        fogFactor = 1.0 - exp(-fogDensity * viewDistance);
    }
    else // Exponential squared
    {
        float f = fogDensity * viewDistance;
        fogFactor = 1.0 - exp(-f * f);
    }

    return lerp(color, g_LightingParams.FogColor, fogFactor);
}

// ============================================================================
// Clustered Lighting (requires cluster uniforms)
// ============================================================================

#ifdef USE_CLUSTERED_LIGHTING

cbuffer ClusterParams : register(b3)
{
    uint3 g_ClusterGridSize;
    uint g_ClusterPadding;
    float g_ClusterNear;
    float g_ClusterFar;
    float g_ClusterLogScale;
    float g_ClusterBias;
}

uint GetClusterIndex(float2 screenPos, float viewDepth, uint2 screenSize)
{
    // Screen position to cluster X,Y
    uint clusterX = (uint)(screenPos.x / screenSize.x * g_ClusterGridSize.x);
    uint clusterY = (uint)(screenPos.y / screenSize.y * g_ClusterGridSize.y);

    // Logarithmic depth slice
    float logDepth = log(viewDepth / g_ClusterNear);
    uint clusterZ = (uint)(logDepth * g_ClusterLogScale + g_ClusterBias);

    clusterX = min(clusterX, g_ClusterGridSize.x - 1);
    clusterY = min(clusterY, g_ClusterGridSize.y - 1);
    clusterZ = min(clusterZ, g_ClusterGridSize.z - 1);

    return clusterX + clusterY * g_ClusterGridSize.x +
           clusterZ * g_ClusterGridSize.x * g_ClusterGridSize.y;
}

float3 EvaluateClusteredLights(
    float3 worldPos, float3 N, float3 V,
    float3 albedo, float metallic, float roughness, float3 F0,
    float2 screenPos, float viewDepth, uint2 screenSize)
{
    uint clusterIndex = GetClusterIndex(screenPos, viewDepth, screenSize);
    ClusterData cluster = g_ClusterLightData[clusterIndex];

    float3 result = float3(0, 0, 0);

    for (uint i = 0; i < cluster.Count && i < MAX_LIGHTS_PER_CLUSTER; i++)
    {
        uint lightIndex = g_LightIndices[cluster.Offset + i];
        LightData light = g_Lights[lightIndex];
        result += EvaluateLight(light, worldPos, N, V, albedo, metallic, roughness, F0);
    }

    return result;
}

#endif // USE_CLUSTERED_LIGHTING

#endif // LIGHTING_HLSLI
