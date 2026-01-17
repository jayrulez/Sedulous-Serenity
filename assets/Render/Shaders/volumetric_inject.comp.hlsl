// Volumetric Fog - Light Injection Compute Shader
// Injects lighting and density into the froxel volume
#pragma pack_matrix(row_major)

// Light structure
struct Light
{
    float3 Position;
    float Range;
    float3 Color;
    float Intensity;
    float3 Direction;
    uint Type;
    float SpotAngle;
    float SpotInnerAngle;
    float2 _Padding;
};

cbuffer VolumetricParams : register(b0)
{
    float4x4 InvViewProjection;
    float3 CameraPosition;
    float NearPlane;
    float3 VolumeSize;
    float FarPlane;
    float3 FogColor;
    float FogDensity;
    float3 AmbientLight;
    float Anisotropy;
    float3 WindDirection;
    float NoiseScale;
    float NoiseStrength;
    float Time;
    uint LightCount;
    float _Padding;
};

cbuffer FroxelParams : register(b1)
{
    uint3 FroxelDimensions;
    uint _FroxelPadding;
    float2 FroxelScale;
    float2 FroxelBias;
};

// Buffers
StructuredBuffer<Light> Lights : register(t0);
Texture3D<float> NoiseTexture : register(t1);
RWTexture3D<float4> ScatteringVolume : register(u0); // RGB = inscattered light, A = extinction

SamplerState LinearSampler : register(s0);

// Convert froxel index to world position
float3 FroxelToWorld(uint3 froxel)
{
    float3 uv = (float3(froxel) + 0.5) / float3(FroxelDimensions);

    // NDC coordinates
    float2 ndc = uv.xy * 2.0 - 1.0;

    // Exponential depth distribution for better near-field precision
    float linearZ = pow(uv.z, 2.0);
    float viewZ = lerp(NearPlane, FarPlane, linearZ);

    // Reconstruct world position
    float4 clipPos = float4(ndc.x, ndc.y, 0.5, 1.0);
    float4 worldPos = mul(clipPos, InvViewProjection);
    worldPos /= worldPos.w;

    float3 viewDir = normalize(worldPos.xyz - CameraPosition);
    return CameraPosition + viewDir * viewZ;
}

// Henyey-Greenstein phase function
float HenyeyGreenstein(float cosTheta, float g)
{
    float g2 = g * g;
    return (1.0 - g2) / (4.0 * 3.14159265359 * pow(1.0 + g2 - 2.0 * g * cosTheta, 1.5));
}

// Sample density at world position
float SampleDensity(float3 worldPos)
{
    // Base density with height falloff
    float heightFalloff = exp(-max(worldPos.y - 0.0, 0.0) * 0.1);
    float density = FogDensity * heightFalloff;

    // Add noise
    float3 noiseCoord = worldPos * NoiseScale + WindDirection * Time;
    float noise = NoiseTexture.SampleLevel(LinearSampler, noiseCoord * 0.1, 0).r;
    density *= 1.0 + (noise * 2.0 - 1.0) * NoiseStrength;

    return max(density, 0.0);
}

// Calculate light contribution at a point
float3 CalculateLighting(float3 worldPos, float3 viewDir, float density)
{
    float3 lighting = AmbientLight * FogColor;

    for (uint i = 0; i < LightCount; i++)
    {
        Light light = Lights[i];

        float3 lightDir;
        float attenuation;

        if (light.Type == 2) // Directional
        {
            lightDir = -light.Direction;
            attenuation = 1.0;
        }
        else
        {
            float3 toLight = light.Position - worldPos;
            float distance = length(toLight);
            lightDir = toLight / distance;

            // Distance attenuation
            attenuation = saturate(1.0 - distance / light.Range);
            attenuation *= attenuation;

            if (light.Type == 1) // Spot
            {
                float cosAngle = dot(-lightDir, light.Direction);
                float cosOuter = cos(light.SpotAngle);
                float cosInner = cos(light.SpotInnerAngle);
                attenuation *= saturate((cosAngle - cosOuter) / max(cosInner - cosOuter, 0.001));
            }
        }

        // Phase function
        float cosTheta = dot(viewDir, lightDir);
        float phase = HenyeyGreenstein(cosTheta, Anisotropy);

        lighting += light.Color * light.Intensity * attenuation * phase * FogColor;
    }

    return lighting;
}

[numthreads(8, 8, 8)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    if (any(DTid >= FroxelDimensions))
        return;

    float3 worldPos = FroxelToWorld(DTid);
    float3 viewDir = normalize(worldPos - CameraPosition);

    // Sample density
    float density = SampleDensity(worldPos);

    // Calculate lighting
    float3 inscattering = CalculateLighting(worldPos, viewDir, density);

    // Store scattering and extinction
    float extinction = density;
    ScatteringVolume[DTid] = float4(inscattering * density, extinction);
}
