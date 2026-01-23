namespace Sedulous.Render;

using System;
using Sedulous.Mathematics;
using Sedulous.RHI;

/// Proxy for a standalone trail emitter in the render world.
/// Unlike particle trails, standalone trails are driven directly by game code
/// calling AddPoint() each frame (for sword swings, motion trails, etc.).
public struct TrailEmitterProxy
{
	/// Blend mode for trail rendering.
	public ParticleBlendMode BlendMode;

	/// Maximum number of trail points in the ring buffer.
	public int32 MaxPoints;

	/// Trail point lifetime in seconds. Points older than this are discarded.
	public float Lifetime;

	/// Width at the newest point (head).
	public float WidthStart;

	/// Width at the oldest point (tail).
	public float WidthEnd;

	/// Minimum distance between consecutive trail points.
	public float MinVertexDistance;

	/// Trail color (multiplied with per-point color).
	public Vector4 Color;

	/// Soft particle distance (0 = disabled).
	public float SoftParticleDistance;

	/// The standalone trail emitter instance (manages ring buffer and GPU upload).
	public TrailEmitter Emitter;

	/// Whether the trail is enabled.
	public bool IsEnabled;

	/// Whether this proxy slot is in use.
	public bool IsActive;

	/// Render layer mask.
	public uint32 LayerMask;

	/// Generation counter (for handle validation).
	public uint32 Generation;

	/// Creates a default trail emitter proxy.
	public static Self CreateDefault()
	{
		return .()
		{
			BlendMode = .Alpha,
			MaxPoints = 32,
			Lifetime = 1.0f,
			WidthStart = 0.1f,
			WidthEnd = 0.0f,
			MinVertexDistance = 0.02f,
			Color = .(1, 1, 1, 1),
			SoftParticleDistance = 0.0f,
			Emitter = null,
			IsEnabled = true,
			IsActive = false,
			LayerMask = 0xFFFFFFFF,
			Generation = 0
		};
	}

	/// Resets the proxy for reuse.
	public void Reset() mut
	{
		BlendMode = .Alpha;
		MaxPoints = 0;
		Lifetime = 1.0f;
		WidthStart = 0.1f;
		WidthEnd = 0.0f;
		MinVertexDistance = 0.02f;
		Color = .(1, 1, 1, 1);
		SoftParticleDistance = 0.0f;
		Emitter = null;
		IsEnabled = false;
		IsActive = false;
		LayerMask = 0xFFFFFFFF;
	}
}
