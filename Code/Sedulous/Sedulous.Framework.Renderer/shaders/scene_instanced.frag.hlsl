// Scene instanced fragment shader
// Simple directional lighting with instance color

#pragma pack_matrix(row_major)

struct PSInput
{
    float4 position : SV_Position;
    float3 worldPos : TEXCOORD0;
    float3 worldNormal : TEXCOORD1;
    float2 uv : TEXCOORD2;
    float4 color : COLOR;
};

cbuffer CameraUniforms : register(b0)
{
    float4x4 viewProjection;
    float3 cameraPosition;
    float _pad0;
};

float4 main(PSInput input) : SV_Target
{
    // Simple directional lighting
    float3 lightDir = normalize(float3(-0.5, -1.0, -0.3));
    float3 normal = normalize(input.worldNormal);

    // Diffuse
    float ndotl = max(dot(normal, -lightDir), 0.0);
    float diffuse = ndotl * 0.7 + 0.3; // Add ambient

    // View direction for specular
    float3 viewDir = normalize(cameraPosition - input.worldPos);
    float3 halfDir = normalize(viewDir - lightDir);
    float specular = pow(max(dot(normal, halfDir), 0.0), 32.0) * 0.3;

    float3 finalColor = input.color.rgb * diffuse + float3(1, 1, 1) * specular;

    return float4(finalColor, 1.0);
}
