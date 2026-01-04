// Lighting Sample - Fragment Shader
// Demonstrates clustered forward lighting with multiple dynamic lights
// Uses row-major matrices with row-vector math: mul(vector, matrix)

#pragma pack_matrix(row_major)

static const float PI = 3.14159265359;

// Light types
static const uint LIGHT_TYPE_DIRECTIONAL = 0;
static const uint LIGHT_TYPE_POINT = 1;
static const uint LIGHT_TYPE_SPOT = 2;

struct PSInput
{
    float4 position : SV_Position;
    float3 worldPos : TEXCOORD0;
    float3 worldNormal : TEXCOORD1;
    float2 uv : TEXCOORD2;
    float2 material : TEXCOORD3;  // x=metallic, y=roughness (from instance data)
    float viewZ : TEXCOORD4;      // View-space Z for shadow cascade selection
};

// Camera uniform buffer
cbuffer CameraUniforms : register(b0)
{
    float4x4 viewProjection;
    float4x4 view;
    float4x4 projection;
    float3 cameraPosition;
    float _pad0;
};

// Lighting uniform buffer
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
    uint _pad1;
    uint _pad2;
};

// Light structure
struct ClusteredLight
{
    float4 PositionType;    // xyz=position, w=type
    float4 DirectionRange;  // xyz=direction, w=range
    float4 ColorIntensity;  // rgb=color*intensity, a=intensity
    float4 SpotShadowFlags; // x=cos(innerAngle), y=cos(outerAngle), z=shadowIndex, w=flags
};

// Light buffer
StructuredBuffer<ClusteredLight> g_Lights : register(t0);

// ==================== Shadow Resources ====================

// Shadow constants
static const uint SHADOW_CASCADE_COUNT = 4;
static const uint SHADOW_MAX_TILES = 64;

// Shadow cascade data
struct CascadeData
{
    float4x4 ViewProjection;
    float4 SplitDepths;  // x=near, y=far
};

// Shadow tile data
struct ShadowTileData
{
    float4x4 ViewProjection;
    float4 UVOffsetScale;
    int LightIndex;
    int FaceIndex;
    int _pad0;
    int _pad1;
};

// Shadow uniform buffer
cbuffer ShadowUniforms : register(b3)
{
    CascadeData g_Cascades[SHADOW_CASCADE_COUNT];
    ShadowTileData g_ShadowTiles[SHADOW_MAX_TILES];
    uint g_ActiveTileCount;
    float g_AtlasTexelSize;
    float g_CascadeTexelSize;
    uint g_DirectionalShadowEnabled;
};

// Shadow textures and sampler
Texture2DArray<float> g_CascadeShadowMap : register(t1);
Texture2D<float> g_ShadowAtlas : register(t2);
SamplerComparisonState g_ShadowSampler : register(s0);

// PCF shadow sampling for cascades
float SampleCascadeShadowPCF(float2 shadowUV, float shadowDepth, int cascadeIndex)
{
    // Use PCF for soft shadow edges
    #define USE_SINGLE_SAMPLE 0

    #if USE_SINGLE_SAMPLE
    return g_CascadeShadowMap.SampleCmpLevelZero(
        g_ShadowSampler,
        float3(shadowUV, cascadeIndex),
        shadowDepth
    );
    #else
    float shadow = 0.0;
    float texelSize = g_CascadeTexelSize;

    [unroll]
    for (int y = -1; y <= 1; y++)
    {
        [unroll]
        for (int x = -1; x <= 1; x++)
        {
            float2 offset = float2(x, y) * texelSize;
            shadow += g_CascadeShadowMap.SampleCmpLevelZero(
                g_ShadowSampler,
                float3(shadowUV + offset, cascadeIndex),
                shadowDepth
            );
        }
    }

    return shadow / 9.0;
    #endif
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

    return SHADOW_CASCADE_COUNT - 1;
}

