// Clustered Forward Lighting - Shader Include
// 16x9x24 cluster grid with logarithmic depth slicing
// Uses row-major matrices with row-vector math: mul(vector, matrix)

#ifndef CLUSTERED_LIGHTING_HLSLI
#define CLUSTERED_LIGHTING_HLSLI

#pragma pack_matrix(row_major)

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

// ==================== SHADOW MAPPING ====================

// Shadow constants - must match ShadowConstants in LightingData.bf
static const uint SHADOW_CASCADE_COUNT = 4;
static const uint SHADOW_MAX_TILES = 64;

// Cascade data structure - matches CascadeData in LightingData.bf
struct CascadeData
{
    float4x4 ViewProjection;
    float4 SplitDepths;  // x=near, y=far, z=unused, w=unused
};

// Shadow tile data - matches GPUShadowTileData in LightingData.bf
struct ShadowTileData
{
    float4x4 ViewProjection;
    float4 UVOffsetScale;  // xy=offset, zw=scale
    int LightIndex;
    int FaceIndex;
    int _pad0;
    int _pad1;
};

// Shadow textures and sampler
Texture2DArray<float> g_CascadeShadowMap : register(t13);
Texture2D<float> g_ShadowAtlas : register(t14);
SamplerComparisonState g_ShadowSampler : register(s1);

// Shadow uniform buffer - matches ShadowUniforms in LightingData.bf
cbuffer ShadowUniforms : register(b4)
{
    CascadeData g_Cascades[SHADOW_CASCADE_COUNT];
    ShadowTileData g_ShadowTiles[SHADOW_MAX_TILES];
    uint g_ActiveTileCount;
    float g_AtlasTexelSize;
    float g_CascadeTexelSize;
    uint g_DirectionalShadowEnabled;
};

// 3x3 PCF shadow sampling for cascade shadow maps
float SampleCascadeShadowPCF(float3 shadowCoord, int cascadeIndex)
{
    float shadow = 0.0;
    float texelSize = g_CascadeTexelSize;

    // 3x3 PCF kernel
    [unroll]
    for (int y = -1; y <= 1; y++)
    {
        [unroll]
        for (int x = -1; x <= 1; x++)
        {
            float2 offset = float2(x, y) * texelSize;
            shadow += g_CascadeShadowMap.SampleCmpLevelZero(
                g_ShadowSampler,
                float3(shadowCoord.xy + offset, cascadeIndex),
                shadowCoord.z
            );
        }
    }

    return shadow / 9.0;
}

// 3x3 PCF shadow sampling for atlas
float SampleAtlasShadowPCF(float2 atlasUV, float depth)
{
    float shadow = 0.0;
    float texelSize = g_AtlasTexelSize;

    [unroll]
    for (int y = -1; y <= 1; y++)
    {
        [unroll]
        for (int x = -1; x <= 1; x++)
        {
            float2 offset = float2(x, y) * texelSize;
            shadow += g_ShadowAtlas.SampleCmpLevelZero(
                g_ShadowSampler,
                atlasUV + offset,
                depth
            );
        }
    }

    return shadow / 9.0;
}

// Select cascade based on view-space depth
int SelectCascade(float viewZ)
{
    float absViewZ = abs(viewZ);

    for (int i = 0; i < SHADOW_CASCADE_COUNT; i++)
    {
        if (absViewZ < g_Cascades[i].SplitDepths.y)
            return i;
    }

    return SHADOW_CASCADE_COUNT - 1;  // Fallback to last cascade
}

