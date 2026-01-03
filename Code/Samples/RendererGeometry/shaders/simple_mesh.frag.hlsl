// Simple Mesh Fragment Shader
// Basic lit rendering with a directional light

struct PSInput
{
    float4 position : SV_Position;
    float3 worldPos : TEXCOORD0;
    float3 worldNormal : TEXCOORD1;
    float2 uv : TEXCOORD2;
};

cbuffer CameraUniforms : register(b0)
{
    float4x4 viewProjection;
    float4x4 view;
    float4x4 projection;
    float3 cameraPosition;
    float _pad0;
};

cbuffer ObjectUniforms : register(b1)
{
    float4x4 model;
    float4 objectColor;
};

float4 main(PSInput input) : SV_Target
{
    // Light direction (from top-right-front)
    float3 lightDir = normalize(float3(1.0, 1.0, 0.5));
    float3 lightColor = float3(1.0, 1.0, 1.0);

    // Normal and view direction
    float3 N = normalize(input.worldNormal);
    float3 V = normalize(cameraPosition - input.worldPos);

    // Diffuse lighting
    float NdotL = max(dot(N, lightDir), 0.0);
    float3 diffuse = objectColor.rgb * lightColor * NdotL;

    // Simple specular
    float3 H = normalize(lightDir + V);
    float NdotH = max(dot(N, H), 0.0);
    float spec = pow(NdotH, 32.0) * 0.5;

    // Ambient
    float3 ambient = objectColor.rgb * 0.1;

    // Final color
    float3 color = ambient + diffuse + spec;

    // Gamma correction
    color = pow(color, 1.0 / 2.2);

    return float4(color, objectColor.a);
}
