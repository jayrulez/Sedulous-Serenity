// Simple PBR Vertex Shader

struct VSInput
{
    float3 position : POSITION;
    float3 normal : NORMAL;
    float2 uv : TEXCOORD0;
};

struct VSOutput
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

// Object uniform buffer (binding 2)
cbuffer ObjectUniforms : register(b2)
{
    float4x4 model;
    float4x4 normalMatrix;
};

VSOutput main(VSInput input)
{
    VSOutput output;

    float4 worldPos = mul(model, float4(input.position, 1.0));
    output.position = mul(viewProjection, worldPos);
    output.worldPos = worldPos.xyz;
    output.worldNormal = mul((float3x3)normalMatrix, input.normal);
    output.uv = input.uv;

    return output;
}
