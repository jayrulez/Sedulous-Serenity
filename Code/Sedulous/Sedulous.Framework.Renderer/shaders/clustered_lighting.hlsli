// Clustered Forward Lighting - Shader Include
// 16x9x24 cluster grid with logarithmic depth slicing

#ifndef CLUSTERED_LIGHTING_HLSLI
#define CLUSTERED_LIGHTING_HLSLI

static const float PI = 3.14159265359;

// Cluster constants - must match ClusterConstants in LightingData.bf
static const uint CLUSTER_TILES_X = 16;
static const uint CLUSTER_TILES_Y = 9;
static const uint CLUSTER_DEPTH_SLICES = 24;
static const uint MAX_LIGHTS_PER_CLUSTER = 256;

// Light types
static const uint LIGHT_TYPE_DIRECTIONAL = 0;
static const uint LIGHT_TYPE_POINT = 1;
static const uint LIGHT_TYPE_SPOT = 2;

// GPU light structure - matches GPUClusteredLight in LightingData.bf
struct ClusteredLight
{
    float4 PositionType;    // xyz=position, w=type
    float4 DirectionRange;  // xyz=direction, w=range
    float4 ColorIntensity;  // rgb=color*intensity, a=intensity
    float4 SpotShadowFlags; // x=cos(innerAngle), y=cos(outerAngle), z=shadowIndex, w=flags
};

// Light grid entry - matches LightGridEntry in LightingData.bf
struct LightGridEntry
{
    uint Offset;
    uint Count;
    uint _pad0;
    uint _pad1;
};

// Lighting uniform buffer - matches LightingUniforms in LightingData.bf
cbuffer LightingUniforms : register(b2)
{
    float4x4 g_ViewMatrix;
    float4x4 g_InverseProjection;
    float4 g_ScreenParams;    // xy=screen size, zw=tile size
    float4 g_ClusterParams;   // x=near, y=far, z=depthScale, w=depthBias
    float4 g_DirectionalDir;  // xyz=direction, w=intensity
    float4 g_DirectionalColor; // rgb=color, a=shadowIndex
    uint g_LightCount;
    uint g_DebugFlags;
    uint _pad0;
    uint _pad1;
};

// Structured buffers
StructuredBuffer<ClusteredLight> g_Lights : register(t10);
StructuredBuffer<LightGridEntry> g_LightGrid : register(t11);
StructuredBuffer<uint> g_LightIndices : register(t12);

// Computes the cluster index for a given screen position and view depth
uint3 GetClusterIndex(float2 screenPos, float viewZ)
{
    // Tile index from screen position
    uint clusterX = uint(screenPos.x / g_ScreenParams.z);
    uint clusterY = uint(screenPos.y / g_ScreenParams.w);

    // Clamp to valid range
    clusterX = min(clusterX, CLUSTER_TILES_X - 1);
    clusterY = min(clusterY, CLUSTER_TILES_Y - 1);

    // Depth slice using logarithmic distribution
    // slice = depthScale * log(viewZ) + depthBias
    float depthScale = g_ClusterParams.z;
    float depthBias = g_ClusterParams.w;
    uint clusterZ = uint(max(0.0, depthScale * log(abs(viewZ)) + depthBias));
    clusterZ = min(clusterZ, CLUSTER_DEPTH_SLICES - 1);

    return uint3(clusterX, clusterY, clusterZ);
}

// Converts cluster 3D index to linear index
uint ClusterIndexToLinear(uint3 clusterIndex)
{
    return clusterIndex.x +
           clusterIndex.y * CLUSTER_TILES_X +
           clusterIndex.z * CLUSTER_TILES_X * CLUSTER_TILES_Y;
}

// Distance attenuation for point/spot lights (smooth falloff)
float ComputeDistanceAttenuation(float distance, float range)
{
    if (distance >= range)
        return 0.0;

    // Smooth inverse-square falloff with range
    float distNorm = distance / range;
    float attenuation = saturate(1.0 - distNorm * distNorm);
    return attenuation * attenuation;
}

// Spot light angular attenuation
float ComputeSpotAttenuation(float3 toLight, float3 spotDir, float cosInner, float cosOuter)
{
    float cosAngle = dot(normalize(-toLight), spotDir);

    if (cosAngle <= cosOuter)
        return 0.0;
    if (cosAngle >= cosInner)
        return 1.0;

    float t = (cosAngle - cosOuter) / (cosInner - cosOuter);
    return t * t;
}

