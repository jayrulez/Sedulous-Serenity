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
    uint DebugMode; // 0=normal, 1=cluster index, 2=light count, 3=diffuse only
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

// Light structure - MUST match GPULight in LightBuffer.bf
struct Light
{
    float3 Position;
    float Range;
    float3 Direction;
    float SpotAngleCos;    // cos(outer cone angle) for spot lights
    float3 Color;
    float Intensity;
    uint Type;             // 0 = Directional, 1 = Point, 2 = Spot
    int ShadowIndex;
    float2 _Padding;
};

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
    float2 ShadowMapSize;
};
#endif

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
// ClusterScale.xy = screen-to-cluster scale (ClustersX/Width, ClustersY/Height)
// ClusterBias.x = log depth scale (ClustersZ / log(far/near))
// ClusterBias.y = log depth bias (-ClustersZ * log(near) / log(far/near))
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

    // Transform to shadow space
    float4 shadowCoord = mul(float4(worldPos, 1.0), ShadowViewProjection[cascadeIndex]);
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

    // PCF sampling with cascade array index
    // Note: Shadow bias is applied via hardware depth bias during shadow map rendering,
    // so we compare against shadowCoord.z directly (no shader bias subtraction needed)
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
    float ao = OcclusionTexture.Sample(LinearSampler, input.TexCoord).r * AO;

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
    // Note: View-space Z is negative in front of camera (RH convention),
    // but cluster slicing uses positive depth values, so we negate/abs
    float viewZ = abs(mul(float4(input.WorldPosition, 1.0), ViewMatrix).z);
    uint clusterIndex = GetClusterIndex(input.Position.xy, viewZ);
    uint2 lightInfo = ClusterLightInfo[clusterIndex];
    uint lightOffset = lightInfo.x;
    uint lightCount = lightInfo.y;

    // Debug visualization modes
    if (DebugMode == 1)
    {
        // Cluster index as color (XYZ mapped to RGB)
        uint clusterX = uint(input.Position.x * ClusterScale.x);
        uint clusterY = uint(input.Position.y * ClusterScale.y);
        uint clusterZ = uint(max(0.0, log(viewZ) * ClusterBias.x + ClusterBias.y));
        float3 debugColor = float3(
            float(clusterX % ClusterDimensionX) / float(ClusterDimensionX),
            float(clusterY % ClusterDimensionY) / float(ClusterDimensionY),
            float(clusterZ % ClusterDimensionZ) / float(ClusterDimensionZ)
        );
        return float4(debugColor, 1.0);
    }
    else if (DebugMode == 2)
    {
        // Light count per cluster as heat map (black=0, blue=1, green=2-3, yellow=4-5, red=6+)
        float t = saturate(float(lightCount) / 8.0);
        float3 debugColor = float3(
            saturate(t * 3.0 - 1.0),
            saturate(t * 3.0) - saturate(t * 3.0 - 2.0),
            saturate(1.0 - t * 3.0)
        );
        return float4(debugColor, 1.0);
    }

    // Process lights in cluster
    for (uint i = 0; i < lightCount; i++)
    {
        uint lightIndex = LightIndices[lightOffset + i];
        Light light = Lights[lightIndex];

        float3 L;
        float attenuation;

        if (light.Type == 0) // Directional
        {
            L = -light.Direction;
            attenuation = 1.0;
        }
        else
        {
            float3 lightVec = light.Position - input.WorldPosition;
            L = normalize(lightVec);
            attenuation = GetAttenuation(light, input.WorldPosition);

            if (light.Type == 2) // Spot
            {
                attenuation *= GetSpotFalloff(light, L);
            }
        }

        float3 H = normalize(V + L);
        float3 radiance = light.Color * light.Intensity * attenuation;

        float NdotL = max(dot(N, L), 0.0);

        if (DebugMode == 3)
        {
            // Diffuse only (no specular) for debugging beam artifacts
            Lo += albedo.rgb / PI * radiance * NdotL;
        }
        else
        {
            // Cook-Torrance BRDF
            float NDF = DistributionGGX(N, H, roughness);
            float G = GeometrySmith(N, V, L, roughness);
            float3 F = FresnelSchlick(max(dot(H, V), 0.0), F0);

            float3 numerator = NDF * G * F;
            float denominator = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + EPSILON;
            float3 specular = numerator / denominator;

            float3 kS = F;
            float3 kD = (1.0 - kS) * (1.0 - metallic);

            Lo += (kD * albedo.rgb / PI + specular) * radiance * NdotL;
        }
    }

#ifdef RECEIVE_SHADOWS
    float shadow = SampleShadowMap(input.WorldPosition, N);
    Lo *= shadow;
#endif

    float3 color = ambient + Lo + emissive;

    return float4(color, albedo.a);
}
