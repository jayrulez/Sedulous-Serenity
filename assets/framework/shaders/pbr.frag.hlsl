// PBR Material Fragment Shader
// Cook-Torrance BRDF with dynamic lighting and cascaded shadow mapping
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
    float3 tint : COLOR0;
    float viewZ : TEXCOORD3;
};

// ==================== Bind Group 0: Scene Resources ====================

// Camera uniform buffer (binding 0)
cbuffer CameraUniforms : register(b0, space0)
{
    float4x4 viewProjection;
    float4x4 view;
    float4x4 projection;
    float3 cameraPosition;
    float _pad0;
};

// Lighting uniform buffer (binding 2)
cbuffer LightingUniforms : register(b2, space0)
{
    float4x4 g_ViewMatrix;
    float4x4 g_InverseProjection;
    float4 g_ScreenParams;
    float4 g_ClusterParams;
    float4 g_DirectionalDir;
    float4 g_DirectionalColor;
    uint g_LightCount;
    uint g_DebugFlags;
    uint _lightPad1;
    uint _lightPad2;
};

// Light structure
struct ClusteredLight
{
    float4 PositionType;
    float4 DirectionRange;
    float4 ColorIntensity;
    float4 SpotShadowFlags;
};

// Light buffer (binding t0)
StructuredBuffer<ClusteredLight> g_Lights : register(t0, space0);

// Shadow constants
static const uint SHADOW_CASCADE_COUNT = 4;
static const uint SHADOW_MAX_TILES = 64;

