// Forward PBR Fragment Shader
// DebugMode (F key) isolates rendering stages:
//   0 = Full rendering (PBR + IBL + shadows) — default
//   1 = Flat albedo (no lighting)
//   2 = World normals
//   3 = View direction (V)
//   4 = NdotV heatmap
//   5 = Lambertian diffuse (first directional light only)
//   6 = Lambertian + flat ambient (all clustered lights)
//   7 = Full PBR direct (Cook-Torrance, no IBL)
//   8 = PBR + IBL ambient (no shadows)
#pragma pack_matrix(row_major)

// Constants
static const float PI = 3.14159265359;
static const float EPSILON = 0.0001;

#include "scene_uniforms.hlsli"

// Lighting uniforms
// Layout MUST match LightingUniforms struct in LightBuffer.bf
cbuffer LightingUniforms : register(b3)
{
    float3 AmbientColor;
    float AmbientIntensity;
    uint LightCount;
    uint ClusterDimensionX;
    uint ClusterDimensionY;
    uint ClusterDimensionZ;
    float2 ClusterScale;
    float2 ClusterBias;
    uint DebugMode; // 0-8 progressive stages
    uint _Pad0;
    uint _Pad1;
    uint _Pad2;
};

// Material uniforms (space1 = descriptor set 1 for materials)
// Layout MUST match MaterialBuilder.CreatePBR in MaterialBuilder.bf:
//   - BaseColor (float4) at offset 0
//   - Metallic (float) at offset 16
//   - Roughness (float) at offset 20
//   - AO (float) at offset 24
//   - AlphaCutoff (float) at offset 28
//   - EmissiveColor (float4) at offset 32
cbuffer MaterialUniforms : register(b0, space1)
{
    float4 BaseColor;
    float Metallic;
    float Roughness;
    float AO;
    float AlphaCutoff;
    float4 EmissiveColor;
};

#include "light.hlsli"

// Material textures (space1 = descriptor set 1 for materials)
// Order MUST match MaterialBuilder.CreatePBR texture order:
//   AlbedoMap, NormalMap, MetallicRoughnessMap, OcclusionMap, EmissiveMap
Texture2D AlbedoTexture : register(t0, space1);
Texture2D NormalTexture : register(t1, space1);
Texture2D MetallicRoughnessTexture : register(t2, space1);
Texture2D OcclusionTexture : register(t3, space1);
Texture2D EmissiveTexture : register(t4, space1);

// Clustered lighting buffers (read-only)
StructuredBuffer<Light> Lights : register(t4);
StructuredBuffer<uint2> ClusterLightInfo : register(t5); // offset, count
StructuredBuffer<uint> LightIndices : register(t6);

#ifdef RECEIVE_SHADOWS
Texture2DArray ShadowMap : register(t7);
SamplerComparisonState ShadowSampler : register(s1);

cbuffer ShadowUniforms : register(b5)
{
    float4x4 ShadowViewProjection[4];
    float4 CascadeSplits;
    uint CascadeCount;
    float ShadowBias;
    float ShadowNormalBias;
    uint _ShadowPad0;
    float2 ShadowMapSize;
    float2 _ShadowPad1;
    float4 ShadowLightDirection;   // xyz = normalized light direction
    float4 CascadeTexelSizes;     // world-space texel size per cascade
};
#endif

// IBL (Image-Based Lighting) resources
TextureCube IrradianceMap : register(t8);
TextureCube PrefilteredMap : register(t9);
Texture2D BRDFLutTexture : register(t10);
SamplerState IBLSampler : register(s2);

// Material sampler (space1 = descriptor set 1 for materials)
SamplerState LinearSampler : register(s0, space1);

struct FragmentInput
{
    float4 Position : SV_Position;
    float3 WorldPosition : TEXCOORD0;
    float3 WorldNormal : TEXCOORD1;
    float2 TexCoord : TEXCOORD2;
#ifdef NORMAL_MAP
    float3 WorldTangent : TEXCOORD3;
    float3 WorldBitangent : TEXCOORD4;
#endif
#ifdef RECEIVE_SHADOWS
    float4 ShadowCoord : TEXCOORD5;
#endif
};

