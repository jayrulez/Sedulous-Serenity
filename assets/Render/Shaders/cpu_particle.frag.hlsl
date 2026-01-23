// CPU Particle Render Fragment Shader
// Textured particles with soft depth fade and optional cluster-based lighting
#pragma pack_matrix(row_major)

// Camera uniforms (needed for view-Z computation and billboard normal)
cbuffer CameraUniforms : register(b0)
{
    float4x4 ViewMatrix;
    float4x4 ProjectionMatrix;
    float4x4 ViewProjectionMatrix;
    float4x4 InvViewMatrix;
    float4x4 InvProjectionMatrix;
    float4x4 PrevViewProjectionMatrix;
    float3 CameraPosition;
    float Time;
    float3 CameraForward;
    float DeltaTime;
    float2 ScreenSize;
    float CameraNearPlane;
    float CameraFarPlane;
};

Texture2D ParticleTexture : register(t0);
Texture2D DepthTexture : register(t1);
SamplerState LinearSampler : register(s0);

cbuffer EmitterParams : register(b1)
{
    float SoftDistance;
    float NearPlane;
    float FarPlane;
    float RenderMode;
    float StretchFactor;
    float Lit;              // 0 = unlit, 1 = lit
    float2 _padding;
};

// Lighting uniforms (only used when Lit > 0)
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
};

struct Light
{
    float3 Position;
    float Range;
    float3 Direction;
    float SpotAngleCos;
    float3 Color;
    float Intensity;
    uint Type;
    int ShadowIndex;
    float2 _LightPad;
};

StructuredBuffer<Light> Lights : register(t4);
StructuredBuffer<uint2> ClusterLightInfo : register(t5);
StructuredBuffer<uint> LightIndices : register(t6);

struct FragmentInput
{
    float4 Position : SV_Position;
    float2 TexCoord : TEXCOORD0;
    float4 Color : TEXCOORD1;
    float3 WorldPosition : TEXCOORD2;
};

float LinearizeDepth(float depth, float near, float far)
{
    return near * far / (far - depth * (far - near));
}

float DistanceAttenuation(float distance, float range)
{
    float d = distance / range;
    float d2 = d * d;
    float d4 = d2 * d2;
    float falloff = saturate(1.0 - d4);
    return falloff * falloff / max(distance * distance, 0.0001);
}

float3 ComputeParticleLighting(float3 worldPos, float2 screenPos)
{
    // Billboard normal: face toward camera
    float3 normal = normalize(CameraPosition - worldPos);

    // Compute cluster index
    float viewZ = abs(mul(float4(worldPos, 1.0), ViewMatrix).z);
    uint clusterX = (uint)(screenPos.x / ScreenSize.x * ClusterDimensionX);
    uint clusterY = (uint)(screenPos.y / ScreenSize.y * ClusterDimensionY);
    uint clusterZ = (uint)(max(0.0, log(viewZ) * ClusterBias.x + ClusterBias.y));

    clusterX = min(clusterX, ClusterDimensionX - 1);
    clusterY = min(clusterY, ClusterDimensionY - 1);
    clusterZ = min(clusterZ, ClusterDimensionZ - 1);

    uint clusterIndex = clusterX + clusterY * ClusterDimensionX +
                        clusterZ * ClusterDimensionX * ClusterDimensionY;

    uint2 lightInfo = ClusterLightInfo[clusterIndex];
    uint lightOffset = lightInfo.x;
    uint lightCount = min(lightInfo.y, 32u); // Cap at 32 lights per particle

    // Start with ambient
    float3 lighting = AmbientColor * AmbientIntensity;

    for (uint i = 0; i < lightCount; i++)
    {
        uint lightIdx = LightIndices[lightOffset + i];
        Light light = Lights[lightIdx];

        float3 lightContribution = float3(0, 0, 0);

        if (light.Type == 0)
        {
            // Directional light
            float NdotL = max(dot(normal, -light.Direction), 0.0);
            lightContribution = light.Color * light.Intensity * NdotL;
        }
        else if (light.Type == 1)
        {
            // Point light
            float3 toLight = light.Position - worldPos;
            float dist = length(toLight);

            if (dist < light.Range)
            {
                float3 lightDir = toLight / dist;
                float NdotL = max(dot(normal, lightDir), 0.0);
                float atten = DistanceAttenuation(dist, light.Range);
                lightContribution = light.Color * light.Intensity * NdotL * atten;
            }
        }
        else if (light.Type == 2)
        {
            // Spot light
            float3 toLight = light.Position - worldPos;
            float dist = length(toLight);

            if (dist < light.Range)
            {
                float3 lightDir = toLight / dist;
                float spotCos = dot(-lightDir, light.Direction);

                if (spotCos > light.SpotAngleCos)
                {
                    float NdotL = max(dot(normal, lightDir), 0.0);
                    float atten = DistanceAttenuation(dist, light.Range);
                    // Smooth spot edge falloff
                    float spotFade = saturate((spotCos - light.SpotAngleCos) / (1.0 - light.SpotAngleCos));
                    lightContribution = light.Color * light.Intensity * NdotL * atten * spotFade;
                }
            }
        }

        lighting += lightContribution;
    }

    return lighting;
}

float4 main(FragmentInput input) : SV_Target
{
    // Sample particle texture
    float4 texColor = ParticleTexture.Sample(LinearSampler, input.TexCoord);

    // Multiply by particle color
    float4 finalColor = texColor * input.Color;

    // Apply lighting when enabled
    if (Lit > 0.5)
    {
        float3 lighting = ComputeParticleLighting(input.WorldPosition, input.Position.xy);
        finalColor.rgb *= lighting;
    }

    // Soft particle depth fade (when SoftDistance > 0)
    if (SoftDistance > 0.0)
    {
        float sceneDepth = DepthTexture.Load(int3(input.Position.xy, 0)).r;
        float linearScene = LinearizeDepth(sceneDepth, NearPlane, FarPlane);
        float linearFrag = LinearizeDepth(input.Position.z, NearPlane, FarPlane);
        float softFade = saturate((linearScene - linearFrag) / SoftDistance);
        finalColor.a *= softFade;
    }

    // Discard fully transparent pixels
    if (finalColor.a < 0.001)
        discard;

    // Premultiplied alpha output
    return float4(finalColor.rgb * finalColor.a, finalColor.a);
}
