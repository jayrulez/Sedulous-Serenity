// Particle rendering vertex shader
// Reads particle data from storage buffer and offsets triangle vertices

struct Particle
{
    float2 position;
    float2 velocity;
    float4 color;
};

StructuredBuffer<Particle> particles : register(t0);

struct VSInput
{
    float2 localPos : POSITION;
    uint instanceID : SV_InstanceID;
};

struct VSOutput
{
    float4 position : SV_Position;
    float4 color : COLOR0;
};

VSOutput main(VSInput input)
{
    VSOutput output;

    Particle p = particles[input.instanceID];

    // Offset the local triangle position by particle position
    float2 worldPos = input.localPos + p.position;

    output.position = float4(worldPos, 0.0, 1.0);
    output.color = p.color;

    return output;
}
