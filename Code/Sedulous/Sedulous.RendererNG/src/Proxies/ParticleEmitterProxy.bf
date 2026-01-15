namespace Sedulous.RendererNG;

using Sedulous.Mathematics;

/// Blend mode for particle rendering.
enum ParticleBlendMode : uint8
{
	/// Alpha blending.
	AlphaBlend,
	/// Additive blending.
	Additive,
	/// Multiplicative blending.
	Multiply,
	/// Premultiplied alpha blending.
	PremultipliedAlpha
}

/// Proxy for a particle emitter.
/// Contains all data needed to update and render particles.
struct ParticleEmitterProxy
{
	/// World position of the emitter.
	public Vector3 Position;

	/// Emitter rotation (quaternion).
	public Quaternion Rotation;

	/// World-space bounding box for all particles.
	public BoundingBox Bounds;

	/// Handle to the particle texture.
	public uint32 TextureHandle;

	/// Handle to the particle buffer (GPU).
	public BufferHandle ParticleBuffer;

	/// Current number of active particles.
	public uint32 ParticleCount;

	/// Maximum particles this emitter can have.
	public uint32 MaxParticles;

	/// Emission rate (particles per second).
	public float EmissionRate;

	/// Time accumulator for emission.
	public float EmissionAccumulator;

	/// Particle lifetime range (min, max).
	public Vector2 LifetimeRange;

	/// Initial velocity range.
	public Vector3 VelocityMin;
	public Vector3 VelocityMax;

	/// Particle size range (start, end).
	public Vector2 SizeRange;

	/// Particle color (RGBA).
	public Color StartColor;
	public Color EndColor;

	/// Blend mode for rendering.
	public ParticleBlendMode BlendMode;

	/// Emitter flags.
	public ParticleEmitterFlags Flags;

	/// Layer mask for visibility.
	public uint32 LayerMask;

	/// Sort key for render order.
	public uint32 SortKey;

	/// Returns true if this emitter is active.
	public bool IsActive => (Flags & .Active) != 0;

	/// Returns true if soft particles are enabled.
	public bool UseSoftParticles => (Flags & .SoftParticles) != 0;

	/// Creates a default particle emitter proxy.
	public static Self Default => .()
	{
		Position = .Zero,
		Rotation = .Identity,
		Bounds = .(.Zero, .Zero),
		TextureHandle = 0,
		ParticleBuffer = .Invalid,
		ParticleCount = 0,
		MaxParticles = 1000,
		EmissionRate = 100.0f,
		EmissionAccumulator = 0,
		LifetimeRange = .(1.0f, 2.0f),
		VelocityMin = .(-1, 0, -1),
		VelocityMax = .(1, 5, 1),
		SizeRange = .(0.1f, 0.5f),
		StartColor = .White,
		EndColor = .(255, 255, 255, 0),
		BlendMode = .AlphaBlend,
		Flags = .Active | .Visible,
		LayerMask = 0xFFFFFFFF,
		SortKey = 0
	};
}

/// Flags for particle emitter behavior.
enum ParticleEmitterFlags : uint32
{
	None = 0,

	/// Emitter is active and emitting.
	Active = 1 << 0,

	/// Emitter is visible.
	Visible = 1 << 1,

	/// Use soft particles (depth-aware fading).
	SoftParticles = 1 << 2,

	/// Particles are world-space (vs local to emitter).
	WorldSpace = 1 << 3,

	/// Sort particles back-to-front.
	SortParticles = 1 << 4,

	/// Loop emission.
	Looping = 1 << 5,

	/// Default flags.
	Default = Active | Visible | WorldSpace | Looping
}