// ===================== PBR Functions =====================

float DistributionGGX(float3 N, float3 H, float roughness)
{
    float a = roughness * roughness;
    float a2 = a * a;
    float NdotH = max(dot(N, H), 0.0);
    float NdotH2 = NdotH * NdotH;

    float num = a2;
    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    denom = PI * denom * denom;

    return num / max(denom, EPSILON);
}

float GeometrySchlickGGX(float NdotV, float roughness)
{
    float r = (roughness + 1.0);
    float k = (r * r) / 8.0;

    float num = NdotV;
    float denom = NdotV * (1.0 - k) + k;

    return num / max(denom, EPSILON);
}

float GeometrySmith(float3 N, float3 V, float3 L, float roughness)
{
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    float ggx2 = GeometrySchlickGGX(NdotV, roughness);
    float ggx1 = GeometrySchlickGGX(NdotL, roughness);

    return ggx1 * ggx2;
}

float3 FresnelSchlick(float cosTheta, float3 F0)
{
    return F0 + (1.0 - F0) * pow(saturate(1.0 - cosTheta), 5.0);
}

float3 FresnelSchlickRoughness(float cosTheta, float3 F0, float roughness)
{
    float3 maxF0 = max(float3(1.0 - roughness, 1.0 - roughness, 1.0 - roughness), F0);
    return F0 + (maxF0 - F0) * pow(saturate(1.0 - cosTheta), 5.0);
}

// ===================== Utility Functions =====================

uint GetClusterIndex(float2 screenPos, float viewZ)
{
    uint clusterX = uint(screenPos.x * ClusterScale.x);
    uint clusterY = uint(screenPos.y * ClusterScale.y);
    uint clusterZ = uint(max(0.0, log(viewZ) * ClusterBias.x + ClusterBias.y));

    clusterX = min(clusterX, ClusterDimensionX - 1);
    clusterY = min(clusterY, ClusterDimensionY - 1);
    clusterZ = min(clusterZ, ClusterDimensionZ - 1);

    return clusterX + clusterY * ClusterDimensionX + clusterZ * ClusterDimensionX * ClusterDimensionY;
}

// Light attenuation
float GetAttenuation(Light light, float3 worldPos)
{
    float3 lightVec = light.Position - worldPos;
    float distance = length(lightVec);
    float attenuation = saturate(1.0 - (distance / light.Range));
    return attenuation * attenuation;
}

// Spot light falloff
float GetSpotFalloff(Light light, float3 L)
{
    float cosAngle = dot(-L, light.Direction);
    float cosOuter = light.SpotAngleCos;
    // Assume inner cone is 80% of outer cone angle
    float cosInner = lerp(1.0, cosOuter, 0.8);
    return saturate((cosAngle - cosOuter) / max(cosInner - cosOuter, EPSILON));
}

