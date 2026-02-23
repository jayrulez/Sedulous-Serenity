// Instanced rendering vertex shader
// Renders many instances with per-instance transform and color

struct VSInput
{
    // Per-vertex data
    float2 position : POSITION;

    // Per-instance data
    float2 instanceOffset : TEXCOORD0;
    float4 instanceColor : COLOR0;
    float instanceRotation : TEXCOORD1;
};

struct VSOutput
{
    float4 position : SV_Position;
    float4 color : COLOR0;
};

VSOutput main(VSInput input)
{
    VSOutput output;

    // Apply per-instance rotation
    float c = cos(input.instanceRotation);
    float s = sin(input.instanceRotation);
    float2 rotated;
    rotated.x = input.position.x * c - input.position.y * s;
    rotated.y = input.position.x * s + input.position.y * c;

    // Apply per-instance offset
    float2 finalPos = rotated + input.instanceOffset;

    output.position = float4(finalPos, 0.0, 1.0);
    output.color = input.instanceColor;

    return output;
}
