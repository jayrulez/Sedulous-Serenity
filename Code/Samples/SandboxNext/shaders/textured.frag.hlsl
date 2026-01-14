// Textured fragment shader
// Simple diffuse lighting with texture

struct PSInput
{
    float4 position : SV_Position;
    float3 worldNormal : NORMAL;
    float2 uv : TEXCOORD0;
};

// Texture and sampler (binding 2)
Texture2D diffuseTexture : register(t0);
SamplerState diffuseSampler : register(s0);

// Simple directional light
static const float3 lightDir = normalize(float3(0.5, 1.0, 0.3));
static const float3 lightColor = float3(1.0, 1.0, 1.0);
static const float3 ambientColor = float3(0.2, 0.2, 0.2);

float4 main(PSInput input) : SV_Target
{
    // Sample texture
    float4 texColor = diffuseTexture.Sample(diffuseSampler, input.uv);

    // Simple diffuse lighting
    float3 normal = normalize(input.worldNormal);
    float ndotl = max(dot(normal, lightDir), 0.0);
    float3 diffuse = lightColor * ndotl;

    // Combine ambient and diffuse
    float3 lighting = ambientColor + diffuse;

    float3 finalColor = texColor.rgb * lighting;
    return float4(finalColor, texColor.a);
}
