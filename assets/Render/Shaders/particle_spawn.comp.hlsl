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
    uint AliveCount;
    float DeltaTime;
    float TotalTime;
    uint SpawnCount;
    uint _Padding;

    // Emission shape parameters
    uint ShapeType;       // 0=Point, 1=Sphere, 2=Hemisphere, 3=Cone, 4=Box, 5=Circle, 6=Edge
    float ShapeSizeX;
    float ShapeSizeY;
    float ShapeSizeZ;
    float ShapeConeAngle;
    float ShapeArc;
    uint ShapeEmitFromSurface;
    uint _ShapePadding;
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

static const float PI = 3.14159265359;
static const float TWO_PI = 6.28318530718;

float3 RandomOnUnitSphere(uint seed)
{
    float theta = Hash(seed) * TWO_PI;
    float phi = acos(2.0 * Hash(seed + 1) - 1.0);
    float sinPhi = sin(phi);
    return float3(sinPhi * cos(theta), cos(phi), sinPhi * sin(theta));
}

float3 RandomOnUnitSphereArc(uint seed, float arc)
{
    float theta = Hash(seed) * arc;
    float phi = acos(2.0 * Hash(seed + 1) - 1.0);
    float sinPhi = sin(phi);
    return float3(sinPhi * cos(theta), cos(phi), sinPhi * sin(theta));
}

// Sample emission shape — mirrors CPU EmissionShape.Sample()
void SampleShape(uint seed, out float3 position, out float3 direction)
{
    float arc = (ShapeArc <= 0.0 || ShapeArc >= TWO_PI) ? TWO_PI : ShapeArc;

    if (ShapeType == 0) // Point
    {
        position = float3(0, 0, 0);
        direction = float3(0, 1, 0);
    }
    else if (ShapeType == 1) // Sphere
    {
        float3 dir = RandomOnUnitSphereArc(seed + 50, arc);
        float r = ShapeSizeX;
        if (!ShapeEmitFromSurface)
            r *= pow(Hash(seed + 52), 1.0 / 3.0);
        position = dir * r;
        direction = normalize(dir);
    }
    else if (ShapeType == 2) // Hemisphere
    {
        float3 dir = RandomOnUnitSphereArc(seed + 50, arc);
        dir.y = abs(dir.y);
        float r = ShapeSizeX;
        if (!ShapeEmitFromSurface)
            r *= pow(Hash(seed + 52), 1.0 / 3.0);
        position = dir * r;
        direction = normalize(dir);
    }
    else if (ShapeType == 3) // Cone
    {
        float cosAngle = cos(ShapeConeAngle);
        float z = cosAngle + (1.0 - cosAngle) * Hash(seed + 50);
        float phi = Hash(seed + 51) * arc;
        float sinTheta = sqrt(1.0 - z * z);
        direction = float3(sinTheta * cos(phi), z, sinTheta * sin(phi));
        float r = ShapeSizeX;
        if (!ShapeEmitFromSurface)
            r *= Hash(seed + 52);
        position = direction * r;
    }
    else if (ShapeType == 4) // Box
    {
        if (ShapeEmitFromSurface)
        {
            uint face = uint(Hash(seed + 50) * 6.0) % 6;
            float3 pos = float3(
                (Hash(seed + 51) * 2.0 - 1.0) * ShapeSizeX,
                (Hash(seed + 52) * 2.0 - 1.0) * ShapeSizeY,
                (Hash(seed + 53) * 2.0 - 1.0) * ShapeSizeZ
            );
            direction = float3(0, 1, 0);
            if (face == 0)      { pos.x =  ShapeSizeX; direction = float3( 1, 0, 0); }
            else if (face == 1) { pos.x = -ShapeSizeX; direction = float3(-1, 0, 0); }
            else if (face == 2) { pos.y =  ShapeSizeY; direction = float3( 0, 1, 0); }
            else if (face == 3) { pos.y = -ShapeSizeY; direction = float3( 0,-1, 0); }
            else if (face == 4) { pos.z =  ShapeSizeZ; direction = float3( 0, 0, 1); }
            else                { pos.z = -ShapeSizeZ; direction = float3( 0, 0,-1); }
            position = pos;
        }
        else
        {
            position = float3(
                (Hash(seed + 51) * 2.0 - 1.0) * ShapeSizeX,
                (Hash(seed + 52) * 2.0 - 1.0) * ShapeSizeY,
                (Hash(seed + 53) * 2.0 - 1.0) * ShapeSizeZ
            );
            direction = float3(0, 1, 0);
        }
    }
    else if (ShapeType == 5) // Circle
    {
        float angle = Hash(seed + 50) * arc;
        float r = ShapeSizeX;
        if (!ShapeEmitFromSurface)
            r *= sqrt(Hash(seed + 51));
        position = float3(cos(angle) * r, 0, sin(angle) * r);
        direction = float3(0, 1, 0);
    }
    else // Edge (6)
    {
        float t = Hash(seed + 50) * 2.0 - 1.0;
        position = float3(t * ShapeSizeX, 0, 0);
        direction = float3(0, 1, 0);
    }
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

    // Sample emission shape for spawn position and direction
    float3 shapePos;
    float3 shapeDir;
    SampleShape(seed, shapePos, shapeDir);
    p.Position = EmitterPosition + shapePos;

    // Velocity: use base velocity if present, otherwise use shape direction
    float baseSpeed = length(BaseVelocity);
    float3 randomDir = normalize(RandomOnUnitSphere(seed + 100));
    if (baseSpeed > 0.001)
        p.Velocity = BaseVelocity + randomDir * VelocityRandomness;
    else
        p.Velocity = shapeDir + randomDir * VelocityRandomness;

    // Random lifetime
    p.Lifetime = lerp(LifetimeMin, LifetimeMax, Hash(seed + 200));
    p.Age = 0.0;

    // Initial color and size
    p.Color = ColorStart;
    p.Size = SizeStart;

    // Random rotation
    p.Rotation = Hash(seed + 300) * TWO_PI;
    p.RotationSpeed = (Hash(seed + 400) - 0.5) * 2.0;

    Particles[particleIndex] = p;

    // Add to alive list
    uint aliveIndex;
    InterlockedAdd(Counters[0], 1, aliveIndex);
    AliveList[aliveIndex] = particleIndex;
}
