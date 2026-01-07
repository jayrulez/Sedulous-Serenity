// Skinned Toon/Cel-Shading Material Fragment Shader
// Quantized lighting with rim highlight effect for skeletal meshes
// Uses 3 bind groups: Scene (0), Object+Bones (1), Material (2)

#pragma pack_matrix(row_major)

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

// ==================== Bind Group 1: Object + Bones ====================
// (No fragment resources needed from this group)

// ==================== Bind Group 2: Material Resources ====================

// Material uniform buffer (binding 1)
cbuffer MaterialUniforms : register(b1, space2)
{
    float4 baseColor;       // offset 0: Base diffuse color
    float4 shadowColor;     // offset 16: Color in shadow areas
    float4 rimColor;        // offset 32: Rim/fresnel highlight color
    float bands;            // offset 48: Number of shading bands (2-5 typical)
    float rimPower;         // offset 52: Rim light falloff exponent
    float rimIntensity;     // offset 56: Rim light strength
    float shadowThreshold;  // offset 60: Threshold for shadow band
};

// Material textures
Texture2D albedoMap : register(t0, space2);

// Material sampler (binding s0)
SamplerState materialSampler : register(s0, space2);

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

// ==================== Toon Shading Functions ====================

// Quantize a value into discrete bands
float Quantize(float value, float numBands)
{
    return floor(value * numBands) / (numBands - 1.0);
}

// Compute toon-shaded diffuse with hard bands
float3 ComputeToonDiffuse(float NdotL, float shadow, float3 lightColor, float3 albedo)
{
    // Combine lighting with shadow
    float lighting = NdotL * shadow;

    // Quantize into bands
    float quantized = Quantize(saturate(lighting), bands);

    // Interpolate between shadow and lit color based on quantized value
    float3 diffuse = lerp(shadowColor.rgb, albedo, quantized);

    return diffuse * lightColor;
}

// Compute rim lighting (fresnel-like edge highlight)
float3 ComputeRimLight(float3 N, float3 V, float3 rimCol)
{
    float rim = 1.0 - saturate(dot(N, V));
    rim = pow(rim, rimPower);
    return rimCol * rim * rimIntensity;
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

// ==================== Main ====================

float4 main(PSInput input) : SV_Target
{
    // Sample albedo texture
    float4 albedoSample = albedoMap.Sample(materialSampler, input.uv);
    float3 albedo = albedoSample.rgb * baseColor.rgb * input.tint;
    float alpha = albedoSample.a * baseColor.a;

#ifdef ALPHA_TEST
    if (alpha < 0.5)
        discard;
#endif

    // Normalize vectors
    float3 N = normalize(input.worldNormal);
    float3 V = normalize(cameraPosition - input.worldPos);

    float3 finalColor = float3(0, 0, 0);

    // Directional light with shadow
    if (g_DirectionalDir.w > 0.0)
    {
        float3 L = normalize(-g_DirectionalDir.xyz);
        float NdotL = max(dot(N, L), 0.0);

        float shadow = SampleDirectionalShadow(input.worldPos, input.viewZ);
        float3 lightColor = g_DirectionalColor.rgb * g_DirectionalDir.w;

        finalColor += ComputeToonDiffuse(NdotL, shadow, lightColor, albedo);
    }

    // Process point/spot lights
    for (uint i = 0; i < g_LightCount; i++)
    {
        ClusteredLight light = g_Lights[i];
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
            float3 toLight = lightPos - input.worldPos;
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

        if (attenuation > 0.0)
        {
            float NdotL = max(dot(N, L), 0.0);
            finalColor += ComputeToonDiffuse(NdotL, 1.0, lightColor * attenuation, albedo);
        }
    }

    // Add rim lighting
    finalColor += ComputeRimLight(N, V, rimColor.rgb);

    // Add ambient (using shadow color as base ambient)
    finalColor += shadowColor.rgb * albedo * 0.1;

    return float4(finalColor, alpha);
}
