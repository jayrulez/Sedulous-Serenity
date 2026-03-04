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
#include "gbuffer_utils.hlsli"

#include "light.hlsli"
#include "lighting_uniforms.hlsli"

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

// Material textures (space1 = descriptor set 1 for materials)
// Order MUST match MaterialBuilder.CreatePBR texture order:
//   AlbedoMap, NormalMap, MetallicRoughnessMap, OcclusionMap, EmissiveMap
Texture2D AlbedoTexture : register(t0, space1);
Texture2D NormalTexture : register(t1, space1);
Texture2D MetallicRoughnessTexture : register(t2, space1);
Texture2D OcclusionTexture : register(t3, space1);
Texture2D EmissiveTexture : register(t4, space1);

#include "shadow_uniforms.hlsli"

// IBL (Image-Based Lighting) resources
TextureCube IrradianceMap : register(t8);
TextureCube PrefilteredMap : register(t9);
Texture2D BRDFLutTexture : register(t10);
SamplerState IBLSampler : register(s2);

#include "probe_uniforms.hlsli"

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
    float4 Color : COLOR0;
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

// ===================== MRT Output =====================

struct PSOutput
{
    float4 Color : SV_Target0;
    float4 GBuffer : SV_Target1;  // Octahedral view-space normal (RG), roughness (B), metallic (A)
};

// Neutral GBuffer value: forward-facing normal, zero roughness/metallic
static const float4 NEUTRAL_GBUFFER = float4(0.5, 0.5, 0.0, 0.0);

// ===================== Main =====================

