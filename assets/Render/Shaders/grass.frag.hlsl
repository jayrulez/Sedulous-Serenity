// Grass Fragment Shader
// Alpha-test + forward+ PBR lighting (same pipeline as terrain)
#pragma pack_matrix(row_major)

static const float PI = 3.14159265359;
static const float EPSILON = 0.0001;

#include "scene_uniforms.hlsli"
#include "gbuffer_utils.hlsli"

#include "light.hlsli"
#include "lighting_uniforms.hlsli"

cbuffer GrassUniforms : register(b0, space1)
{
    float3 GrassColor;
    float AlphaCutoff;
    float WindStrength;
    float WindFrequency;
    float2 WindDirection;
    float Roughness;
    float BladeWidth;
    float BladeHeight;
    float FadeStart;
    float FadeEnd;
    float3 _Pad;
};

Texture2D GrassAlbedo : register(t0, space1);
SamplerState GrassSampler : register(s0, space1);

#include "shadow_uniforms.hlsli"

// IBL resources
TextureCube IrradianceMap : register(t8);
TextureCube PrefilteredMap : register(t9);
Texture2D BRDFLutTexture : register(t10);
SamplerState IBLSampler : register(s2);

#include "probe_uniforms.hlsli"

struct FragmentInput
{
    float4 Position      : SV_Position;
    float3 WorldPosition : TEXCOORD0;
    float2 UV            : TEXCOORD1;
    float  FadeAlpha     : TEXCOORD2;
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
    return GeometrySchlickGGX(NdotV, roughness) * GeometrySchlickGGX(NdotL, roughness);
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

// ===================== Lighting Helpers =====================

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

float GetAttenuation(Light light, float3 worldPos)
{
    float3 lightVec = light.Position - worldPos;
    float distance = length(lightVec);
    float attenuation = saturate(1.0 - (distance / light.Range));
    return attenuation * attenuation;
}

float GetSpotFalloff(Light light, float3 L)
{
    float cosAngle = dot(-L, light.Direction);
    float cosOuter = light.SpotAngleCos;
    float cosInner = lerp(1.0, cosOuter, 0.8);
    return saturate((cosAngle - cosOuter) / max(cosInner - cosOuter, EPSILON));
}

void ResolveLightVector(Light light, float3 worldPos, out float3 L, out float attenuation)
{
    if (light.Type == 0)
    {
        L = -light.Direction;
        attenuation = 1.0;
    }
    else
    {
        float3 lightVec = light.Position - worldPos;
        L = normalize(lightVec);
        attenuation = GetAttenuation(light, worldPos);
        if (light.Type == 2)
            attenuation *= GetSpotFalloff(light, L);
    }
}

// ===================== MRT Output =====================

struct PSOutput
{
    float4 Color : SV_Target0;
    float4 GBuffer : SV_Target1;
};

PSOutput main(FragmentInput input)
{
    PSOutput output;

    // Sample albedo with alpha
    float4 texColor = GrassAlbedo.Sample(GrassSampler, input.UV);

    // Alpha test with distance fade
    float alpha = texColor.a * input.FadeAlpha;
    if (alpha < AlphaCutoff)
        discard;

    float3 albedo = texColor.rgb * GrassColor;

    // Grass normal: mostly up with slight variation
    float3 N = float3(0.0, 1.0, 0.0);

    // View direction
    float3 V = normalize(CameraPosition - input.WorldPosition);
    float NdotV = max(dot(N, V), 0.0);

    // PBR material (grass is non-metallic)
    float roughness = Roughness;
    float metallic = 0.0;
    float ao = 1.0;
    float3 F0 = float3(0.04, 0.04, 0.04);

    // GBuffer output
    float3 viewN = normalize(mul(N, (float3x3)ViewMatrix));
    output.GBuffer = PackGBuffer(viewN, roughness, metallic);

    // Cluster lookup
    float viewZ = abs(mul(float4(input.WorldPosition, 1.0), ViewMatrix).z);
    uint clusterIndex = GetClusterIndex(input.Position.xy, viewZ);
    uint2 lightInfo = ClusterLightInfo[clusterIndex];
    uint lightOffset = lightInfo.x;
    uint lightCount = lightInfo.y;

    // IBL ambient
    float3 F_ibl = FresnelSchlickRoughness(NdotV, F0, roughness);
    float3 kD_ibl = (1.0 - F_ibl) * (1.0 - metallic);

    // Probe-aware diffuse irradiance
    float4 probeDiffuse = SampleProbeDiffuse(input.WorldPosition, N);
    float3 diffuseIBL;
    if (probeDiffuse.w > 0.001)
    {
        float3 globalDiffuse = IrradianceMap.Sample(IBLSampler, N).rgb;
        diffuseIBL = lerp(globalDiffuse, probeDiffuse.rgb, probeDiffuse.w) * albedo;
    }
    else
    {
        diffuseIBL = IrradianceMap.Sample(IBLSampler, N).rgb * albedo;
    }

    float3 R = reflect(-V, N);

    // Probe-aware specular
    float4 probeResult = SampleReflectionProbe(input.WorldPosition, R, roughness, IBLSampler);
    float3 prefilteredColor;
    if (probeResult.w > 0.001)
    {
        float3 globalPrefiltered = PrefilteredMap.SampleLevel(IBLSampler, R, roughness * 4.0).rgb;
        prefilteredColor = lerp(globalPrefiltered, probeResult.rgb, probeResult.w);
    }
    else
    {
        prefilteredColor = PrefilteredMap.SampleLevel(IBLSampler, R, roughness * 4.0).rgb;
    }

    float2 envBRDF = BRDFLutTexture.Sample(IBLSampler, float2(NdotV, roughness)).rg;
    float3 specularIBL = prefilteredColor * (F0 * envBRDF.x + envBRDF.y);
    float3 ambient = (kD_ibl * diffuseIBL + specularIBL + AmbientColor * albedo) * AmbientIntensity * ao;

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
        float3 lightContrib = (kD * albedo / PI + specular) * radiance * NdotL;

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

    output.Color = float4(ambient + Lo, 1.0);
    return output;
}
