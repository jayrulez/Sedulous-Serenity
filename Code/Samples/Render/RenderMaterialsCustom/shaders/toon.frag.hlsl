// Toon/Cel-Shading Fragment Shader
// Quantized lighting with rim highlight, using Sedulous.Render bind group layout
#pragma pack_matrix(row_major)

static const float EPSILON = 0.0001;

// ==================== Scene Bind Group (space0) ====================

#include "scene_uniforms.hlsli"
#include "light.hlsli"
#include "lighting_uniforms.hlsli"
#include "shadow_uniforms.hlsli"

// ==================== Material Bind Group (space1) ====================

// Toon material uniforms — layout matches MaterialBuilder property order
cbuffer MaterialUniforms : register(b0, space1)
{
    float4 BaseColor;        // offset 0
    float4 ShadowColor;     // offset 16
    float4 RimColor;        // offset 32
    float Bands;            // offset 48
    float RimPower;         // offset 52
    float RimIntensity;     // offset 56
    float ShadowThreshold;  // offset 60
};

Texture2D AlbedoTexture : register(t0, space1);
SamplerState LinearSampler : register(s0, space1);

// ==================== Fragment Input ====================

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
    float4 Color : COLOR0;
};

// ==================== Toon Shading Functions ====================

// Quantize a value into discrete bands
float Quantize(float value, float numBands)
{
    return floor(value * numBands) / max(numBands - 1.0, 1.0);
}

// Compute toon-shaded diffuse with hard bands
float3 ComputeToonDiffuse(float NdotL, float shadow, float3 lightColor, float3 albedo)
{
    float lighting = NdotL * shadow;
    float quantized = Quantize(saturate(lighting), Bands);
    float3 diffuse = lerp(ShadowColor.rgb, albedo, quantized);
    return diffuse * lightColor;
}

// Compute rim lighting (fresnel-like edge highlight)
float3 ComputeRimLight(float3 N, float3 V)
{
    float rim = 1.0 - saturate(dot(N, V));
    rim = pow(rim, RimPower);
    return RimColor.rgb * rim * RimIntensity;
}

// ==================== Cluster + Attenuation ====================

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

// ==================== Main ====================

float4 main(FragmentInput input) : SV_Target
{
    // Sample albedo texture
    float4 albedoSample = AlbedoTexture.Sample(LinearSampler, input.TexCoord);
    float3 albedo = albedoSample.rgb * BaseColor.rgb;
    float alpha = albedoSample.a * BaseColor.a;

#ifdef ALPHA_TEST
    if (alpha < 0.5)
        discard;
#endif

    float3 N = normalize(input.WorldNormal);
    float3 V = normalize(CameraPosition - input.WorldPosition);

    // Ambient base
    float3 finalColor = AmbientColor * AmbientIntensity * ShadowColor.rgb * albedo;

    // Get cluster for this fragment
    float viewZ = abs(mul(float4(input.WorldPosition, 1.0), ViewMatrix).z);
    uint clusterIndex = GetClusterIndex(input.Position.xy, viewZ);
    uint2 lightInfo = ClusterLightInfo[clusterIndex];
    uint lightOffset = lightInfo.x;
    uint lightCount = lightInfo.y;

    // Shadow factor for directional light
    float shadowFactor = 1.0;
#ifdef RECEIVE_SHADOWS
    shadowFactor = SampleShadowMap(input.WorldPosition, N);
#endif

    // Process lights in cluster
    for (uint i = 0; i < lightCount; i++)
    {
        uint lightIndex = LightIndices[lightOffset + i];
        Light light = Lights[lightIndex];

        float3 L;
        float attenuation;
        float shadow = 1.0;

        if (light.Type == 0) // Directional
        {
            L = -light.Direction;
            attenuation = 1.0;
            shadow = shadowFactor;
        }
        else
        {
            float3 lightVec = light.Position - input.WorldPosition;
            L = normalize(lightVec);
            attenuation = GetAttenuation(light, input.WorldPosition);

            if (light.Type == 2) // Spot
                attenuation *= GetSpotFalloff(light, L);
        }

        float NdotL = max(dot(N, L), 0.0);
        float3 lightColor = light.Color * light.Intensity * attenuation;
        finalColor += ComputeToonDiffuse(NdotL, shadow, lightColor, albedo);
    }

    // Add rim lighting
    finalColor += ComputeRimLight(N, V);

    return float4(finalColor, alpha);
}