PSOutput main(FragmentInput input)
{
    PSOutput output;
    output.GBuffer = NEUTRAL_GBUFFER;
    // ===== Material sampling =====
    // Combine texture, material base color, and vertex color
    float4 albedo = AlbedoTexture.Sample(LinearSampler, input.TexCoord) * BaseColor * input.Color;

#ifdef ALPHA_TEST
    if (albedo.a < AlphaCutoff)
        discard;
#endif

    // ----- Debug 1: Flat albedo (no lighting) -----
    if (DebugMode == 1)
    {
        output.Color = float4(albedo.rgb, albedo.a);
        return output;
    }

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
    {
        // N is available — write GBuffer with normal (no roughness/metallic yet)
        float3 viewN = normalize(mul(N, (float3x3)ViewMatrix));
        output.GBuffer = PackGBuffer(viewN, 0.0, 0.0);
        output.Color = float4(N * 0.5 + 0.5, 1.0);
        return output;
    }

    // ===== View direction =====
    float3 V = normalize(CameraPosition - input.WorldPosition);
    float NdotV = max(dot(N, V), 0.0);

    // ----- Debug 3: View direction (V) -----
    if (DebugMode == 3)
    {
        float3 viewN = normalize(mul(N, (float3x3)ViewMatrix));
        output.GBuffer = PackGBuffer(viewN, 0.0, 0.0);
        output.Color = float4(V * 0.5 + 0.5, 1.0);
        return output;
    }

    // ----- Debug 4: raw NdotV heatmap (green=positive, red=negative) -----
    if (DebugMode == 4)
    {
        float3 viewN = normalize(mul(N, (float3x3)ViewMatrix));
        output.GBuffer = PackGBuffer(viewN, 0.0, 0.0);
        float rawNdotV = dot(N, V);
        if (rawNdotV < -0.3) output.Color = float4(1.0, 0.0, 0.0, 1.0);
        else if (rawNdotV < -0.1) output.Color = float4(0.7, 0.0, 0.0, 1.0);
        else if (rawNdotV < 0.0)  output.Color = float4(0.4, 0.0, 0.0, 1.0);
        else if (rawNdotV < 0.1)  output.Color = float4(0.0, 0.4, 0.0, 1.0);
        else if (rawNdotV < 0.3)  output.Color = float4(0.0, 0.7, 0.0, 1.0);
        else output.Color = float4(0.0, 1.0, 0.0, 1.0);
        return output;
    }

    // ----- Debug 5: Lambertian diffuse (first directional light only) -----
    if (DebugMode == 5)
    {
        float3 viewN = normalize(mul(N, (float3x3)ViewMatrix));
        output.GBuffer = PackGBuffer(viewN, 0.0, 0.0);
        for (uint i = 0; i < LightCount; i++)
        {
            if (Lights[i].Type == 0)
            {
                float3 L = -Lights[i].Direction;
                float NdotL = max(dot(N, L), 0.0);
                output.Color = float4(albedo.rgb / PI * Lights[i].Color * Lights[i].Intensity * NdotL, 1.0);
                return output;
            }
        }
        output.Color = float4(0.0, 0.0, 0.0, 1.0);
        return output;
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
        float3 viewN = normalize(mul(N, (float3x3)ViewMatrix));
        output.GBuffer = PackGBuffer(viewN, 0.0, 0.0);
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
        output.Color = float4(ambient + Lo, 1.0);
        return output;
    }

    // ===== PBR material properties (needed for stages 5+) =====
    float4 metallicRoughness = MetallicRoughnessTexture.Sample(LinearSampler, input.TexCoord);
    float metallic = metallicRoughness.b * Metallic;
    float roughness = metallicRoughness.g * Roughness;
    float ao = OcclusionTexture.Sample(LinearSampler, input.TexCoord).r * AO;
    float3 emissive = EmissiveTexture.Sample(LinearSampler, input.TexCoord).rgb * EmissiveColor.rgb;
    float3 F0 = lerp(float3(0.04, 0.04, 0.04), albedo.rgb, metallic);

    // Pack GBuffer with view-space normal, roughness, metallic
    float3 viewN = normalize(mul(N, (float3x3)ViewMatrix));
    output.GBuffer = PackGBuffer(viewN, roughness, metallic);

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
        output.Color = float4(ambient + Lo + emissive, albedo.a);
        return output;
    }

    // ----- Debug 8: PBR + IBL (no shadows) -----
    if (DebugMode == 8)
    {
        // IBL ambient
        float3 F_ibl = FresnelSchlickRoughness(NdotV, F0, roughness);
        float3 kD_ibl = (1.0 - F_ibl) * (1.0 - metallic);

        // Probe-aware diffuse irradiance
        float4 probeDiffuse7 = SampleProbeDiffuse(input.WorldPosition, N);
        float3 diffuseIBL;
        if (probeDiffuse7.w > 0.001)
        {
            float3 globalDiffuse = IrradianceMap.Sample(IBLSampler, N).rgb;
            diffuseIBL = lerp(globalDiffuse, probeDiffuse7.rgb, probeDiffuse7.w) * albedo.rgb;
        }
        else
        {
            diffuseIBL = IrradianceMap.Sample(IBLSampler, N).rgb * albedo.rgb;
        }

        float3 R7 = reflect(-V, N);

        // Try reflection probes first, fall back to global IBL
        float4 probeResult = SampleReflectionProbe(input.WorldPosition, R7, roughness, IBLSampler);
        float3 prefilteredColor;
        if (probeResult.w > 0.001)
        {
            float3 globalPrefiltered = PrefilteredMap.SampleLevel(IBLSampler, R7, roughness * 4.0).rgb;
            prefilteredColor = lerp(globalPrefiltered, probeResult.rgb, probeResult.w);
        }
        else
        {
            prefilteredColor = PrefilteredMap.SampleLevel(IBLSampler, R7, roughness * 4.0).rgb;
        }

        float2 envBRDF = BRDFLutTexture.Sample(IBLSampler, float2(NdotV, roughness)).rg;
        float3 specularIBL = prefilteredColor * (F0 * envBRDF.x + envBRDF.y);
        float3 ambient = (kD_ibl * diffuseIBL + specularIBL + AmbientColor * albedo.rgb) * AmbientIntensity * ao;

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
        output.Color = float4(ambient + Lo + emissive, albedo.a);
        return output;
    }

    // ----- Default (mode 0): Full rendering (PBR + IBL + shadows) -----
    {
        // IBL ambient
        float3 F_ibl = FresnelSchlickRoughness(NdotV, F0, roughness);
        float3 kD_ibl = (1.0 - F_ibl) * (1.0 - metallic);

        // Probe-aware diffuse irradiance
        float4 probeDiffuse8 = SampleProbeDiffuse(input.WorldPosition, N);
        float3 diffuseIBL;
        if (probeDiffuse8.w > 0.001)
        {
            float3 globalDiffuse = IrradianceMap.Sample(IBLSampler, N).rgb;
            diffuseIBL = lerp(globalDiffuse, probeDiffuse8.rgb, probeDiffuse8.w) * albedo.rgb;
        }
        else
        {
            diffuseIBL = IrradianceMap.Sample(IBLSampler, N).rgb * albedo.rgb;
        }

        float3 R8 = reflect(-V, N);

        // Try reflection probes first, fall back to global IBL
        float4 probeResult8 = SampleReflectionProbe(input.WorldPosition, R8, roughness, IBLSampler);
        float3 prefilteredColor;
        if (probeResult8.w > 0.001)
        {
            float3 globalPrefiltered = PrefilteredMap.SampleLevel(IBLSampler, R8, roughness * 4.0).rgb;
            prefilteredColor = lerp(globalPrefiltered, probeResult8.rgb, probeResult8.w);
        }
        else
        {
            prefilteredColor = PrefilteredMap.SampleLevel(IBLSampler, R8, roughness * 4.0).rgb;
        }

        float2 envBRDF = BRDFLutTexture.Sample(IBLSampler, float2(NdotV, roughness)).rg;
        float3 specularIBL = prefilteredColor * (F0 * envBRDF.x + envBRDF.y);
        float3 ambient = (kD_ibl * diffuseIBL + specularIBL + AmbientColor * albedo.rgb) * AmbientIntensity * ao;

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

        output.Color = float4(ambient + Lo + emissive, albedo.a);
        return output;
    }
}
