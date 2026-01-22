namespace Sedulous.Render;

using Sedulous.RHI;

/// Per-emitter GPU particle system resources.
public class GPUParticleSystem
{
	public IBuffer ParticleBuffer ~ delete _;
	public IBuffer AliveList ~ delete _;
	public IBuffer DeadList ~ delete _;
	public IBuffer Counters ~ delete _;      // [0] = alive count, [1] = dead count
	public IBuffer EmitterParams ~ delete _;
	public IBuffer ParticleParams ~ delete _; // For render shader b1

	// Compute bind group (does not reference per-frame camera buffer)
	public IBindGroup ComputeBindGroup ~ delete _;

	// Per-frame render bind groups (reference per-frame camera uniform buffer)
	public IBindGroup[RenderConfig.FrameBufferCount] RenderBindGroups ~ { for (let bg in _) delete bg; };

	public uint32 MaxParticles;
	public uint32 ActiveCount;

	// CPU-side estimate of alive particles (since GPU readback is expensive)
	public uint32 EstimatedAliveCount;
	public float AccumulatedSpawn; // Fractional spawn accumulator
	public uint32 PendingSpawnCount; // Particles to spawn this frame

	// Track GPU alive list write position (may diverge from EstimatedAliveCount due to holes)
	public uint32 GPUAliveWriteIndex;
	public float TimeSinceReset; // Time since last buffer reset
	public bool NeedsReset; // Flag to trigger reset on next update

	// Blend mode for this emitter's particles
	public ParticleBlendMode BlendMode;

	/// Gets the render bind group for the current frame.
	public IBindGroup GetRenderBindGroup(int32 frameIndex)
	{
		return RenderBindGroups[frameIndex];
	}
}
