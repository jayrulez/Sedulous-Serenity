// Toon/Cel-Shading Fragment Shader
// Quantized lighting with rim highlight, using Sedulous.Render bind group layout
#pragma pack_matrix(row_major)

static const float EPSILON = 0.0001;

// ==================== Scene Bind Group (space0) ====================

// Camera uniform buffer
cbuffer CameraUniforms : register(b0)
{
    float4x4 ViewMatrix;
    float4x4 ProjectionMatrix;
    float4x4 ViewProjectionMatrix;
    float4x4 InvViewMatrix;
    float4x4 InvProjectionMatrix;
    float3 CameraPosition;
    float NearPlane;
    float3 CameraForward;
    float FarPlane;
};

// Lighting uniforms — layout matches LightingUniforms in LightBuffer.bf
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
    uint DebugMode;
    uint _Pad0;
    uint _Pad1;
    uint _Pad2;
};

// Light structure — matches GPULight in LightBuffer.bf
struct Light
{
    float3 Position;
    float Range;
    float3 Direction;
    float SpotAngleCos;
    float3 Color;
    float Intensity;
    uint Type;             // 0 = Directional, 1 = Point, 2 = Spot
    int ShadowIndex;
    float2 _Padding;
};

// Clustered lighting buffers
StructuredBuffer<Light> Lights : register(t4);
StructuredBuffer<uint2> ClusterLightInfo : register(t5);
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
    float2 ShadowMapSize;
};
#endif

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
#ifdef RECEIVE_SHADOWS
    float4 ShadowCoord : TEXCOORD5;
#endif
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

// ==================== Shadow ====================

#ifdef RECEIVE_SHADOWS
float SampleShadowMap(float3 worldPos, float3 N)
{
    float viewZ = abs(mul(float4(worldPos, 1.0), ViewMatrix).z);

    uint cascadeIndex = CascadeCount - 1;
    for (uint i = 0; i < CascadeCount; i++)
    {
        if (viewZ < CascadeSplits[i])
        {
            cascadeIndex = i;
            break;
        }
    }

    float4 shadowCoord = mul(float4(worldPos, 1.0), ShadowViewProjection[cascadeIndex]);
    shadowCoord.xyz /= shadowCoord.w;
    shadowCoord.xy = shadowCoord.xy * 0.5 + 0.5;
    shadowCoord.z = saturate(shadowCoord.z);

#if !defined(VULKAN)
    shadowCoord.y = 1.0 - shadowCoord.y;
#endif

    if (any(shadowCoord.xy < 0.0) || any(shadowCoord.xy > 1.0))
        return 1.0;

    float shadow = 0.0;
    float2 texelSize = 1.0 / ShadowMapSize;
    for (int x = -1; x <= 1; x++)
    {
        for (int y = -1; y <= 1; y++)
        {
            float2 offset = float2(x, y) * texelSize;
            float3 sampleCoord = float3(shadowCoord.xy + offset, (float)cascadeIndex);
            shadow += ShadowMap.SampleCmpLevelZero(ShadowSampler, sampleCoord, shadowCoord.z);
        }
    }
    return shadow / 9.0;
}
#endif

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
