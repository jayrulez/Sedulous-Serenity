namespace Sedulous.Renderer;

using System;
using Sedulous.Mathematics;

/// Render proxy for a particle emitter in the scene.
/// References a ParticleSystem owned by a component.
[Reflect]
struct ParticleEmitterProxy
{
	/// Unique ID for this proxy.
	public uint32 Id;

	/// World position of the emitter.
	public Vector3 Position;

	/// World-space bounding box (for culling).
	public BoundingBox WorldBounds;

	/// Reference to the particle system (owned by component).
	public ParticleSystem System;

	/// Flags for rendering behavior.
	public ParticleEmitterProxyFlags Flags;

	/// Layer mask for culling (bitfield).
	public uint32 LayerMask;

	/// Distance from camera (calculated during visibility).
	public float DistanceToCamera;

	/// Sort key for draw call ordering (for transparency sorting).
	public uint64 SortKey;

	/// Creates an invalid proxy.
	public static Self Invalid
	{
		get
		{
			Self p = default;
			p.Id = uint32.MaxValue;
			p.Position = .Zero;
			p.WorldBounds = .(.Zero, .Zero);
			p.System = null;
			p.Flags = .None;
			p.LayerMask = 0xFFFFFFFF;
			p.DistanceToCamera = 0;
			p.SortKey = 0;
			return p;
		}
	}

	/// Creates a particle emitter proxy with the given parameters.
	public this(uint32 id, ParticleSystem system, Vector3 position)
	{
		Id = id;
		System = system;
		Position = position;
		// Default bounds - should be updated based on particle spread
		WorldBounds = .(position - .(5, 5, 5), position + .(5, 5, 5));
		Flags = .Visible | .Emitting;
		LayerMask = 0xFFFFFFFF;
		DistanceToCamera = 0;
		SortKey = 0;
	}

	/// Updates position and bounds.
	public void SetPosition(Vector3 position, float boundsRadius = 5.0f) mut
	{
		Position = position;
		WorldBounds = .(position - .(boundsRadius, boundsRadius, boundsRadius),
					   position + .(boundsRadius, boundsRadius, boundsRadius));
		// Note: ParticleSystem position is set externally by the component
	}

	/// Checks if this proxy is valid.
	public bool IsValid => Id != uint32.MaxValue && System != null;

	/// Checks if visible.
	public bool IsVisible => Flags.HasFlag(.Visible);

	/// Checks if actively emitting new particles.
	public bool IsEmitting => Flags.HasFlag(.Emitting);

	/// Gets the current particle count.
	public int32 ParticleCount => System?.ParticleCount ?? 0;

	/// Checks if has particles to render.
	public bool HasParticles => ParticleCount > 0;
}

/// Flags controlling particle emitter proxy behavior.
enum ParticleEmitterProxyFlags : uint16
{
	None = 0,
	/// Emitter is visible for rendering.
	Visible = 1 << 0,
	/// Emitter is actively spawning new particles.
	Emitting = 1 << 1,
	/// Emitter affects lighting (for lit particles).
	AffectsLighting = 1 << 2,
	/// Emitter casts shadows (expensive).
	CastsShadows = 1 << 3,
	/// Object was culled this frame.
	Culled = 1 << 4,
	/// Use soft particles (depth fade).
	SoftParticles = 1 << 5,
	/// Particles are world-space (vs local-space).
	WorldSpace = 1 << 6
}