// Sample directional light shadow
float SampleDirectionalShadow(float3 worldPos, float viewZ)
{
    // DEBUG: Disable shadow sampling entirely to test if artifact is shadow-related
    #define DISABLE_SHADOWS_FOR_TEST 0

    #if DISABLE_SHADOWS_FOR_TEST
    return 1.0;  // Always lit
    #endif

    if (g_DirectionalShadowEnabled == 0)
        return 1.0;

    int cascadeIndex = SelectCascade(viewZ);

    // Row-vector transform: pos * matrix
    float4 shadowPos = mul(float4(worldPos, 1.0), g_Cascades[cascadeIndex].ViewProjection);
    shadowPos.xyz /= shadowPos.w;

    // NDC to UV: [-1,1] -> [0,1]
    // Note: No Y flip needed - Vulkan NDC and texture coordinates both have Y increasing downward
    float2 shadowUV = shadowPos.xy * 0.5 + 0.5;

    if (any(shadowUV < 0.0) || any(shadowUV > 1.0))
        return 1.0;

    // No shader-side bias - rely on hardware depth bias only
    float shadowDepth = saturate(shadowPos.z);

    return SampleCascadeShadowPCF(shadowUV, shadowDepth, cascadeIndex);
}

// Distance attenuation for point/spot lights
float ComputeDistanceAttenuation(float distance, float range)
{
    if (distance >= range)
        return 0.0;

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

// GGX Distribution
float DistributionGGX(float3 N, float3 H, float rough)
{
    float a = rough * rough;
    float a2 = a * a;
    float NdotH = max(dot(N, H), 0.0);
    float NdotH2 = NdotH * NdotH;

    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    denom = PI * denom * denom;

    return a2 / max(denom, 0.0001);
}

// Schlick-GGX Geometry
float GeometrySchlickGGX(float NdotV, float rough)
{
    float r = (rough + 1.0);
    float k = (r * r) / 8.0;
    return NdotV / (NdotV * (1.0 - k) + k);
}

float GeometrySmith(float3 N, float3 V, float3 L, float rough)
{
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    return GeometrySchlickGGX(NdotV, rough) * GeometrySchlickGGX(NdotL, rough);
}

// Fresnel (Schlick)
float3 FresnelSchlick(float cosTheta, float3 F0)
{
    return F0 + (1.0 - F0) * pow(saturate(1.0 - cosTheta), 5.0);
}

// Compute lighting from a single light
float3 ComputeLightContribution(
    ClusteredLight light,
    float3 worldPos,
    float3 N,
    float3 V,
    float3 albedo,
    float metal,
    float rough,
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

    float3 H = normalize(V + L);
    float NdotL = max(dot(N, L), 0.0);
    float NdotV = max(dot(N, V), 0.0);
    float HdotV = max(dot(H, V), 0.0);

    // Cook-Torrance BRDF
    float D = DistributionGGX(N, H, rough);
    float G = GeometrySmith(N, V, L, rough);
    float3 F = FresnelSchlick(HdotV, F0);

    float3 numerator = D * G * F;
    float denominator = 4.0 * NdotV * NdotL + 0.0001;
    float3 specular = numerator / denominator;

    float3 kS = F;
    float3 kD = (1.0 - kS) * (1.0 - metal);

    return (kD * albedo / PI + specular) * lightColor * attenuation * NdotL;
}

// Debug: set to 1 to visualize cascade index, 2 to visualize shadow value,
//        3 to visualize shadow depth, 4 to visualize shadow UV, 0 for normal
#define SHADOW_DEBUG_MODE 0

float4 main(PSInput input) : SV_Target
{
    float3 N = normalize(input.worldNormal);
    float3 V = normalize(cameraPosition - input.worldPos);

    // Use base white color for now - material data from instance
    float3 albedo = float3(0.8, 0.8, 0.8);
    float metal = input.material.x;
    float rough = max(input.material.y, 0.04);

    // Calculate F0
    float3 F0 = lerp(float3(0.04, 0.04, 0.04), albedo, metal);

    float3 totalLight = float3(0, 0, 0);

    // Add directional light with shadow
    float shadow = 1.0;
    int cascadeIndex = 0;
    if (g_DirectionalDir.w > 0.0)
    {
        ClusteredLight dirLight;
        dirLight.PositionType = float4(0, 0, 0, LIGHT_TYPE_DIRECTIONAL);
        dirLight.DirectionRange = g_DirectionalDir;
        dirLight.ColorIntensity = float4(g_DirectionalColor.rgb * g_DirectionalDir.w, g_DirectionalDir.w);
        dirLight.SpotShadowFlags = float4(0, 0, -1, 0);

        float3 dirContribution = ComputeLightContribution(dirLight, input.worldPos, N, V, albedo, metal, rough, F0);

        // Apply directional shadow
        cascadeIndex = SelectCascade(input.viewZ);
        shadow = SampleDirectionalShadow(input.worldPos, input.viewZ);
        totalLight += dirContribution * shadow;
    }

    // Process all point/spot lights
    for (uint i = 0; i < g_LightCount; i++)
    {
        ClusteredLight light = g_Lights[i];
        totalLight += ComputeLightContribution(light, input.worldPos, N, V, albedo, metal, rough, F0);
    }

    // Ambient
    float3 ambient = float3(0.03, 0.03, 0.03) * albedo;

    float3 color = ambient + totalLight;

    // Tone mapping and gamma correction
    color = color / (color + 1.0);
    color = pow(color, 1.0 / 2.2);

#if SHADOW_DEBUG_MODE == 1
    // Debug: visualize cascade index (red=0, green=1, blue=2, yellow=3)
    float3 cascadeColors[4] = {
        float3(1, 0, 0),   // Cascade 0: Red
        float3(0, 1, 0),   // Cascade 1: Green
        float3(0, 0, 1),   // Cascade 2: Blue
        float3(1, 1, 0)    // Cascade 3: Yellow
    };
    return float4(cascadeColors[cascadeIndex] * shadow, 1.0);
#elif SHADOW_DEBUG_MODE == 2
    // Debug: visualize raw shadow value as grayscale
    return float4(shadow, shadow, shadow, 1.0);
#elif SHADOW_DEBUG_MODE == 3
    // Debug: visualize shadow depth and UV validity
    // Compute shadow position for current cascade
    float4 shadowPos = mul(float4(input.worldPos, 1.0), g_Cascades[cascadeIndex].ViewProjection);
    shadowPos.xyz /= shadowPos.w;
    float2 shadowUV = shadowPos.xy * 0.5 + 0.5;
    float shadowDepth = shadowPos.z;

    // Check if depth is negative (would indicate projection issue)
    // Red = positive depth (0-1 range)
    // Green = negative depth indicator (bright green = depth is negative!)
    // Blue = depth > 1 indicator
    float posDepth = (shadowDepth >= 0.0 && shadowDepth <= 1.0) ? shadowDepth : 0.0;
    float negDepth = (shadowDepth < 0.0) ? 1.0 : 0.0;
    float overDepth = (shadowDepth > 1.0) ? 1.0 : 0.0;
    return float4(posDepth, negDepth, overDepth, 1.0);
#elif SHADOW_DEBUG_MODE == 4
    // Debug: visualize shadow UV as color
    // Red = U coordinate, Green = V coordinate
    // Should see smooth gradient across the scene if projection is correct
    float4 shadowPos = mul(float4(input.worldPos, 1.0), g_Cascades[cascadeIndex].ViewProjection);
    shadowPos.xyz /= shadowPos.w;
    float2 shadowUV = shadowPos.xy * 0.5 + 0.5;
    // Clamp to show out-of-bounds as blue
    float outOfBounds = (any(shadowUV < 0.0) || any(shadowUV > 1.0)) ? 1.0 : 0.0;
    return float4(saturate(shadowUV.x), saturate(shadowUV.y), outOfBounds, 1.0);
#else
    return float4(color, 1.0);
#endif
}
