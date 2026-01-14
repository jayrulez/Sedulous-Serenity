// Textured vertex shader
// Supports position + normal + UV vertex format

struct VSInput
{
    float3 position : POSITION;
    float3 normal : NORMAL;
    float2 uv : TEXCOORD0;
};

struct VSOutput
{
    float4 position : SV_Position;
    float3 worldNormal : NORMAL;
    float2 uv : TEXCOORD0;
};

// Per-frame camera data (binding 0)
cbuffer CameraData : register(b0)
{
    float4x4 viewProjection;
    float3 cameraPosition;
    float _pad0;
};

// Per-object transform (binding 1)
cbuffer ObjectData : register(b1)
{
    float4x4 worldMatrix;
};

VSOutput main(VSInput input)
{
    VSOutput output;
    float4 worldPos = mul(worldMatrix, float4(input.position, 1.0));
    output.position = mul(viewProjection, worldPos);
    output.worldNormal = mul((float3x3)worldMatrix, input.normal);
    output.uv = input.uv;
    return output;
}
