// Forward PBR Fragment Shader
// Physically-based rendering with clustered lighting
#pragma pack_matrix(row_major)

// Constants
static const float PI = 3.14159265359;
static const float EPSILON = 0.0001;

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

// Lighting uniforms
cbuffer LightingUniforms : register(b3)
{
    float3 AmbientColor;
    float AmbientIntensity;
    uint LightCount;
    uint3 ClusterDimensions;
    float2 ClusterScale;
    float2 ClusterBias;
};

// Material uniforms
cbuffer MaterialUniforms : register(b4)
{
    float4 BaseColor;
    float4 EmissiveColor;
    float Metallic;
    float Roughness;
    float AO;
    float AlphaCutoff;
};

// Light structure
struct Light
{
    float3 Position;
    float Range;
    float3 Color;
    float Intensity;
    float3 Direction;
    uint Type; // 0 = point, 1 = spot, 2 = directional
    float SpotAngle;
    float SpotInnerAngle;
    float2 _Padding;
};

// Textures
Texture2D AlbedoTexture : register(t0);
Texture2D NormalTexture : register(t1);
Texture2D MetallicRoughnessTexture : register(t2);
Texture2D EmissiveTexture : register(t3);

// Clustered lighting buffers
StructuredBuffer<Light> Lights : register(t4);
StructuredBuffer<uint2> ClusterLightInfo : register(t5); // offset, count
StructuredBuffer<uint> LightIndices : register(t6);

#ifdef RECEIVE_SHADOWS
Texture2D ShadowMap : register(t7);
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

SamplerState LinearSampler : register(s0);

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

// PBR Functions
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

// Cluster index calculation
uint GetClusterIndex(float2 screenPos, float viewZ)
{
    uint clusterX = uint(screenPos.x * ClusterScale.x);
    uint clusterY = uint(screenPos.y * ClusterScale.y);
    uint clusterZ = uint(log(viewZ) * ClusterScale.x + ClusterBias.x);

    clusterX = min(clusterX, ClusterDimensions.x - 1);
    clusterY = min(clusterY, ClusterDimensions.y - 1);
    clusterZ = min(clusterZ, ClusterDimensions.z - 1);

    return clusterX + clusterY * ClusterDimensions.x + clusterZ * ClusterDimensions.x * ClusterDimensions.y;
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
    float cosOuter = cos(light.SpotAngle);
    float cosInner = cos(light.SpotInnerAngle);
    return saturate((cosAngle - cosOuter) / max(cosInner - cosOuter, EPSILON));
}

#ifdef RECEIVE_SHADOWS
float SampleShadowMap(float3 worldPos, float3 N)
{
    // Find cascade
    float viewZ = mul(float4(worldPos, 1.0), ViewMatrix).z;
    uint cascadeIndex = 0;
    for (uint i = 0; i < CascadeCount; i++)
    {
        if (viewZ < CascadeSplits[i])
        {
            cascadeIndex = i;
            break;
        }
    }

    // Transform to shadow space
    float4 shadowCoord = mul(float4(worldPos, 1.0), ShadowViewProjection[cascadeIndex]);
    shadowCoord.xyz /= shadowCoord.w;
    shadowCoord.xy = shadowCoord.xy * 0.5 + 0.5;
    shadowCoord.y = 1.0 - shadowCoord.y;

    // PCF sampling
    float shadow = 0.0;
    float2 texelSize = 1.0 / ShadowMapSize;
    for (int x = -1; x <= 1; x++)
    {
        for (int y = -1; y <= 1; y++)
        {
            float2 offset = float2(x, y) * texelSize;
            shadow += ShadowMap.SampleCmpLevelZero(ShadowSampler, shadowCoord.xy + offset, shadowCoord.z - ShadowBias);
        }
    }
    return shadow / 9.0;
}
#endif

float4 main(FragmentInput input) : SV_Target
{
    // Sample textures
    float4 albedo = AlbedoTexture.Sample(LinearSampler, input.TexCoord) * BaseColor;

#ifdef ALPHA_TEST
    if (albedo.a < AlphaCutoff)
        discard;
#endif

    float4 metallicRoughness = MetallicRoughnessTexture.Sample(LinearSampler, input.TexCoord);
    float metallic = metallicRoughness.b * Metallic;
    float roughness = metallicRoughness.g * Roughness;
    float ao = metallicRoughness.r * AO;

    float3 emissive = EmissiveTexture.Sample(LinearSampler, input.TexCoord).rgb * EmissiveColor.rgb;

    // Get normal
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

    float3 V = normalize(CameraPosition - input.WorldPosition);
    float3 F0 = lerp(float3(0.04, 0.04, 0.04), albedo.rgb, metallic);

    // Ambient lighting
    float3 ambient = AmbientColor * AmbientIntensity * albedo.rgb * ao;
    float3 Lo = float3(0.0, 0.0, 0.0);

    // Get cluster index
    float viewZ = mul(float4(input.WorldPosition, 1.0), ViewMatrix).z;
    uint clusterIndex = GetClusterIndex(input.Position.xy, viewZ);
    uint2 lightInfo = ClusterLightInfo[clusterIndex];
    uint lightOffset = lightInfo.x;
    uint lightCount = lightInfo.y;

    // Process lights in cluster
    for (uint i = 0; i < lightCount; i++)
    {
        uint lightIndex = LightIndices[lightOffset + i];
        Light light = Lights[lightIndex];

        float3 L;
        float attenuation;

        if (light.Type == 2) // Directional
        {
            L = -light.Direction;
            attenuation = 1.0;
        }
        else
        {
            float3 lightVec = light.Position - input.WorldPosition;
            L = normalize(lightVec);
            attenuation = GetAttenuation(light, input.WorldPosition);

            if (light.Type == 1) // Spot
            {
                attenuation *= GetSpotFalloff(light, L);
            }
        }

        float3 H = normalize(V + L);
        float3 radiance = light.Color * light.Intensity * attenuation;

        // Cook-Torrance BRDF
        float NDF = DistributionGGX(N, H, roughness);
        float G = GeometrySmith(N, V, L, roughness);
        float3 F = FresnelSchlick(max(dot(H, V), 0.0), F0);

        float3 numerator = NDF * G * F;
        float denominator = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + EPSILON;
        float3 specular = numerator / denominator;

        float3 kS = F;
        float3 kD = (1.0 - kS) * (1.0 - metallic);

        float NdotL = max(dot(N, L), 0.0);
        Lo += (kD * albedo.rgb / PI + specular) * radiance * NdotL;
    }

#ifdef RECEIVE_SHADOWS
    float shadow = SampleShadowMap(input.WorldPosition, N);
    Lo *= shadow;
#endif

    float3 color = ambient + Lo + emissive;

    return float4(color, albedo.a);
}
