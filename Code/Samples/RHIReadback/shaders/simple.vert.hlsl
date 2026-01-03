struct VSInput
{
    float2 position : POSITION;
    float3 color : COLOR;
};

struct VSOutput
{
    float4 position : SV_Position;
    float3 color : COLOR;
};

VSOutput main(VSInput input)
{
    VSOutput output;
    output.position = float4(input.position, 0.0, 1.0);
    output.color = input.color;
    return output;
}