#ifdef RECEIVE_SHADOWS
float SampleShadowMap(float3 worldPos, float3 N)
{
    // Find cascade based on view-space depth
    // Note: Use positive depth (cascade splits are positive distances)
    float viewZ = abs(mul(float4(worldPos, 1.0), ViewMatrix).z);

    // Default to last cascade if beyond all splits
    uint cascadeIndex = CascadeCount - 1;
    for (uint i = 0; i < CascadeCount; i++)
    {
        if (viewZ < CascadeSplits[i])
        {
            cascadeIndex = i;
            break;
        }
    }

    float3 lightDir = ShadowLightDirection.xyz;
    float NdotL = saturate(dot(N, -lightDir));
    float texelSize = CascadeTexelSizes[cascadeIndex];
    float3 offsetPos = worldPos + N * (ShadowNormalBias * texelSize * (1.0 - NdotL));

    float4 shadowCoord = mul(float4(offsetPos, 1.0), ShadowViewProjection[cascadeIndex]);
    shadowCoord.xyz /= shadowCoord.w;

    // Convert from NDC [-1,1] to texture UV [0,1]
    shadowCoord.xy = shadowCoord.xy * 0.5 + 0.5;

    // Clamp depth to valid range (matches old renderer)
    shadowCoord.z = saturate(shadowCoord.z);

    // DX12/WebGPU have Y-up NDC, need to flip Y for shadow UV
    // Vulkan has Y-down NDC, no flip needed
#if !defined(VULKAN)
    shadowCoord.y = 1.0 - shadowCoord.y;
#endif

    // Early out if outside shadow map bounds
    if (any(shadowCoord.xy < 0.0) || any(shadowCoord.xy > 1.0))
        return 1.0;

    shadowCoord.z -= ShadowBias;

    float shadow = 0.0;
    float2 texelSizeUV = 1.0 / ShadowMapSize;
    for (int x = -2; x <= 2; x++)
    {
        for (int y = -2; y <= 2; y++)
        {
            float2 offset = float2(x, y) * texelSizeUV;
            float3 sampleCoord = float3(shadowCoord.xy + offset, (float)cascadeIndex);
            shadow += ShadowMap.SampleCmpLevelZero(ShadowSampler, sampleCoord, shadowCoord.z);
        }
    }
    return shadow / 25.0;
}
#endif

// ===================== Lighting Helpers =====================

// Resolves light direction and attenuation for any light type.
void ResolveLightVector(Light light, float3 worldPos, out float3 L, out float attenuation)
{
    if (light.Type == 0) // Directional
    {
        L = -light.Direction;
        attenuation = 1.0;
    }
    else
    {
        float3 lightVec = light.Position - worldPos;
        L = normalize(lightVec);
        attenuation = GetAttenuation(light, worldPos);
        if (light.Type == 2) // Spot
            attenuation *= GetSpotFalloff(light, L);
    }
}

// ===================== Main =====================

