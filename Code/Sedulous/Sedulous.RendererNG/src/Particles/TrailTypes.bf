namespace Sedulous.RendererNG;

using System;
using Sedulous.Mathematics;

/// A single point in a particle trail.
struct TrailPoint
{
	/// Position in world space.
	public Vector3 Position;

	/// Width at this point.
	public float Width;

	/// Color at this point.
	public Color Color;

	/// Time when this point was created.
	public float Time;

	/// Direction of movement (for orientation).
	public Vector3 Direction;

	public this()
	{
		Position = .Zero;
		Width = 1.0f;
		Color = .White;
		Time = 0;
		Direction = .Zero;
	}

	public this(Vector3 position, float width, Color color, float time, Vector3 direction)
	{
		Position = position;
		Width = width;
		Color = color;
		Time = time;
		Direction = direction;
	}
}

/// GPU vertex format for trail rendering (24 bytes).
[CRepr]
struct TrailVertex
{
	/// Position in world space.
	public Vector3 Position;

	/// Texture coordinate (U = along trail, V = across trail).
	public Vector2 TexCoord;

	/// Vertex color with alpha.
	public Color Color;

	public const uint32 Stride = 24;

	public this(Vector3 position, Vector2 texCoord, Color color)
	{
		Position = position;
		TexCoord = texCoord;
		Color = color;
	}
}

/// Trail settings for particle emitters.
struct TrailSettings
{
	/// Whether trails are enabled.
	public bool Enabled = false;

	/// Maximum number of points per trail.
	public int32 MaxPoints = 20;

	/// Minimum distance between trail points.
	public float MinVertexDistance = 0.1f;

	/// Width at the particle (head of trail).
	public float WidthStart = 1.0f;

	/// Width at the tail of the trail.
	public float WidthEnd = 0.0f;

	/// Maximum age of trail points in seconds.
	public float MaxAge = 1.0f;

	/// Whether to inherit particle color.
	public bool InheritParticleColor = true;

	/// Fixed trail color (used if InheritParticleColor is false).
	public Color TrailColor = .White;

	/// Blend mode for trail rendering.
	public ParticleBlendMode BlendMode = .Additive;

	/// Creates default trail settings.
	public static Self Default => .() { Enabled = true };

	/// Creates laser beam trail settings.
	public static Self Laser => .()
	{
		Enabled = true,
		MaxPoints = 30,
		MinVertexDistance = 0.05f,
		WidthStart = 0.1f,
		WidthEnd = 0.05f,
		MaxAge = 0.5f
	};

	/// Creates magic trail settings.
	public static Self Magic => .()
	{
		Enabled = true,
		MaxPoints = 40,
		MinVertexDistance = 0.08f,
		WidthStart = 0.2f,
		WidthEnd = 0.0f,
		MaxAge = 0.8f
	};

	/// Creates motion blur trail settings.
	public static Self MotionBlur => .()
	{
		Enabled = true,
		MaxPoints = 10,
		MinVertexDistance = 0.02f,
		WidthStart = 1.0f,
		WidthEnd = 0.5f,
		MaxAge = 0.1f
	};
}

/// Trail uniform data for shaders.
[CRepr]
struct TrailUniforms
{
	/// x = useTexture, y = softEdge, z = unused, w = unused
	public Vector4 Params;

	public const uint32 Size = 16;

	public static Self Default => .()
	{
		Params = .(0, 0.3f, 0, 0)
	};
}
