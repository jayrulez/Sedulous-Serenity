// Water Fragment Shader
// Refraction, Fresnel reflection, depth absorption, specular highlights, foam
// Adapted from Lunex water shader for Serenity's forward+ PBR pipeline.
#pragma pack_matrix(row_major)

static const float PI = 3.14159265359;
static const float EPSILON = 0.0001;

#include "scene_uniforms.hlsli"
#include "gbuffer_utils.hlsli"
#include "light.hlsli"
#include "lighting_uniforms.hlsli"

// Water uniforms (space1)
cbuffer WaterUniforms : register(b0, space1)
{
    float3 WaterCenter;     float WaveSpeed;
    float4 WaterColor;
    float2 WaterSize;       float WaveScale;       float NormalStrength;
    float FresnelR0;        float RefractionStrength; float SpecularPower;  float MaxVisibleDepth;
    float FoamDepthThreshold; float FoamIntensity;  float Roughness;       float WaterPad0;
    float2 FlowDirection;   float2 WaterPad1;
};

// Water textures (space1)
Texture2D<float4> NormalMap      : register(t0, space1);  // Wave normal + height in alpha
Texture2D<float4> FoamTexture    : register(t1, space1);  // Foam (RGBA8 or R8)
Texture2D<float4> SceneColorCopy : register(t2, space1);  // HDR scene copy for refraction
Texture2D<float>  SceneDepthTex  : register(t3, space1);  // Scene depth buffer
SamplerState WaterSampler        : register(s0, space1);  // Linear wrap (normal, foam)
SamplerState SceneSampler        : register(s1, space1);  // Linear clamp (scene, depth)

#include "shadow_uniforms.hlsli"

// IBL resources (space0)
TextureCube IrradianceMap  : register(t8);
TextureCube PrefilteredMap : register(t9);
Texture2D BRDFLutTexture   : register(t10);
SamplerState IBLSampler    : register(s2);

#include "probe_uniforms.hlsli"

struct FragmentInput
{
    float4 Position : SV_Position;
    float3 WorldPosition : TEXCOORD0;
    float2 UV : TEXCOORD1;
};

// ===================== Wave Height =====================

float getHeight(float2 uv)
{
    float n0 = NormalMap.Sample(WaterSampler, uv).r;
    float n1 = NormalMap.Sample(WaterSampler, -uv.yx * 2.0 + 0.1).r;
    return (cos(n0 * 2.0 * PI + Time * 5.0)
          + sin(n1 * PI - Time * 3.0)) * 0.5 + 0.5;
}

// ===================== Surface Normal (finite differences) =====================

float3 getSurfaceNormal(float2 uv, out float h00)
{
    float2 d = float2(0.01, 0);
    uv *= WaveScale;
    uv += FlowDirection * Time * WaveSpeed;

    h00 = getHeight(uv - d.xy) * NormalStrength;
    float h10 = getHeight(uv + d.xy) * NormalStrength;
    float h01 = getHeight(uv - d.yx) * NormalStrength;
    float h11 = getHeight(uv + d.yx) * NormalStrength;

    float3 N;
    N.x = h00 - h10;
    N.z = h01 - h11;
    N.y = sqrt(saturate(1.0 - dot(N.xz, N.xz)));
    return normalize(N);
}

// ===================== Depth Helpers =====================

float linearizeDepth(float d)
{
    return NearPlane * FarPlane / (FarPlane - d * (FarPlane - NearPlane));
}

