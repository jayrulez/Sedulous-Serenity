// Compute shader for particle simulation
// Updates particle positions based on velocity and time

struct Particle
{
    float2 position;
    float2 velocity;
    float4 color;
};

cbuffer SimParams : register(b0)
{
    float deltaTime;
    float totalTime;
    float2 bounds;  // x = width/2, y = height/2
};

RWStructuredBuffer<Particle> particles : register(u0);

[numthreads(64, 1, 1)]
void main(uint3 dispatchID : SV_DispatchThreadID)
{
    uint index = dispatchID.x;

    Particle p = particles[index];

    // Update position
    p.position += p.velocity * deltaTime;

    // Bounce off boundaries
    if (p.position.x < -bounds.x || p.position.x > bounds.x)
    {
        p.velocity.x = -p.velocity.x;
        p.position.x = clamp(p.position.x, -bounds.x, bounds.x);
    }
    if (p.position.y < -bounds.y || p.position.y > bounds.y)
    {
        p.velocity.y = -p.velocity.y;
        p.position.y = clamp(p.position.y, -bounds.y, bounds.y);
    }

    // Add some swirl effect based on time
    float angle = totalTime * 0.5;
    float2 center = float2(0, 0);
    float2 toCenter = center - p.position;
    float dist = length(toCenter);
    if (dist > 0.01)
    {
        float2 tangent = float2(-toCenter.y, toCenter.x) / dist;
        p.velocity += tangent * 0.1 * deltaTime;
    }

    // Damping
    p.velocity *= 0.999;

    particles[index] = p;
}
