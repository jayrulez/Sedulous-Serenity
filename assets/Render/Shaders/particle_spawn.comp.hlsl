// Particle Spawn Compute Shader
// Spawns new particles from the dead list
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
    uint SpawnCount;
    float DeltaTime;
    float TotalTime;
};

// Buffers
RWStructuredBuffer<Particle> Particles : register(u0);
RWStructuredBuffer<uint> AliveList : register(u1);
RWStructuredBuffer<uint> DeadList : register(u2);
RWStructuredBuffer<uint> Counters : register(u3); // [0] = alive count, [1] = dead count

// Simple hash function for randomness
float Hash(uint seed)
{
    seed = (seed ^ 61) ^ (seed >> 16);
    seed *= 9;
    seed = seed ^ (seed >> 4);
    seed *= 0x27d4eb2d;
    seed = seed ^ (seed >> 15);
    return float(seed) / 4294967295.0;
}

float3 RandomInSphere(uint seed)
{
    float theta = Hash(seed) * 6.28318530718;
    float phi = acos(2.0 * Hash(seed + 1) - 1.0);
    float r = pow(Hash(seed + 2), 1.0 / 3.0);

    float sinPhi = sin(phi);
    return float3(
        r * sinPhi * cos(theta),
        r * sinPhi * sin(theta),
        r * cos(phi)
    );
}

[numthreads(64, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    if (DTid.x >= SpawnCount)
        return;

    // Atomically decrement dead count and get index
    uint deadIndex;
    InterlockedAdd(Counters[1], -1, deadIndex);

    if (deadIndex == 0 || deadIndex > MaxParticles)
    {
        // Restore counter if no dead particles
        InterlockedAdd(Counters[1], 1);
        return;
    }

    // Get particle index from dead list
    uint particleIndex = DeadList[deadIndex - 1];

    // Generate random seed based on particle index and time
    uint seed = particleIndex * 1234567 + uint(TotalTime * 1000.0);

    // Initialize particle
    Particle p;

    // Random position within spawn radius
    float3 offset = RandomInSphere(seed) * SpawnRadius;
    p.Position = EmitterPosition + offset;

    // Random velocity
    float3 randomDir = normalize(RandomInSphere(seed + 100));
    p.Velocity = BaseVelocity + randomDir * VelocityRandomness;

    // Random lifetime
    p.Lifetime = lerp(LifetimeMin, LifetimeMax, Hash(seed + 200));
    p.Age = 0.0;

    // Initial color and size
    p.Color = ColorStart;
    p.Size = SizeStart;

    // Random rotation
    p.Rotation = Hash(seed + 300) * 6.28318530718;
    p.RotationSpeed = (Hash(seed + 400) - 0.5) * 2.0;

    Particles[particleIndex] = p;

    // Add to alive list
    uint aliveIndex;
    InterlockedAdd(Counters[0], 1, aliveIndex);
    AliveList[aliveIndex] = particleIndex;
}
