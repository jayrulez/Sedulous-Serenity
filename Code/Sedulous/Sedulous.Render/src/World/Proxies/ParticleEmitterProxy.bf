namespace Sedulous.Render;

using System;
using Sedulous.Mathematics;
using Sedulous.Materials;
using Sedulous.RHI;

/// Particle simulation space.
public enum ParticleSpace : uint8
{
	/// Particles simulate in world space.
	World,

	/// Particles simulate relative to emitter.
	Local
}

/// Particle blend mode.
public enum ParticleBlendMode : uint8
{
	/// Standard alpha blending.
	Alpha,

	/// Additive blending.
	Additive,

	/// Premultiplied alpha.
	Premultiplied,

	/// Multiply blending (darkens).
	Multiply
}

/// Particle rendering mode.
public enum ParticleRenderMode : uint8
{
	/// Camera-facing billboards.
	Billboard,

	/// Velocity-aligned billboards.
	StretchedBillboard,

	/// Horizontal billboards (facing up, Y-axis normal).
	HorizontalBillboard,

	/// Vertical billboards (always face camera horizontally, locked Y-up).
	VerticalBillboard,

	/// Mesh particles.
	Mesh
}

/// Proxy for a particle emitter in the render world.
public struct ParticleEmitterProxy
{
	/// Emitter position in world space.
	public Vector3 Position;

	/// Emitter rotation.
	public Quaternion Rotation;

	/// Emitter scale.
	public Vector3 Scale;

	/// Previous frame position (for motion vectors).
	public Vector3 PrevPosition;

	/// Simulation backend (CPU or GPU).
	public ParticleSimulationBackend Backend;

	/// Simulation space.
	public ParticleSpace SimulationSpace;

	/// Blend mode.
	public ParticleBlendMode BlendMode;

	/// Render mode.
	public ParticleRenderMode RenderMode;

	/// CPU emitter simulation state (only used when Backend == CPU).
	public CPUParticleEmitter CPUEmitter;

	/// Handle to the GPU particle buffer.
	public IBuffer ParticleBuffer;

	/// Handle to the GPU indirect draw buffer.
	public IBuffer IndirectBuffer;

	/// Particle texture.
	public ITextureView ParticleTexture;

	/// Material for rendering (optional, for custom shaders).
	public MaterialInstance Material;

	/// Maximum particle count.
	public uint32 MaxParticles;

	/// Current alive particle count (updated by simulation).
	public uint32 AliveCount;

	/// Particles per second spawn rate.
	public float SpawnRate;

	/// Base particle lifetime in seconds.
	public float ParticleLifetime;

	/// Initial particle size.
	public Vector2 StartSize;

	/// End particle size.
	public Vector2 EndSize;

	/// Initial particle color.
	public Vector4 StartColor;

	/// End particle color.
	public Vector4 EndColor;

	/// Initial velocity (in local/world space based on SimulationSpace).
	public Vector3 InitialVelocity;

	/// Velocity randomization range.
	public Vector3 VelocityRandomness;

	/// Gravity multiplier.
	public float GravityMultiplier;

	/// Drag coefficient.
	public float Drag;

	/// Soft particle fade distance (0 = disabled).
	/// When > 0, particles fade out near opaque geometry.
	public float SoftParticleDistance;

	/// Stretch factor for stretched billboards.
	public float StretchFactor;

	// --- Curves over lifetime ---

	/// Size over lifetime curve (overrides StartSize/EndSize linear lerp when active).
	public ParticleCurveVector2 SizeOverLifetime;

	/// Color over lifetime curve (overrides StartColor/EndColor linear lerp when active).
	public ParticleCurveColor ColorOverLifetime;

	/// Speed multiplier over lifetime (scales velocity magnitude, 1.0 = no change).
	public ParticleCurveFloat SpeedOverLifetime;

	/// Alpha multiplier over lifetime (applied on top of color alpha).
	public ParticleCurveFloat AlphaOverLifetime;

	/// Rotation speed over lifetime (radians/sec multiplier).
	public ParticleCurveFloat RotationSpeedOverLifetime;

	// --- Burst emission ---

	/// Number of particles to emit per burst.
	public int32 BurstCount;

	/// Interval between bursts in seconds (0 = single burst on spawn).
	public float BurstInterval;

	/// Number of burst cycles (0 = infinite).
	public int32 BurstCycles;

	// --- Texture atlas ---

	/// Number of columns in the texture atlas (1 = no atlas).
	public int32 AtlasColumns;

	/// Number of rows in the texture atlas (1 = no atlas).
	public int32 AtlasRows;

	/// Animation speed in frames per second (for animated atlas).
	public float AtlasFPS;

	/// Whether atlas animation loops.
	public bool AtlasLoop;

	// --- Force modules ---

	/// Force modules applied during simulation (turbulence, vortex, attractor, wind, radial).
	public ParticleForceModules ForceModules;

	// --- Velocity inheritance ---

	/// Fraction of emitter velocity inherited by spawned particles [0, 1].
	public float VelocityInheritance;

	// --- LOD (Level of Detail) ---

	/// Distance at which emission rate starts to decrease (0 = no LOD).
	public float LODStartDistance;

	/// Distance at which emission is fully culled (0 = no cull).
	public float LODCullDistance;

	/// Minimum emission rate multiplier at LODCullDistance [0, 1] (before full cull).
	public float LODMinRateMultiplier;

	// --- Lifetime variance ---

	/// Randomized lifetime range (min multiplier on ParticleLifetime).
	public float LifetimeVarianceMin;

	/// Randomized lifetime range (max multiplier on ParticleLifetime).
	public float LifetimeVarianceMax;

	/// Sort particles back-to-front (for alpha blending).
	public bool SortParticles;