// Computes lighting contribution from a single light
float3 ComputeLightContribution(
    ClusteredLight light,
    float3 worldPos,
    float3 N,
    float3 V,
    float3 albedo,
    float metallic,
    float roughness,
    float3 F0)
{
    uint lightType = uint(light.PositionType.w);
    float3 lightColor = light.ColorIntensity.rgb;

    float3 L;
    float attenuation = 1.0;

    if (lightType == LIGHT_TYPE_DIRECTIONAL)
    {
        L = normalize(-light.DirectionRange.xyz);
    }
    else
    {
        float3 lightPos = light.PositionType.xyz;
        float3 toLight = lightPos - worldPos;
        float distance = length(toLight);
        L = toLight / distance;

        float range = light.DirectionRange.w;
        attenuation = ComputeDistanceAttenuation(distance, range);

        if (lightType == LIGHT_TYPE_SPOT)
        {
            float3 spotDir = normalize(light.DirectionRange.xyz);
            float cosInner = light.SpotShadowFlags.x;
            float cosOuter = light.SpotShadowFlags.y;
            attenuation *= ComputeSpotAttenuation(toLight, spotDir, cosInner, cosOuter);
        }
    }

    if (attenuation <= 0.0)
        return float3(0, 0, 0);

    // Standard PBR lighting calculation
    float3 H = normalize(V + L);
    float NdotL = max(dot(N, L), 0.0);
    float NdotV = max(dot(N, V), 0.0);
    float NdotH = max(dot(N, H), 0.0);
    float HdotV = max(dot(H, V), 0.0);

    // GGX Distribution
    float a = roughness * roughness;
    float a2 = a * a;
    float denom = (NdotH * NdotH * (a2 - 1.0) + 1.0);
    float D = a2 / (PI * denom * denom);

    // Schlick-GGX Geometry
    float r = (roughness + 1.0);
    float k = (r * r) / 8.0;
    float G1V = NdotV / (NdotV * (1.0 - k) + k);
    float G1L = NdotL / (NdotL * (1.0 - k) + k);
    float G = G1V * G1L;

    // Fresnel (Schlick)
    float3 F = F0 + (1.0 - F0) * pow(1.0 - HdotV, 5.0);

    // Cook-Torrance BRDF
    float3 numerator = D * G * F;
    float denominator = 4.0 * NdotV * NdotL + 0.0001;
    float3 specular = numerator / denominator;

    // Energy conservation
    float3 kS = F;
    float3 kD = (1.0 - kS) * (1.0 - metallic);

    // Final contribution
    return (kD * albedo / PI + specular) * lightColor * attenuation * NdotL;
}

// Computes total lighting for a pixel using clustered forward
float3 ComputeClusteredLighting(
    float2 screenPos,
    float viewZ,
    float3 worldPos,
    float3 N,
    float3 V,
    float3 albedo,
    float metallic,
    float roughness)
{
    // Calculate F0 (reflectance at normal incidence)
    float3 F0 = lerp(float3(0.04, 0.04, 0.04), albedo, metallic);

    float3 totalLight = float3(0, 0, 0);

    // Add directional light contribution
    if (g_DirectionalDir.w > 0.0)
    {
        ClusteredLight dirLight;
        dirLight.PositionType = float4(0, 0, 0, LIGHT_TYPE_DIRECTIONAL);
        dirLight.DirectionRange = g_DirectionalDir;
        dirLight.ColorIntensity = float4(g_DirectionalColor.rgb * g_DirectionalDir.w, g_DirectionalDir.w);
        dirLight.SpotShadowFlags = float4(0, 0, g_DirectionalColor.a, 0);

        totalLight += ComputeLightContribution(dirLight, worldPos, N, V, albedo, metallic, roughness, F0);
    }

    // Get cluster for this pixel
    uint3 clusterIndex = GetClusterIndex(screenPos, viewZ);
    uint linearIndex = ClusterIndexToLinear(clusterIndex);

    // Get light list for this cluster
    LightGridEntry gridEntry = g_LightGrid[linearIndex];

    // Iterate over lights in this cluster
    for (uint i = 0; i < gridEntry.Count && i < MAX_LIGHTS_PER_CLUSTER; i++)
    {
        uint lightIndex = g_LightIndices[gridEntry.Offset + i];
        ClusteredLight light = g_Lights[lightIndex];

        totalLight += ComputeLightContribution(light, worldPos, N, V, albedo, metallic, roughness, F0);
    }

    return totalLight;
}

// Simplified version for use without cluster data (fallback for debug)
float3 ComputeSimpleLighting(
    float3 worldPos,
    float3 N,
    float3 V,
    float3 albedo,
    float metallic,
    float roughness)
{
    float3 F0 = lerp(float3(0.04, 0.04, 0.04), albedo, metallic);
    float3 totalLight = float3(0, 0, 0);

    // Just process directional light
    if (g_DirectionalDir.w > 0.0)
    {
        ClusteredLight dirLight;
        dirLight.PositionType = float4(0, 0, 0, LIGHT_TYPE_DIRECTIONAL);
        dirLight.DirectionRange = g_DirectionalDir;
        dirLight.ColorIntensity = float4(g_DirectionalColor.rgb * g_DirectionalDir.w, g_DirectionalDir.w);
        dirLight.SpotShadowFlags = float4(0, 0, g_DirectionalColor.a, 0);

        totalLight += ComputeLightContribution(dirLight, worldPos, N, V, albedo, metallic, roughness, F0);
    }

    // Process all lights without culling (for small light counts)
    for (uint i = 0; i < g_LightCount; i++)
    {
        ClusteredLight light = g_Lights[i];
        totalLight += ComputeLightContribution(light, worldPos, N, V, albedo, metallic, roughness, F0);
    }

    return totalLight;
}

#endif // CLUSTERED_LIGHTING_HLSLI