float2 worldToScreenUV(float3 worldPos)
{
    float4 clipPos = mul(float4(worldPos, 1.0), ViewProjectionMatrix);
    clipPos.xyz /= clipPos.w;
    float2 uv = clipPos.xy * 0.5 + 0.5;
    uv.y = 1.0 - uv.y;
    return uv;
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

    float3 V = normalize(CameraPosition - input.WorldPosition);

    // Animated surface normal
    float h;
    float3 waterNormal = getSurfaceNormal(input.UV, h);

    // Screen UV for this fragment
    float2 screenUV = input.Position.xy / ScreenSize;

    // Scene depth at this pixel
    float rawDepth = SceneDepthTex.Sample(SceneSampler, screenUV).r;
    float sceneLinearDepth = linearizeDepth(rawDepth);
    float waterLinearDepth = linearizeDepth(input.Position.z);
    float waterDepth = sceneLinearDepth - waterLinearDepth;

    // Discard fragments behind scene geometry (no depth attachment)
    if (waterDepth < 0.0)
        discard;

    waterDepth = max(waterDepth - saturate(h * 0.4), 0.0);

    // Soft edge factor
    float softEdge = saturate(waterDepth * 5.0);

    // ===================== Refraction =====================

    // Distort screen UV by surface normal
    float2 refractionUV = screenUV + waterNormal.xz * RefractionStrength * softEdge;
    // Clamp to avoid sampling outside screen
    refractionUV = clamp(refractionUV, 0.001, 0.999);

    float3 refractedColor = SceneColorCopy.Sample(SceneSampler, refractionUV).rgb;

    // Depth-based absorption
    float3 absorption = exp(-waterDepth / max(MaxVisibleDepth, 0.01) * (1.0 - float3(WaterColor.rgb)));
    refractedColor *= absorption;

    // Tint with water color based on depth
    float depthFactor = saturate(waterDepth / max(MaxVisibleDepth, 0.01));
    refractedColor = lerp(refractedColor, WaterColor.rgb * 0.5, depthFactor);

    // ===================== Reflection (IBL) =====================

    float NdotV = max(dot(waterNormal, V), 0.001);
    float3 R = reflect(-V, waterNormal);

    // IBL specular reflection
    float3 prefilteredColor = PrefilteredMap.SampleLevel(IBLSampler, R, Roughness * 4.0).rgb;

    // Check for reflection probes
    float4 probeResult = SampleReflectionProbe(input.WorldPosition, R, Roughness, IBLSampler);
    if (probeResult.w > 0.001)
    {
        float3 globalPrefiltered = prefilteredColor;
        prefilteredColor = lerp(globalPrefiltered, probeResult.rgb, probeResult.w);
    }

    float3 reflection = prefilteredColor;

    // ===================== Specular Highlights =====================

    // Direct lighting specular (Blinn-Phong for water surface)
    float viewZ = abs(mul(float4(input.WorldPosition, 1.0), ViewMatrix).z);
    uint clusterIndex = GetClusterIndex(input.Position.xy, viewZ);
    uint2 lightInfo = ClusterLightInfo[clusterIndex];
    uint lightOffset = lightInfo.x;
    uint lightCount = lightInfo.y;

    float3 specularLit = float3(0, 0, 0);
    float3 shadowLit = float3(0, 0, 0);
    float3 unshadowedLit = float3(0, 0, 0);

    for (uint i = 0; i < lightCount; i++)
    {
        Light light = Lights[LightIndices[lightOffset + i]];
        float3 L;
        float attenuation;
        ResolveLightVector(light, input.WorldPosition, L, attenuation);

        float3 H = normalize(V + L);
        float NdotL = max(dot(waterNormal, L), 0.0);
        float NdotH = max(dot(waterNormal, H), 0.0);

        // Blinn-Phong specular
        float spec = pow(NdotH, SpecularPower) * attenuation * NdotL;
        float3 lightContrib = light.Color * light.Intensity * spec;

        if (light.ShadowIndex >= 0)
            shadowLit += lightContrib;
        else
            unshadowedLit += lightContrib;
    }

#ifdef RECEIVE_SHADOWS
    float shadow = SampleShadowMap(input.WorldPosition, waterNormal);
    specularLit = shadowLit * shadow + unshadowedLit;
#else
    specularLit = shadowLit + unshadowedLit;
#endif

    reflection += specularLit;

    // ===================== Fresnel =====================

    float fresnel = FresnelR0 + (1.0 - FresnelR0) * pow(saturate(1.0 - NdotV), 5.0);
    float3 color = lerp(refractedColor, reflection, fresnel);

    // Blend with soft edge (near shore, more transparent)
    color = lerp(refractedColor, color, softEdge);

    // ===================== Foam =====================

    if (waterDepth < FoamDepthThreshold && waterDepth > 0.0)
    {
        float2 foamUV = input.UV * WaveScale * 2.0 + FlowDirection * Time * WaveSpeed * 0.5;
        float foam = FoamTexture.Sample(WaterSampler, foamUV).r;
        float foamMask = (1.0 - saturate(waterDepth / FoamDepthThreshold));
        foamMask *= foamMask; // Sharper falloff
        color = lerp(color, float3(1, 1, 1) * FoamIntensity, foam * foamMask);
    }

    // ===================== Output =====================

    output.Color = float4(color, 1.0);

    // GBuffer: pack view-space normal, roughness, 0 metallic
    float3 viewN = normalize(mul(waterNormal, (float3x3)ViewMatrix));
    output.GBuffer = PackGBuffer(viewN, Roughness, 0.0);

    return output;
}
