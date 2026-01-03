// Simple PBR Fragment Shader
// Simplified Cook-Torrance BRDF with single directional light

static const float PI = 3.14159265359;

struct PSInput
{
    float4 position : SV_Position;
    float3 worldPos : TEXCOORD0;
    float3 worldNormal : TEXCOORD1;
    float2 uv : TEXCOORD2;
};

// Camera uniform buffer (binding 0)
cbuffer CameraUniforms : register(b0)
{
    float4x4 viewProjection;
    float4x4 view;
    float4x4 projection;
    float3 cameraPosition;
    float _pad0;
};

// Material uniform buffer (binding 1)
cbuffer MaterialUniforms : register(b1)
{
    float4 baseColor;
    float metallic;
    float roughness;
    float ao;
    float _pad1;
    float4 emissive;
};

// Textures
Texture2D albedoMap : register(t0);

// Samplers
SamplerState materialSampler : register(s0);

// Light configuration
static const float3 lightDir = normalize(float3(1.0, 1.0, 0.5));
static const float3 lightColor = float3(1.0, 1.0, 1.0);
static const float lightIntensity = 3.0;
static const float3 ambientColor = float3(0.03, 0.03, 0.03);

// Normal Distribution Function (GGX/Trowbridge-Reitz)
float DistributionGGX(float3 N, float3 H, float roughness)
{
    float a = roughness * roughness;
    float a2 = a * a;
    float NdotH = max(dot(N, H), 0.0);
    float NdotH2 = NdotH * NdotH;

    float nom = a2;
    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    denom = PI * denom * denom;

    return nom / max(denom, 0.0001);
}

// Geometry Function (Schlick-GGX)
float GeometrySchlickGGX(float NdotV, float roughness)
{
    float r = (roughness + 1.0);
    float k = (r * r) / 8.0;

    float nom = NdotV;
    float denom = NdotV * (1.0 - k) + k;

    return nom / max(denom, 0.0001);
}

// Geometry Function (Smith)
float GeometrySmith(float3 N, float3 V, float3 L, float roughness)
{
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    float ggx2 = GeometrySchlickGGX(NdotV, roughness);
    float ggx1 = GeometrySchlickGGX(NdotL, roughness);

    return ggx1 * ggx2;
}

// Fresnel (Schlick approximation)
float3 FresnelSchlick(float cosTheta, float3 F0)
{
    return F0 + (1.0 - F0) * pow(saturate(1.0 - cosTheta), 5.0);
}

float4 main(PSInput input) : SV_Target
{
    // Sample albedo texture
    float4 albedo = albedoMap.Sample(materialSampler, input.uv) * baseColor;

    float roughness_ = max(roughness, 0.04); // Prevent divide by zero

    // Get normal
    float3 N = normalize(input.worldNormal);
    float3 V = normalize(cameraPosition - input.worldPos);
    float3 L = lightDir;
    float3 H = normalize(V + L);

    // Calculate reflectance at normal incidence (F0)
    float3 F0 = lerp(float3(0.04, 0.04, 0.04), albedo.rgb, metallic);

    // Cook-Torrance BRDF
    float NDF = DistributionGGX(N, H, roughness_);
    float G = GeometrySmith(N, V, L, roughness_);
    float3 F = FresnelSchlick(max(dot(H, V), 0.0), F0);

    float3 numerator = NDF * G * F;
    float denominator = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.0001;
    float3 specular = numerator / denominator;

    // Energy conservation
    float3 kS = F;
    float3 kD = (1.0 - kS) * (1.0 - metallic);

    // Final radiance
    float NdotL = max(dot(N, L), 0.0);
    float3 Lo = (kD * albedo.rgb / PI + specular) * lightColor * lightIntensity * NdotL;

    // Ambient
    float3 ambient = ambientColor * albedo.rgb * ao;

    // Final color
    float3 color = ambient + Lo + emissive.rgb;

    // Simple tone mapping and gamma correction
    color = color / (color + 1.0); // Reinhard tone mapping
    color = pow(color, 1.0 / 2.2); // Gamma correction

    return float4(color, albedo.a);
}
