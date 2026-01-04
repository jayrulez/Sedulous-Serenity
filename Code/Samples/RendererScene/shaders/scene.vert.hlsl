// Scene vertex shader with instancing

struct VSInput
{
    // Per-vertex data
    float3 position : POSITION;
    float3 normal : NORMAL;
    float2 uv : TEXCOORD0;

    // Per-instance data (columns from column-major matrix)
    float4 instanceCol0 : TEXCOORD3;  // Transform matrix column 0
    float4 instanceCol1 : TEXCOORD4;  // Transform matrix column 1
    float4 instanceCol2 : TEXCOORD5;  // Transform matrix column 2
    float4 instanceCol3 : TEXCOORD6;  // Transform matrix column 3 (translation)
    float4 instanceColor : TEXCOORD7; // Instance color
};

struct VSOutput
{
    float4 position : SV_Position;
    float3 worldPos : TEXCOORD0;
    float3 worldNormal : TEXCOORD1;
    float2 uv : TEXCOORD2;
    float4 color : COLOR;
};

cbuffer CameraUniforms : register(b0)
{
    column_major float4x4 viewProjection;
    float3 cameraPosition;
    float _pad0;
};

VSOutput main(VSInput input)
{
    VSOutput output;

    // Reconstruct world matrix from instance columns
    // float4x4(a,b,c,d) creates rows from parameters, so we transpose
    // to convert our columns back to proper column-major layout
    float4x4 world = transpose(float4x4(
        input.instanceCol0,
        input.instanceCol1,
        input.instanceCol2,
        input.instanceCol3
    ));

    float4 worldPos = mul(world, float4(input.position, 1.0));
    output.position = mul(viewProjection, worldPos);
    output.worldPos = worldPos.xyz;
    output.worldNormal = mul((float3x3)world, input.normal);
    output.uv = input.uv;
    output.color = input.instanceColor;

    return output;
}
