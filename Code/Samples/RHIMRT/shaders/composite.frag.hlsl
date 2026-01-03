// Composite pass - combines G-buffer textures with simple lighting

Texture2D albedoTex : register(t0);
Texture2D normalTex : register(t1);
Texture2D positionTex : register(t2);
SamplerState samp : register(s0);

cbuffer LightParams : register(b0)
{
    float3 lightDir;
    float padding1;
    float3 lightColor;
    float padding2;
    float3 ambientColor;
    float displayMode;  // 0=lit, 1=albedo, 2=normals, 3=position
};

struct PSInput
{
    float4 position : SV_Position;
    float2 texCoord : TEXCOORD0;
};

float4 main(PSInput input) : SV_Target
{
    float3 albedo = albedoTex.Sample(samp, input.texCoord).rgb;
    float3 normal = normalTex.Sample(samp, input.texCoord).rgb * 2.0 - 1.0;  // Unpack
    float3 worldPos = positionTex.Sample(samp, input.texCoord).rgb;

    int mode = (int)displayMode;

    if (mode == 1)
        return float4(albedo, 1.0);  // Show albedo only
    else if (mode == 2)
        return float4(normal * 0.5 + 0.5, 1.0);  // Show normals
    else if (mode == 3)
        return float4(frac(worldPos), 1.0);  // Show position (fractional for visibility)

    // Default: simple diffuse lighting
    float NdotL = max(dot(normal, -lightDir), 0.0);
    float3 diffuse = albedo * lightColor * NdotL;
    float3 ambient = albedo * ambientColor;
    float3 finalColor = ambient + diffuse;

    return float4(finalColor, 1.0);
}
