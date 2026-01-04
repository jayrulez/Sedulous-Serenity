// GLTF Mesh Vertex Shader
// Standard vertex shader for loaded GLTF models

cbuffer CameraBuffer : register(b0)
{
    float4x4 viewProjection;
    float4x4 view;
    float4x4 projection;
    float3 cameraPosition;
    float _pad0;
};

cbuffer ObjectBuffer : register(b1)
{
    float4x4 model;
    float4 baseColor;
};

struct VSInput
{
    float3 position : POSITION;
    float3 normal : NORMAL;
    float2 texCoord : TEXCOORD0;
    uint color : COLOR;
    float3 tangent : TANGENT;
};

struct PSInput
{
    float4 position : SV_Position;
    float3 worldNormal : NORMAL;
    float2 texCoord : TEXCOORD0;
    float3 worldPos : TEXCOORD1;
};

PSInput main(VSInput input)
{
    PSInput output;

    float4 worldPos = mul(model, float4(input.position, 1.0));
    output.position = mul(viewProjection, worldPos);
    output.worldPos = worldPos.xyz;

    // Transform normal to world space
    float3x3 normalMatrix = (float3x3)model;
    output.worldNormal = normalize(mul(normalMatrix, input.normal));

    output.texCoord = input.texCoord;

    return output;
}
