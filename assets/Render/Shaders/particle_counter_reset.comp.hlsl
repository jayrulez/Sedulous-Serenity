// Particle Counter Reset Compute Shader
// Resets Counters[0] (alive write cursor) to 0 before the compact pass.
// Runs on GPU timeline to avoid CPU/GPU race on Upload memory.
#pragma pack_matrix(row_major)

RWStructuredBuffer<uint> Counters : register(u3); // [0] = alive write cursor

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    Counters[0] = 0;
}
