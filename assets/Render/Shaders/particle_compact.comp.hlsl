// Particle Compact Compute Shader
// Removes holes (0xFFFFFFFF) from the alive list, producing a dense output list.
// Clears the old list as it reads, preparing it for the next ping-pong swap.
#pragma pack_matrix(row_major)

// Emitter parameters (same layout as spawn/update shaders)
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

    // Emission shape parameters (unused by compact, but must match layout)
    uint ShapeType;
    float ShapeSizeX;
    float ShapeSizeY;
    float ShapeSizeZ;
    float ShapeConeAngle;
    float ShapeArc;
    uint ShapeEmitFromSurface;
    uint _ShapePadding;
};

// Old alive list — read entries and clear to 0xFFFFFFFF
RWStructuredBuffer<uint> AliveList : register(u1);

// Counters: [0] = compact write cursor (reset to 0 by CPU before dispatch)
RWStructuredBuffer<uint> Counters : register(u3);

// New alive list — write compacted entries here
RWStructuredBuffer<uint> AliveListNew : register(u4);

[numthreads(64, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    if (DTid.x >= MaxParticles)
        return;

    uint idx = AliveList[DTid.x];
    AliveList[DTid.x] = 0xFFFFFFFF; // Clear as we read (prepares for next swap)

    if (idx != 0xFFFFFFFF && idx < MaxParticles)
    {
        uint newSlot;
        InterlockedAdd(Counters[0], 1, newSlot);
        AliveListNew[newSlot] = idx;
    }
}
