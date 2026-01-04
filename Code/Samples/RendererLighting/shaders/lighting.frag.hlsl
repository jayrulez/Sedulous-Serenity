// Lighting Sample - Fragment Shader
// Demonstrates clustered forward lighting with multiple dynamic lights

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
    column_major float4x4 viewProjection;
    column_major float4x4 view;
    column_major float4x4 projection;
    float3 cameraPosition;
    float _pad0;
};

// Lighting uniform buffer
cbuffer LightingUniforms : register(b2)
{
    column_major float4x4 g_ViewMatrix;
    column_major float4x4 g_InverseProjection;
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
    column_major float4x4 ViewProjection;
    float4 SplitDepths;  // x=near, y=far
};

// Shadow tile data
struct ShadowTileData
{
    column_major float4x4 ViewProjection;
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
    if (g_DirectionalShadowEnabled == 0)
        return 1.0;

    int cascadeIndex = SelectCascade(viewZ);

    float4 shadowPos = mul(g_Cascades[cascadeIndex].ViewProjection, float4(worldPos, 1.0));
    shadowPos.xyz /= shadowPos.w;

    float2 shadowUV = shadowPos.xy * 0.5 + 0.5;
    shadowUV.y = 1.0 - shadowUV.y;

    if (any(shadowUV < 0.0) || any(shadowUV > 1.0))
        return 1.0;

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
    if (g_DirectionalDir.w > 0.0)
    {
        ClusteredLight dirLight;
        dirLight.PositionType = float4(0, 0, 0, LIGHT_TYPE_DIRECTIONAL);
        dirLight.DirectionRange = g_DirectionalDir;
        dirLight.ColorIntensity = float4(g_DirectionalColor.rgb * g_DirectionalDir.w, g_DirectionalDir.w);
        dirLight.SpotShadowFlags = float4(0, 0, -1, 0);

        float3 dirContribution = ComputeLightContribution(dirLight, input.worldPos, N, V, albedo, metal, rough, F0);

        // Apply directional shadow
        float shadow = SampleDirectionalShadow(input.worldPos, input.viewZ);
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

    return float4(color, 1.0);
}
