// PBR Fragment Shader with Clustered Lighting
// Cook-Torrance BRDF with GGX distribution + dynamic lights
// Uses row-major matrices with row-vector math: mul(vector, matrix)

#pragma pack_matrix(row_major)

#include "clustered_lighting.hlsli"

struct PSInput
{
    float4 position : SV_Position;
    float3 worldPos : TEXCOORD0;
    float3 worldNormal : TEXCOORD1;
    float2 uv : TEXCOORD2;
    float4 clipPos : TEXCOORD3;  // For cluster lookup
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
Texture2D normalMap : register(t1);
Texture2D metallicRoughnessMap : register(t2);
Texture2D aoMap : register(t3);
Texture2D emissiveMap : register(t4);

// Samplers
SamplerState materialSampler : register(s0);

// Ambient lighting
static const float3 ambientColor = float3(0.03, 0.03, 0.03);

#ifdef NORMAL_MAP
// Get normal from normal map
float3 GetNormalFromMap(float3 worldNormal, float3 worldPos, float2 uv)
{
    float3 tangentNormal = normalMap.Sample(materialSampler, uv).xyz * 2.0 - 1.0;

    // Compute tangent frame from derivatives
    float3 Q1 = ddx(worldPos);
    float3 Q2 = ddy(worldPos);
    float2 st1 = ddx(uv);
    float2 st2 = ddy(uv);

    float3 N = normalize(worldNormal);
    float3 T = normalize(Q1 * st2.y - Q2 * st1.y);
    float3 B = -normalize(cross(N, T));
    float3x3 TBN = float3x3(T, B, N);

    return normalize(mul(tangentNormal, TBN));
}
#endif

float4 main(PSInput input) : SV_Target
{
    // Sample textures
    float4 albedo = albedoMap.Sample(materialSampler, input.uv) * baseColor;

#ifdef ALPHA_TEST
    if (albedo.a < 0.5)
        discard;
#endif

    float2 metallicRoughnessSample = metallicRoughnessMap.Sample(materialSampler, input.uv).bg;
    float metallic_ = metallicRoughnessSample.x * metallic;
    float roughness_ = metallicRoughnessSample.y * roughness;
    roughness_ = max(roughness_, 0.04); // Prevent divide by zero

    float ao_ = aoMap.Sample(materialSampler, input.uv).r * ao;
    float3 emissive_ = emissiveMap.Sample(materialSampler, input.uv).rgb * emissive.rgb;

    // Get normal
#ifdef NORMAL_MAP
    float3 N = GetNormalFromMap(input.worldNormal, input.worldPos, input.uv);
#else
    float3 N = normalize(input.worldNormal);
#endif

    float3 V = normalize(cameraPosition - input.worldPos);

    // Compute view-space Z for cluster lookup (row-vector: pos * matrix)
    float4 viewPos = mul(float4(input.worldPos, 1.0), view);
    float viewZ = -viewPos.z; // View space Z is negative, we want positive depth

    // Compute screen position for cluster lookup
    float2 screenPos = input.position.xy;

#ifdef USE_CLUSTERED_LIGHTING
    // Full clustered lighting path
    float3 Lo = ComputeClusteredLighting(
        screenPos,
        viewZ,
        input.worldPos,
        N,
        V,
        albedo.rgb,
        metallic_,
        roughness_
    );
#else
    // Simple fallback for samples without cluster grid
    float3 Lo = ComputeSimpleLighting(
        input.worldPos,
        N,
        V,
        albedo.rgb,
        metallic_,
        roughness_
    );
#endif

    // Ambient
    float3 ambient = ambientColor * albedo.rgb * ao_;

    // Final color
    float3 color = ambient + Lo + emissive_;

    // Simple tone mapping and gamma correction
    color = color / (color + 1.0); // Reinhard tone mapping
    color = pow(color, 1.0 / 2.2); // Gamma correction

    return float4(color, albedo.a);
}
