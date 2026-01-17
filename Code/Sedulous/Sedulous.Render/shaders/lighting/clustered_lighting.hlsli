// Clustered lighting utilities
// Provides cluster lookup and PBR light evaluation

#ifndef CLUSTERED_LIGHTING_HLSLI
#define CLUSTERED_LIGHTING_HLSLI

#include "../shadows/shadow_sampling.hlsli"

// --------------------------------------------------
// Constants
// --------------------------------------------------

#define MAX_LIGHTS_PER_CLUSTER 256
#define PI 3.14159265359
#define EPSILON 0.0001

// --------------------------------------------------
// GPU Light structure (must match LightBuffer.bf GPULight)
// --------------------------------------------------

struct GPULight
{
    float3 position;     // World position
    float range;         // Light range

    float3 direction;    // Normalized direction (for spot/directional)
    uint type;           // 0=Directional, 1=Point, 2=Spot

    float3 color;        // RGB color
    float intensity;     // Light intensity

    float innerConeAngle; // Spot inner cone (radians)
    float outerConeAngle; // Spot outer cone (radians)
    int shadowIndex;      // Shadow map index (-1 = no shadow)
    float padding;
};

// --------------------------------------------------
// Cluster data structures
// --------------------------------------------------

struct ClusterLightInfo
{
    uint offset;  // Offset into light index list
    uint count;   // Number of lights in cluster
};

// --------------------------------------------------
// Buffers
// --------------------------------------------------

// Cluster grid uniforms
cbuffer ClusterUniforms : register(b0, space2)
{
    uint clustersX;
    uint clustersY;
    uint clustersZ;
    uint _pad0;

    float screenWidth;
    float screenHeight;
    float nearPlane;
    float farPlane;

    float logDepthScale;
    float logDepthBias;
    float tileSizeX;
    float tileSizeY;
};

// Lighting uniforms
cbuffer LightingUniforms : register(b1, space2)
{
    float3 ambientColor;
    uint activeLightCount;

    float3 sunDirection;
    float sunIntensity;

    float3 sunColor;
    float _lightPad;
};

// Light data buffer
StructuredBuffer<GPULight> lightBuffer : register(t0, space2);

// Per-cluster light info (offset, count)
StructuredBuffer<ClusterLightInfo> clusterLightInfo : register(t1, space2);

// Global light index list
StructuredBuffer<uint> lightIndexList : register(t2, space2);

// --------------------------------------------------
// Cluster lookup
// --------------------------------------------------

uint GetClusterIndex(float2 screenPos, float viewDepth)
{
    // Screen tile
    uint tileX = uint(screenPos.x / tileSizeX);
    uint tileY = uint(screenPos.y / tileSizeY);

    // Depth slice using logarithmic distribution
    float logDepth = log(viewDepth / nearPlane) / log(farPlane / nearPlane);
    uint tileZ = uint(logDepth * clustersZ);

    // Clamp to valid range
    tileX = min(tileX, clustersX - 1);
    tileY = min(tileY, clustersY - 1);
    tileZ = min(tileZ, clustersZ - 1);

    // Linear index
    return tileX + tileY * clustersX + tileZ * clustersX * clustersY;
}

ClusterLightInfo GetClusterLightInfo(uint clusterIndex)
{
    return clusterLightInfo[clusterIndex];
}

// --------------------------------------------------
// PBR Helper Functions
// --------------------------------------------------

// Normal Distribution Function (GGX/Trowbridge-Reitz)
float DistributionGGX(float3 N, float3 H, float roughness)
{
    float a = roughness * roughness;
    float a2 = a * a;
    float NdotH = max(dot(N, H), 0.0);
    float NdotH2 = NdotH * NdotH;

    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    denom = PI * denom * denom;

    return a2 / max(denom, EPSILON);
}

// Geometry function (Schlick-GGX)
float GeometrySchlickGGX(float NdotV, float roughness)
{
    float r = (roughness + 1.0);
    float k = (r * r) / 8.0;

    float denom = NdotV * (1.0 - k) + k;
    return NdotV / max(denom, EPSILON);
}

// Smith's geometry function
float GeometrySmith(float3 N, float3 V, float3 L, float roughness)
{
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    float ggx1 = GeometrySchlickGGX(NdotV, roughness);
    float ggx2 = GeometrySchlickGGX(NdotL, roughness);

    return ggx1 * ggx2;
}

// Fresnel-Schlick approximation
float3 FresnelSchlick(float cosTheta, float3 F0)
{
    return F0 + (1.0 - F0) * pow(saturate(1.0 - cosTheta), 5.0);
}

// --------------------------------------------------
// Light Attenuation
// --------------------------------------------------

float GetDistanceAttenuation(float distance, float range)
{
    // Inverse square falloff with smooth transition at edge
    float d2 = distance * distance;
    float r2 = range * range;
    float attenuation = 1.0 / max(d2, 0.01);

    // Smooth falloff at range boundary
    float factor = saturate(1.0 - (distance / range));
    factor = factor * factor;

    return attenuation * factor;
}

