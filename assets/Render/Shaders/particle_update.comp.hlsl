// Particle Update Compute Shader
// Updates particle physics and kills dead particles
#pragma pack_matrix(row_major)

// Particle structure
struct Particle
{
    float3 Position;
    float Age;
    float3 Velocity;
    float Lifetime;
    float4 Color;
    float2 Size;
    float Rotation;
    float RotationSpeed;
};

// Emitter parameters
cbuffer EmitterParams : register(b0)
{
    float3 EmitterPosition;
    float SpawnRate;
    float3 EmitterDirection;
    float SpawnRadius;
    float3 BaseVelocity;
    float VelocityRandomness;
    float4 ColorStart;
    float4 ColorEnd;
    float2 SizeStart;
    float2 SizeEnd;
    float LifetimeMin;
    float LifetimeMax;
    float Gravity;
    float Drag;
    uint MaxParticles;
    uint AliveCount;
    float DeltaTime;
    float TotalTime;
    uint SpawnCount;
    uint _Padding;
};

// Buffers (same layout as spawn shader for simplicity)
RWStructuredBuffer<Particle> Particles : register(u0);
RWStructuredBuffer<uint> AliveList : register(u1);  // Single alive list (read/write in place)
RWStructuredBuffer<uint> DeadList : register(u2);
RWStructuredBuffer<uint> Counters : register(u3); // [0] = alive count, [1] = dead count

static const float3 GRAVITY_VEC = float3(0.0, -9.81, 0.0);

[numthreads(64, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    if (DTid.x >= AliveCount)
        return;

    uint particleIndex = AliveList[DTid.x];

    // Skip invalid entries (particles that died and left holes in the list)
    if (particleIndex == 0xFFFFFFFF || particleIndex >= MaxParticles)
        return;

    Particle p = Particles[particleIndex];

    // Update age
    p.Age += DeltaTime;

    // Check if particle is dead
    if (p.Age >= p.Lifetime)
    {
        // Add to dead list
        uint deadIndex;
        InterlockedAdd(Counters[1], 1, deadIndex);
        DeadList[deadIndex] = particleIndex;

        // Mark slot as invalid in alive list (will be compacted later or skipped)
        AliveList[DTid.x] = 0xFFFFFFFF;
        return;
    }

    // Calculate life ratio for interpolation
    float lifeRatio = p.Age / p.Lifetime;

    // Apply gravity
    p.Velocity += GRAVITY_VEC * Gravity * DeltaTime;

    // Apply drag
    p.Velocity *= (1.0 - Drag * DeltaTime);

    // Update position
    p.Position += p.Velocity * DeltaTime;

    // Update rotation
    p.Rotation += p.RotationSpeed * DeltaTime;

    // Interpolate color
    p.Color = lerp(ColorStart, ColorEnd, lifeRatio);

    // Interpolate size
    p.Size = lerp(SizeStart, SizeEnd, lifeRatio);

    // Fade out at end of life
    float fadeStart = 0.8;
    if (lifeRatio > fadeStart)
    {
        float fadeRatio = (lifeRatio - fadeStart) / (1.0 - fadeStart);
        p.Color.a *= (1.0 - fadeRatio);
    }

    // Write back
    Particles[particleIndex] = p;
}
