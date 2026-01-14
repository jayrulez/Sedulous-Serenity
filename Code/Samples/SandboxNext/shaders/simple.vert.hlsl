// Simple vertex shader for colored geometry
// Supports position + color vertex format

struct VSInput
{
    float3 position : POSITION;
    float4 color : COLOR0;
};

struct VSOutput
{
    float4 position : SV_Position;
    float4 color : COLOR0;
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
    output.color = input.color;
    return output;
}
