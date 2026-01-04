// Skinned Mesh Fragment Shader
// Simple lit shader with texture

cbuffer ObjectBuffer : register(b1)
{
    float4x4 model;
    float4 baseColor;
};

Texture2D albedoTexture : register(t0);
SamplerState albedoSampler : register(s0);

struct PSInput
{
    float4 position : SV_Position;
    float3 worldNormal : NORMAL;
    float2 texCoord : TEXCOORD0;
    float3 worldPos : TEXCOORD1;
};

float4 main(PSInput input) : SV_Target
{
    // Sample texture
    float4 texColor = albedoTexture.Sample(albedoSampler, input.texCoord);

    // Apply base color tint
    float4 albedo = texColor * baseColor;

    // Simple directional lighting
    float3 lightDir = normalize(float3(0.5, 1.0, 0.3));
    float3 normal = normalize(input.worldNormal);
    float NdotL = max(dot(normal, lightDir), 0.0);

    // Ambient + diffuse
    float3 ambient = albedo.rgb * 0.3;
    float3 diffuse = albedo.rgb * NdotL * 0.7;

    return float4(ambient + diffuse, albedo.a);
}