float4 main(FragmentInput input) : SV_Target
{
    // ===== Material sampling =====
    float4 albedo = AlbedoTexture.Sample(LinearSampler, input.TexCoord) * BaseColor;

#ifdef ALPHA_TEST
    if (albedo.a < AlphaCutoff)
        discard;
#endif

    // ----- Debug 1: Flat albedo (no lighting) -----
    if (DebugMode == 1)
        return float4(albedo.rgb, albedo.a);

    // ===== Normal =====
    float3 N = normalize(input.WorldNormal);
#ifdef NORMAL_MAP
    float3 normalSample = NormalTexture.Sample(LinearSampler, input.TexCoord).rgb * 2.0 - 1.0;
    float3x3 TBN = float3x3(
        normalize(input.WorldTangent),
        normalize(input.WorldBitangent),
        N
    );
    N = normalize(mul(normalSample, TBN));
#endif

    // ----- Debug 2: World normals -----
    if (DebugMode == 2)
        return float4(N * 0.5 + 0.5, 1.0);

    // ===== View direction =====
    float3 V = normalize(CameraPosition - input.WorldPosition);
    float NdotV = max(dot(N, V), 0.0);

    // ----- Debug 3: View direction (V) -----
    if (DebugMode == 3)
        return float4(V * 0.5 + 0.5, 1.0);

    // ----- Debug 4: raw NdotV heatmap (green=positive, red=negative) -----
    if (DebugMode == 4)
    {
        float rawNdotV = dot(N, V);
        if (rawNdotV < -0.3) return float4(1.0, 0.0, 0.0, 1.0);
        if (rawNdotV < -0.1) return float4(0.7, 0.0, 0.0, 1.0);
        if (rawNdotV < 0.0)  return float4(0.4, 0.0, 0.0, 1.0);
        if (rawNdotV < 0.1)  return float4(0.0, 0.4, 0.0, 1.0);
        if (rawNdotV < 0.3)  return float4(0.0, 0.7, 0.0, 1.0);
        return float4(0.0, 1.0, 0.0, 1.0);
    }

    // ----- Debug 5: Lambertian diffuse (first directional light only) -----
    if (DebugMode == 5)
    {
        for (uint i = 0; i < LightCount; i++)
        {
            if (Lights[i].Type == 0)
            {
                float3 L = -Lights[i].Direction;
                float NdotL = max(dot(N, L), 0.0);
                return float4(albedo.rgb / PI * Lights[i].Color * Lights[i].Intensity * NdotL, 1.0);
            }
        }
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    // ===== Cluster lookup (needed for stages 4+) =====
    float viewZ = abs(mul(float4(input.WorldPosition, 1.0), ViewMatrix).z);
    uint clusterIndex = GetClusterIndex(input.Position.xy, viewZ);
    uint2 lightInfo = ClusterLightInfo[clusterIndex];
    uint lightOffset = lightInfo.x;
    uint lightCount = lightInfo.y;

    // ----- Debug 6: Lambertian + flat ambient (all clustered lights) -----
    if (DebugMode == 6)
    {
        float3 ambient = AmbientColor * AmbientIntensity * albedo.rgb;
        float3 Lo = float3(0.0, 0.0, 0.0);
        for (uint i = 0; i < lightCount; i++)
        {
            Light light = Lights[LightIndices[lightOffset + i]];
            float3 L; float attenuation;
            ResolveLightVector(light, input.WorldPosition, L, attenuation);
            float NdotL = max(dot(N, L), 0.0);
            Lo += albedo.rgb / PI * light.Color * light.Intensity * attenuation * NdotL;
        }
        return float4(ambient + Lo, 1.0);
    }

    // ===== PBR material properties (needed for stages 5+) =====
    float4 metallicRoughness = MetallicRoughnessTexture.Sample(LinearSampler, input.TexCoord);
    float metallic = metallicRoughness.b * Metallic;
    float roughness = metallicRoughness.g * Roughness;
    float ao = OcclusionTexture.Sample(LinearSampler, input.TexCoord).r * AO;
    float3 emissive = EmissiveTexture.Sample(LinearSampler, input.TexCoord).rgb * EmissiveColor.rgb;
    float3 F0 = lerp(float3(0.04, 0.04, 0.04), albedo.rgb, metallic);

    // ----- Debug 7: PBR direct lighting (Cook-Torrance, flat ambient, no IBL) -----
    if (DebugMode == 7)
    {
        float3 ambient = AmbientColor * AmbientIntensity * albedo.rgb * ao;
        float3 Lo = float3(0.0, 0.0, 0.0);
        for (uint i = 0; i < lightCount; i++)
        {
            Light light = Lights[LightIndices[lightOffset + i]];
            float3 L; float attenuation;
            ResolveLightVector(light, input.WorldPosition, L, attenuation);
            float3 H = normalize(V + L);
            float3 radiance = light.Color * light.Intensity * attenuation;
            float NdotL = max(dot(N, L), 0.0);

            float NDF = DistributionGGX(N, H, roughness);
            float G = GeometrySmith(N, V, L, roughness);
            float3 F = FresnelSchlick(max(dot(H, V), 0.0), F0);
            float3 specular = (NDF * G * F) / (4.0 * NdotV * NdotL + EPSILON);
            float3 kD = (1.0 - F) * (1.0 - metallic);

            Lo += (kD * albedo.rgb / PI + specular) * radiance * NdotL;
        }
        return float4(ambient + Lo + emissive, albedo.a);
    }

    // ----- Debug 8: PBR + IBL (no shadows) -----
    if (DebugMode == 8)
    {
        // IBL ambient
        float3 F_ibl = FresnelSchlickRoughness(NdotV, F0, roughness);
        float3 kD_ibl = (1.0 - F_ibl) * (1.0 - metallic);
        float3 diffuseIBL = IrradianceMap.Sample(IBLSampler, N).rgb * albedo.rgb;
        float3 R7 = reflect(-V, N);
        float3 prefilteredColor = PrefilteredMap.SampleLevel(IBLSampler, R7, roughness * 4.0).rgb;
        float2 envBRDF = BRDFLutTexture.Sample(IBLSampler, float2(NdotV, roughness)).rg;
        float3 specularIBL = prefilteredColor * (F0 * envBRDF.x + envBRDF.y);
        float3 ambient = (kD_ibl * diffuseIBL + specularIBL) * AmbientIntensity * ao;

        // Direct lighting
        float3 Lo = float3(0.0, 0.0, 0.0);
        for (uint i = 0; i < lightCount; i++)
        {
            Light light = Lights[LightIndices[lightOffset + i]];
            float3 L; float attenuation;
            ResolveLightVector(light, input.WorldPosition, L, attenuation);
            float3 H = normalize(V + L);
            float3 radiance = light.Color * light.Intensity * attenuation;
            float NdotL = max(dot(N, L), 0.0);

            float NDF = DistributionGGX(N, H, roughness);
            float G = GeometrySmith(N, V, L, roughness);
            float3 F = FresnelSchlick(max(dot(H, V), 0.0), F0);
            float3 specular = (NDF * G * F) / (4.0 * NdotV * NdotL + EPSILON);
            float3 kD = (1.0 - F) * (1.0 - metallic);

            Lo += (kD * albedo.rgb / PI + specular) * radiance * NdotL;
        }
        return float4(ambient + Lo + emissive, albedo.a);
    }

    // ----- Default (mode 0): Full rendering (PBR + IBL + shadows) -----
    {
        // IBL ambient
        float3 F_ibl = FresnelSchlickRoughness(NdotV, F0, roughness);
        float3 kD_ibl = (1.0 - F_ibl) * (1.0 - metallic);
        float3 diffuseIBL = IrradianceMap.Sample(IBLSampler, N).rgb * albedo.rgb;
        float3 R8 = reflect(-V, N);
        float3 prefilteredColor = PrefilteredMap.SampleLevel(IBLSampler, R8, roughness * 4.0).rgb;
        float2 envBRDF = BRDFLutTexture.Sample(IBLSampler, float2(NdotV, roughness)).rg;
        float3 specularIBL = prefilteredColor * (F0 * envBRDF.x + envBRDF.y);
        float3 ambient = (kD_ibl * diffuseIBL + specularIBL) * AmbientIntensity * ao;

        // Direct lighting with shadow separation
        float3 shadowLit = float3(0.0, 0.0, 0.0);
        float3 unshadowedLit = float3(0.0, 0.0, 0.0);
        for (uint i = 0; i < lightCount; i++)
        {
            Light light = Lights[LightIndices[lightOffset + i]];
            float3 L; float attenuation;
            ResolveLightVector(light, input.WorldPosition, L, attenuation);
            float3 H = normalize(V + L);
            float3 radiance = light.Color * light.Intensity * attenuation;
            float NdotL = max(dot(N, L), 0.0);

            float NDF = DistributionGGX(N, H, roughness);
            float G = GeometrySmith(N, V, L, roughness);
            float3 F = FresnelSchlick(max(dot(H, V), 0.0), F0);
            float3 specular = (NDF * G * F) / (4.0 * NdotV * NdotL + EPSILON);
            float3 kD = (1.0 - F) * (1.0 - metallic);
            float3 lightContrib = (kD * albedo.rgb / PI + specular) * radiance * NdotL;

            if (light.ShadowIndex >= 0)
                shadowLit += lightContrib;
            else
                unshadowedLit += lightContrib;
        }

        float3 Lo;
#ifdef RECEIVE_SHADOWS
        float shadow = SampleShadowMap(input.WorldPosition, N);
        Lo = shadowLit * shadow + unshadowedLit;
#else
        Lo = shadowLit + unshadowedLit;
#endif

        return float4(ambient + Lo + emissive, albedo.a);
    }
}