// Sample directional light shadow (cascaded)
float SampleDirectionalShadow(float3 worldPos, float viewZ)
{
    if (g_DirectionalShadowEnabled == 0)
        return 1.0;

    // Select cascade based on view-space depth
    int cascadeIndex = SelectCascade(viewZ);

    // Transform to shadow space (row-vector: pos * matrix)
    float4 shadowPos = mul(float4(worldPos, 1.0), g_Cascades[cascadeIndex].ViewProjection);
    shadowPos.xyz /= shadowPos.w;

    // NDC to UV: [-1,1] -> [0,1]
    // Note: No Y flip needed - Vulkan NDC and texture coordinates both have Y increasing downward
    float2 shadowUV = shadowPos.xy * 0.5 + 0.5;

    // Check bounds - outside shadow map means lit
    if (any(shadowUV < 0.0) || any(shadowUV > 1.0))
        return 1.0;

    // Clamp depth to valid range
    float shadowDepth = saturate(shadowPos.z);

    return SampleCascadeShadowPCF(float3(shadowUV, shadowDepth), cascadeIndex);
}

// Sample point/spot light shadow (atlas)
float SampleLocalLightShadow(float3 worldPos, int shadowIndex, uint lightType)
{
    if (shadowIndex < 0 || shadowIndex >= (int)g_ActiveTileCount)
        return 1.0;

    ShadowTileData tile = g_ShadowTiles[shadowIndex];

    // Transform to shadow space (row-vector: pos * matrix)
    float4 shadowPos = mul(float4(worldPos, 1.0), tile.ViewProjection);
    shadowPos.xyz /= shadowPos.w;

    // Convert to UV in tile local space [0,1]
    // Note: No Y flip needed - Vulkan NDC and texture coordinates both have Y increasing downward
    float2 localUV = shadowPos.xy * 0.5 + 0.5;

    // Check bounds
    if (any(localUV < 0.0) || any(localUV > 1.0))
        return 1.0;

    // Map to atlas space using tile offset/scale
    float2 atlasUV = tile.UVOffsetScale.xy + localUV * tile.UVOffsetScale.zw;

    // Clamp depth
    float shadowDepth = saturate(shadowPos.z);

    return SampleAtlasShadowPCF(atlasUV, shadowDepth);
}

// Computes lighting with shadow support
float3 ComputeLightContributionWithShadow(
    ClusteredLight light,
    float3 worldPos,
    float3 N,
    float3 V,
    float3 albedo,
    float metallic,
    float roughness,
    float3 F0,
    float viewZ)
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

    // Shadow sampling
    float shadow = 1.0;
    int shadowIndex = int(light.SpotShadowFlags.z);
    bool castsShadows = light.SpotShadowFlags.w > 0.5;

    if (castsShadows)
    {
        if (lightType == LIGHT_TYPE_DIRECTIONAL)
        {
            shadow = SampleDirectionalShadow(worldPos, viewZ);
        }
        else
        {
            shadow = SampleLocalLightShadow(worldPos, shadowIndex, lightType);
        }
    }

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

    // Final contribution with shadow
    return (kD * albedo / PI + specular) * lightColor * attenuation * NdotL * shadow;
}

// Computes total lighting with shadows using clustered forward
float3 ComputeClusteredLightingWithShadows(
    float2 screenPos,
    float viewZ,
    float3 worldPos,
    float3 N,
    float3 V,
    float3 albedo,
    float metallic,
    float roughness)
{
    float3 F0 = lerp(float3(0.04, 0.04, 0.04), albedo, metallic);
    float3 totalLight = float3(0, 0, 0);

    // Add directional light contribution with shadow
    if (g_DirectionalDir.w > 0.0)
    {
        ClusteredLight dirLight;
        dirLight.PositionType = float4(0, 0, 0, LIGHT_TYPE_DIRECTIONAL);
        dirLight.DirectionRange = g_DirectionalDir;
        dirLight.ColorIntensity = float4(g_DirectionalColor.rgb * g_DirectionalDir.w, g_DirectionalDir.w);
        dirLight.SpotShadowFlags = float4(0, 0, g_DirectionalColor.a, g_DirectionalShadowEnabled > 0 ? 1.0 : 0.0);

        totalLight += ComputeLightContributionWithShadow(dirLight, worldPos, N, V, albedo, metallic, roughness, F0, viewZ);
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

        totalLight += ComputeLightContributionWithShadow(light, worldPos, N, V, albedo, metallic, roughness, F0, viewZ);
    }

    return totalLight;
}

#endif // CLUSTERED_LIGHTING_HLSLI
