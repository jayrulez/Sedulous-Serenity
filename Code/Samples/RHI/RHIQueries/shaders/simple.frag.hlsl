struct PSInput
{
    float4 position : SV_Position;
    float3 color : COLOR;
};

float4 main(PSInput input) : SV_Target
{
    return float4(input.color, 1.0);
}
