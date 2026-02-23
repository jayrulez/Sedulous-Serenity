// Border sampler vertex shader

struct VSOutput
{
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
};

VSOutput main(float2 pos : POSITION, float2 uv : TEXCOORD0)
{
    VSOutput output;
    output.position = float4(pos, 0.0, 1.0);
    output.uv = uv;
    return output;
}
