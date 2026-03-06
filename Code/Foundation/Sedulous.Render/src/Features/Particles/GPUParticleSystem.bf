namespace Sedulous.Render;

using Sedulous.RHI;

/// Per-emitter GPU particle system resources.
/// Uses ping-pong alive lists with a compaction pass to avoid append-only overflow.
public class GPUParticleSystem
{
	public IBuffer ParticleBuffer ~ delete _;
	public IBuffer AliveListA ~ delete _;
	public IBuffer AliveListB ~ delete _;
	public IBuffer DeadList ~ delete _;
	public IBuffer Counters ~ delete _;      // [0] = alive write cursor, [1] = dead count
	public IBuffer EmitterParams ~ delete _;
	public IBuffer ParticleParams ~ delete _; // For render shader b1

	// Two compute bind groups for ping-pong: A has AliveListA at u1/B at u4, B has the reverse.
	public IBindGroup ComputeBindGroupA ~ delete _;
	public IBindGroup ComputeBindGroupB ~ delete _;

	// When true: compact reads A (via BindGroupA), spawn/update use B (via BindGroupB).
	// When false: compact reads B (via BindGroupB), spawn/update use A (via BindGroupA).
	public bool UseA = true;

	// Per-frame/view render bind groups (reference per-view camera uniform buffer)
	public IBindGroup[RenderConfig.FrameBufferCount * RenderConfig.MaxViews] RenderBindGroups ~ { for (let bg in _) delete bg; };

	public uint32 MaxParticles;

	// CPU-side estimate of alive particles (since GPU readback is expensive)
	public uint32 EstimatedAliveCount;
	public float AccumulatedSpawn; // Fractional spawn accumulator
	public uint32 PendingSpawnCount; // Particles to spawn this frame

	// Blend mode for this emitter's particles
	public ParticleBlendMode BlendMode;

	/// Gets the current alive list buffer (the one spawn/update/render should reference).
	public IBuffer CurrentAliveList => UseA ? AliveListB : AliveListA;

	/// Gets the compute bind group for the compact pass (reads old list).
	public IBindGroup CompactBindGroup => UseA ? ComputeBindGroupA : ComputeBindGroupB;

	/// Gets the compute bind group for spawn/update (operates on new list).
	public IBindGroup SpawnUpdateBindGroup => UseA ? ComputeBindGroupB : ComputeBindGroupA;

	/// Swaps the ping-pong state for the next frame.
	public void SwapAliveList()
	{
		UseA = !UseA;
	}

	/// Gets the render bind group for the current frame.
	public IBindGroup GetRenderBindGroup(int32 frameIndex)
	{
		return RenderBindGroups[frameIndex];
	}
}