float GetSpotAttenuation(float3 L, float3 spotDir, float innerCone, float outerCone)
{
    float cosAngle = dot(-L, spotDir);
    float cosOuter = cos(outerCone);
    float cosInner = cos(innerCone);

    return saturate((cosAngle - cosOuter) / max(cosInner - cosOuter, EPSILON));
}

// --------------------------------------------------
// PBR BRDF Evaluation
// --------------------------------------------------

float3 EvaluateBRDF(float3 N, float3 V, float3 L, float3 albedo, float metallic, float roughness)
{
    float3 H = normalize(V + L);

    // F0: reflectance at normal incidence
    float3 F0 = lerp(float3(0.04, 0.04, 0.04), albedo, metallic);

    // Cook-Torrance BRDF
    float D = DistributionGGX(N, H, roughness);
    float G = GeometrySmith(N, V, L, roughness);
    float3 F = FresnelSchlick(max(dot(H, V), 0.0), F0);

    float3 numerator = D * G * F;
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    float denominator = 4.0 * NdotV * NdotL + EPSILON;
    float3 specular = numerator / denominator;

    // Diffuse uses kD (1 - kS, with metallic reducing diffuse)
    float3 kS = F;
    float3 kD = (1.0 - kS) * (1.0 - metallic);

    float3 diffuse = kD * albedo / PI;

    return (diffuse + specular) * NdotL;
}

// --------------------------------------------------
// Evaluate Single Light
// --------------------------------------------------

float3 EvaluateLight(GPULight light, float3 worldPos, float3 N, float3 V,
                     float3 albedo, float metallic, float roughness)
{
    float3 L;
    float attenuation = 1.0;
    float shadow = 1.0;

    if (light.type == 0) // Directional
    {
        L = -normalize(light.direction);

        // Sample cascaded shadows
        if (light.shadowIndex >= 0)
        {
            float viewDepth = length(worldPos); // Would need camera position for proper calc
            shadow = SampleCascadedShadowBlended(worldPos, N, viewDepth);
        }
    }
    else if (light.type == 1) // Point
    {
        float3 toLight = light.position - worldPos;
        float distance = length(toLight);
        L = toLight / max(distance, EPSILON);

        attenuation = GetDistanceAttenuation(distance, light.range);

        // Sample point light shadow
        if (light.shadowIndex >= 0)
        {
            shadow = SamplePointLightShadow(worldPos, light.position, light.range, light.shadowIndex);
        }
    }
    else // Spot (type == 2)
    {
        float3 toLight = light.position - worldPos;
        float distance = length(toLight);
        L = toLight / max(distance, EPSILON);

        attenuation = GetDistanceAttenuation(distance, light.range);
        attenuation *= GetSpotAttenuation(L, light.direction, light.innerConeAngle, light.outerConeAngle);

        // Sample spot light shadow - would need shadow data lookup
        // For now, use simple shadow if available
        if (light.shadowIndex >= 0)
        {
            // Would need lightViewProj and uvOffsetScale from shadow data buffer
            // shadow = SampleSpotLightShadow(worldPos, lightViewProj, uvOffsetScale);
        }
    }

    // Evaluate BRDF
    float3 radiance = light.color * light.intensity * attenuation * shadow;
    float3 brdf = EvaluateBRDF(N, V, L, albedo, metallic, roughness);

    return brdf * radiance;
}

// --------------------------------------------------
// Main Clustered Lighting Function
// --------------------------------------------------

float3 CalculateClusteredLighting(
    float3 worldPos,
    float3 worldNormal,
    float3 viewDir,
    float2 screenPos,
    float viewDepth,
    float3 albedo,
    float metallic,
    float roughness,
    float ao)
{
    float3 N = normalize(worldNormal);
    float3 V = normalize(viewDir);

    // Ambient lighting
    float3 ambient = ambientColor * albedo * ao;

    // Get cluster for this fragment
    uint clusterIndex = GetClusterIndex(screenPos, viewDepth);
    ClusterLightInfo info = GetClusterLightInfo(clusterIndex);

    // Accumulate lighting from all lights in cluster
    float3 Lo = float3(0.0, 0.0, 0.0);

    for (uint i = 0; i < info.count && i < MAX_LIGHTS_PER_CLUSTER; i++)
    {
        uint lightIndex = lightIndexList[info.offset + i];
        GPULight light = lightBuffer[lightIndex];

        Lo += EvaluateLight(light, worldPos, N, V, albedo, metallic, roughness);
    }

    return ambient + Lo;
}

// --------------------------------------------------
// Simple forward lighting (for testing without clusters)
// --------------------------------------------------

float3 CalculateForwardLighting(
    float3 worldPos,
    float3 worldNormal,
    float3 viewDir,
    float3 albedo,
    float metallic,
    float roughness,
    float ao)
{
    float3 N = normalize(worldNormal);
    float3 V = normalize(viewDir);

    // Ambient
    float3 ambient = ambientColor * albedo * ao;

    // Accumulate all lights
    float3 Lo = float3(0.0, 0.0, 0.0);

    for (uint i = 0; i < activeLightCount; i++)
    {
        GPULight light = lightBuffer[i];
        Lo += EvaluateLight(light, worldPos, N, V, albedo, metallic, roughness);
    }

    return ambient + Lo;
}

#endif // CLUSTERED_LIGHTING_HLSLI
