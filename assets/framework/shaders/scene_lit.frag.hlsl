// Scene Lit Fragment Shader
// Dynamic lighting with cascaded shadow mapping
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
    float4 color : COLOR;
    float viewZ : TEXCOORD3;
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

static const uint SHADOW_CASCADE_COUNT = 4;
static const uint SHADOW_MAX_TILES = 64;

struct CascadeData
{
    float4x4 ViewProjection;
    float4 SplitDepths;  // x=near, y=far
};

struct ShadowTileData
{
    float4x4 ViewProjection;
    float4 UVOffsetScale;
    int LightIndex;
    int FaceIndex;
    int _pad0;
    int _pad1;
};

cbuffer ShadowUniforms : register(b3)
{
    CascadeData g_Cascades[SHADOW_CASCADE_COUNT];
    ShadowTileData g_ShadowTiles[SHADOW_MAX_TILES];
    uint g_ActiveTileCount;
    float g_AtlasTexelSize;
    float g_CascadeTexelSize;
    uint g_DirectionalShadowEnabled;
};

Texture2DArray<float> g_CascadeShadowMap : register(t1);
Texture2D<float> g_ShadowAtlas : register(t2);
SamplerComparisonState g_ShadowSampler : register(s0);

// PCF shadow sampling
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

float SampleDirectionalShadow(float3 worldPos, float viewZ)
{
    if (g_DirectionalShadowEnabled == 0)
        return 1.0;

    int cascadeIndex = SelectCascade(viewZ);

    float4 shadowPos = mul(float4(worldPos, 1.0), g_Cascades[cascadeIndex].ViewProjection);
    shadowPos.xyz /= shadowPos.w;

    float2 shadowUV = shadowPos.xy * 0.5 + 0.5;

    if (any(shadowUV < 0.0) || any(shadowUV > 1.0))
        return 1.0;

    float shadowDepth = saturate(shadowPos.z);

    return SampleCascadeShadowPCF(shadowUV, shadowDepth, cascadeIndex);
}

// Distance attenuation
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

// Compute lighting from a single light
float3 ComputeLightContribution(
    ClusteredLight light,
    float3 worldPos,
    float3 N,
    float3 V,
    float3 albedo)
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

    // Simple diffuse + specular
    float NdotL = max(dot(N, L), 0.0);
    float3 H = normalize(V + L);
    float NdotH = max(dot(N, H), 0.0);
    float specular = pow(NdotH, 32.0) * 0.3;

    return (albedo * NdotL + float3(1, 1, 1) * specular) * lightColor * attenuation;
}

float4 main(PSInput input) : SV_Target
{
    float3 N = normalize(input.worldNormal);
    float3 V = normalize(cameraPosition - input.worldPos);
    float3 albedo = input.color.rgb;

    float3 totalLight = float3(0, 0, 0);

    // Add directional light with shadow
    if (g_DirectionalDir.w > 0.0)
    {
        ClusteredLight dirLight;
        dirLight.PositionType = float4(0, 0, 0, LIGHT_TYPE_DIRECTIONAL);
        dirLight.DirectionRange = g_DirectionalDir;
        dirLight.ColorIntensity = float4(g_DirectionalColor.rgb * g_DirectionalDir.w, g_DirectionalDir.w);
        dirLight.SpotShadowFlags = float4(0, 0, -1, 0);

        float3 dirContribution = ComputeLightContribution(dirLight, input.worldPos, N, V, albedo);
        float shadow = SampleDirectionalShadow(input.worldPos, input.viewZ);
        totalLight += dirContribution * shadow;
    }

    // Process all point/spot lights
    for (uint i = 0; i < g_LightCount; i++)
    {
        ClusteredLight light = g_Lights[i];
        totalLight += ComputeLightContribution(light, input.worldPos, N, V, albedo);
    }

    // Ambient
    float3 ambient = float3(0.03, 0.03, 0.03) * albedo;
    float3 color = ambient + totalLight;

    // Simple tone mapping
    color = color / (color + 1.0);

    return float4(color, 1.0);
}