struct CascadeData
{
    float4x4 ViewProjection;
    float4 SplitDepths;
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

// Shadow uniform buffer (binding 3)
cbuffer ShadowUniforms : register(b3, space0)
{
    CascadeData g_Cascades[SHADOW_CASCADE_COUNT];
    ShadowTileData g_ShadowTiles[SHADOW_MAX_TILES];
    uint g_ActiveTileCount;
    float g_AtlasTexelSize;
    float g_CascadeTexelSize;
    uint g_DirectionalShadowEnabled;
};

// Shadow textures and sampler (bindings t1, t2, s0)
Texture2DArray<float> g_CascadeShadowMap : register(t1, space0);
Texture2D<float> g_ShadowAtlas : register(t2, space0);
SamplerComparisonState g_ShadowSampler : register(s0, space0);

// ==================== Bind Group 1: Material Resources ====================

// Material uniform buffer (binding 1)
cbuffer MaterialUniforms : register(b1, space1)
{
    float4 baseColor;    // offset 0
    float metallic;      // offset 16
    float roughness;     // offset 20
    float ao;            // offset 24
    float _matPad1;      // offset 28
    float4 emissive;     // offset 32
};

// Material textures (bindings t0-t4)
Texture2D albedoMap : register(t0, space1);
Texture2D normalMap : register(t1, space1);
Texture2D metallicRoughnessMap : register(t2, space1);
Texture2D aoMap : register(t3, space1);
Texture2D emissiveMap : register(t4, space1);

// Material sampler (binding s0)
SamplerState materialSampler : register(s0, space1);

// ==================== PBR BRDF Functions ====================

// Normal Distribution Function (GGX/Trowbridge-Reitz)
float DistributionGGX(float3 N, float3 H, float rough)
{
    float a = rough * rough;
    float a2 = a * a;
    float NdotH = max(dot(N, H), 0.0);
    float NdotH2 = NdotH * NdotH;

    float nom = a2;
    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    denom = PI * denom * denom;

    return nom / max(denom, 0.0001);
}

// Geometry Function (Schlick-GGX)
float GeometrySchlickGGX(float NdotV, float rough)
{
    float r = (rough + 1.0);
    float k = (r * r) / 8.0;

    float nom = NdotV;
    float denom = NdotV * (1.0 - k) + k;

    return nom / max(denom, 0.0001);
}

// Geometry Function (Smith)
float GeometrySmith(float3 N, float3 V, float3 L, float rough)
{
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    float ggx2 = GeometrySchlickGGX(NdotV, rough);
    float ggx1 = GeometrySchlickGGX(NdotL, rough);

    return ggx1 * ggx2;
}

// Fresnel (Schlick approximation)
float3 FresnelSchlick(float cosTheta, float3 F0)
{
    return F0 + (1.0 - F0) * pow(saturate(1.0 - cosTheta), 5.0);
}

// ==================== Normal Mapping ====================

#ifdef NORMAL_MAP
float3 GetNormalFromMap(float3 worldNormal, float3 worldPos, float2 uv)
{
    float3 tangentNormal = normalMap.Sample(materialSampler, uv).xyz * 2.0 - 1.0;

    // Compute tangent frame from derivatives
    float3 Q1 = ddx(worldPos);
    float3 Q2 = ddy(worldPos);
    float2 st1 = ddx(uv);
    float2 st2 = ddy(uv);

    float3 N = normalize(worldNormal);
    float3 T = normalize(Q1 * st2.y - Q2 * st1.y);
    float3 B = -normalize(cross(N, T));
    float3x3 TBN = float3x3(T, B, N);

    return normalize(mul(tangentNormal, TBN));
}
#endif

// ==================== Shadow Functions ====================

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

// ==================== Light Attenuation ====================

float ComputeDistanceAttenuation(float distance, float range)
{
    if (distance >= range)
        return 0.0;

    float distNorm = distance / range;
    float attenuation = saturate(1.0 - distNorm * distNorm);
    return attenuation * attenuation;
}

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

// ==================== PBR Light Contribution ====================

float3 ComputePBRLightContribution(
    ClusteredLight light,
    float3 worldPos,
    float3 N,
    float3 V,
    float3 albedo,
    float rough,
    float metal,
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

    // Cook-Torrance BRDF
    float NDF = DistributionGGX(N, H, rough);
    float G = GeometrySmith(N, V, L, rough);
    float3 F = FresnelSchlick(max(dot(H, V), 0.0), F0);

    float3 numerator = NDF * G * F;
    float denominator = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.0001;
    float3 specular = numerator / denominator;

    // Energy conservation
    float3 kS = F;
    float3 kD = (1.0 - kS) * (1.0 - metal);

    // Final radiance for this light
    float NdotL = max(dot(N, L), 0.0);
    return (kD * albedo / PI + specular) * lightColor * attenuation * NdotL;
}

// ==================== Main ====================

float4 main(PSInput input) : SV_Target
{
    // Sample textures
    float4 albedoSample = albedoMap.Sample(materialSampler, input.uv);
    float4 albedo = albedoSample * baseColor * float4(input.tint, 1.0);

#ifdef ALPHA_TEST
    if (albedo.a < 0.5)
        discard;
#endif

    // Sample metallic-roughness (glTF convention: G=roughness, B=metallic)
    float2 metallicRoughnessSample = metallicRoughnessMap.Sample(materialSampler, input.uv).bg;
    float metal = metallicRoughnessSample.x * metallic;
    float rough = metallicRoughnessSample.y * roughness;
    rough = max(rough, 0.04); // Prevent divide by zero

    // Sample AO
    float aoSample = aoMap.Sample(materialSampler, input.uv).r * ao;

    // Sample emissive
    float3 emissiveSample = emissiveMap.Sample(materialSampler, input.uv).rgb * emissive.rgb;

    // Get normal
#ifdef NORMAL_MAP
    float3 N = GetNormalFromMap(input.worldNormal, input.worldPos, input.uv);
#else
    float3 N = normalize(input.worldNormal);
#endif

    float3 V = normalize(cameraPosition - input.worldPos);

    // Calculate reflectance at normal incidence (F0)
    float3 F0 = lerp(float3(0.04, 0.04, 0.04), albedo.rgb, metal);

    float3 Lo = float3(0, 0, 0);

    // Directional light with shadow
    if (g_DirectionalDir.w > 0.0)
    {
        ClusteredLight dirLight;
        dirLight.PositionType = float4(0, 0, 0, LIGHT_TYPE_DIRECTIONAL);
        dirLight.DirectionRange = g_DirectionalDir;
        dirLight.ColorIntensity = float4(g_DirectionalColor.rgb * g_DirectionalDir.w, g_DirectionalDir.w);
        dirLight.SpotShadowFlags = float4(0, 0, -1, 0);

        float3 dirContribution = ComputePBRLightContribution(
            dirLight, input.worldPos, N, V, albedo.rgb, rough, metal, F0);

        float shadow = SampleDirectionalShadow(input.worldPos, input.viewZ);
        Lo += dirContribution * shadow;
    }

    // Process all point/spot lights
    for (uint i = 0; i < g_LightCount; i++)
    {
        ClusteredLight light = g_Lights[i];
        Lo += ComputePBRLightContribution(
            light, input.worldPos, N, V, albedo.rgb, rough, metal, F0);
    }

    // Ambient
    float3 ambient = float3(0.03, 0.03, 0.03) * albedo.rgb * aoSample;

    // Final color
    float3 color = ambient + Lo + emissiveSample;

    // Reinhard tone mapping
    color = color / (color + 1.0);

    return float4(color, albedo.a);
}