	/// Whether particles receive scene lighting (cluster-based).
	public bool Lit;

	// --- Sub-emitters ---

	/// Sub-emitter entries (child emitters triggered by particle lifecycle events).
	public SubEmitterEntry[SubEmitterConstants.MaxSubEmitters] SubEmitters;

	/// Number of active sub-emitter entries.
	public int32 SubEmitterCount;

	/// When true, this emitter does not self-emit (only receives particles from parent sub-emitter events).
	public bool SubEmitterOnly;

	/// Trail rendering settings.
	public TrailSettings Trail;

	/// Whether the emitter is enabled.
	public bool IsEnabled;

	/// Whether the emitter is currently emitting.
	public bool IsEmitting;

	/// Render layer mask.
	public uint32 LayerMask;

	/// Generation counter (for handle validation).
	public uint32 Generation;

	/// Whether this proxy slot is in use.
	public bool IsActive;

	/// Gets the world transform matrix.
	public Matrix GetWorldMatrix()
	{
		return Matrix.CreateScale(Scale) *
			   Matrix.CreateFromQuaternion(Rotation) *
			   Matrix.CreateTranslation(Position);
	}

	/// Updates the emitter position and saves previous.
	public void SetPosition(Vector3 position) mut
	{
		PrevPosition = Position;
		Position = position;
	}

	/// Creates a default particle emitter.
	public static Self CreateDefault()
	{
		var emitter = Self();
		emitter.Position = .Zero;
		emitter.Rotation = .Identity;
		emitter.Scale = .One;
		emitter.PrevPosition = .Zero;
		emitter.Backend = .GPU;
		emitter.SimulationSpace = .World;
		emitter.BlendMode = .Alpha;
		emitter.RenderMode = .Billboard;
		emitter.CPUEmitter = null;
		emitter.MaxParticles = 1000;
		emitter.SpawnRate = 100.0f;
		emitter.ParticleLifetime = 2.0f;
		emitter.StartSize = .(0.1f, 0.1f);
		emitter.EndSize = .(0.05f, 0.05f);
		emitter.StartColor = .(1, 1, 1, 1);
		emitter.EndColor = .(1, 1, 1, 0);
		emitter.InitialVelocity = .(0, 1, 0);
		emitter.VelocityRandomness = .(0.5f, 0.5f, 0.5f);
		emitter.GravityMultiplier = 0.0f;
		emitter.Drag = 0.0f;
		emitter.SoftParticleDistance = 0.0f;
		emitter.StretchFactor = 1.0f;
		emitter.SizeOverLifetime = default;
		emitter.ColorOverLifetime = default;
		emitter.SpeedOverLifetime = default;
		emitter.AlphaOverLifetime = default;
		emitter.RotationSpeedOverLifetime = default;
		emitter.BurstCount = 0;
		emitter.BurstInterval = 0;
		emitter.BurstCycles = 0;
		emitter.AtlasColumns = 1;
		emitter.AtlasRows = 1;
		emitter.AtlasFPS = 0;
		emitter.AtlasLoop = true;
		emitter.ForceModules = default;
		emitter.VelocityInheritance = 0;
		emitter.LODStartDistance = 0;
		emitter.LODCullDistance = 0;
		emitter.LODMinRateMultiplier = 0;
		emitter.LifetimeVarianceMin = 1.0f;
		emitter.LifetimeVarianceMax = 1.0f;
		emitter.SortParticles = true;
		emitter.Lit = false;
		emitter.SubEmitters = default;
		emitter.SubEmitterCount = 0;
		emitter.SubEmitterOnly = false;
		emitter.Trail = .Default();
		emitter.IsEnabled = true;
		emitter.IsEmitting = true;
		emitter.LayerMask = 0xFFFFFFFF;
		return emitter;
	}

	/// Resets the proxy for reuse.
	public void Reset() mut
	{
		Position = .Zero;
		Rotation = .Identity;
		Scale = .One;
		PrevPosition = .Zero;
		Backend = .GPU;
		SimulationSpace = .World;
		BlendMode = .Alpha;
		RenderMode = .Billboard;
		CPUEmitter = null;
		ParticleBuffer = null;
		IndirectBuffer = null;
		ParticleTexture = null;
		Material = null;
		MaxParticles = 0;
		AliveCount = 0;
		SpawnRate = 0;
		ParticleLifetime = 1.0f;
		StartSize = .(0.1f, 0.1f);
		EndSize = .(0.1f, 0.1f);
		StartColor = .(1, 1, 1, 1);
		EndColor = .(1, 1, 1, 1);
		InitialVelocity = .Zero;
		VelocityRandomness = .Zero;
		GravityMultiplier = 1.0f;
		Drag = 0.0f;
		SoftParticleDistance = 0.0f;
		StretchFactor = 1.0f;
		SizeOverLifetime = default;
		ColorOverLifetime = default;
		SpeedOverLifetime = default;
		AlphaOverLifetime = default;
		RotationSpeedOverLifetime = default;
		BurstCount = 0;
		BurstInterval = 0;
		BurstCycles = 0;
		AtlasColumns = 1;
		AtlasRows = 1;
		AtlasFPS = 0;
		AtlasLoop = false;
		ForceModules = default;
		VelocityInheritance = 0;
		LODStartDistance = 0;
		LODCullDistance = 0;
		LODMinRateMultiplier = 0;
		LifetimeVarianceMin = 1.0f;
		LifetimeVarianceMax = 1.0f;
		SortParticles = false;
		Lit = false;
		SubEmitters = default;
		SubEmitterCount = 0;
		SubEmitterOnly = false;
		Trail = default;
		IsEnabled = false;
		IsEmitting = false;
		LayerMask = 0xFFFFFFFF;
		IsActive = false;
	}
}
