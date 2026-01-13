namespace Sedulous.Renderer;

using Sedulous.Mathematics;
using Sedulous.RHI;
using System;

/// GPU-uploadable particle vertex data.
/// Size: 52 bytes per particle
[CRepr]
struct ParticleVertex
{
	/// World position of the particle center.
	public Vector3 Position;     // 12 bytes

	/// Billboard size (width, height).
	public Vector2 Size;         // 8 bytes

	/// Particle color with alpha.
	public Color Color;          // 4 bytes

	/// Rotation angle in radians.
	public float Rotation;       // 4 bytes

	/// Texture coordinate offset for atlas (U, V).
	/// For single textures: (0, 0)
	/// For atlases: (column * frameWidth, row * frameHeight)
	public Vector2 TexCoordOffset; // 8 bytes

	/// Texture coordinate scale for atlas (width, height of single frame).
	/// For single textures: (1, 1)
	/// For atlases: (1/columns, 1/rows)
	public Vector2 TexCoordScale;  // 8 bytes

	/// Velocity direction for stretched billboards (normalized XY in view space).
	/// W component encodes stretch length.
	public Vector2 Velocity2D;     // 8 bytes

	/// Creates a vertex from a particle (basic, no texture atlas).
	public this(Particle p)
	{
		Position = p.Position;
		Size = p.Size;
		Color = p.Color;
		Rotation = p.Rotation;
		TexCoordOffset = .Zero;
		TexCoordScale = .(1, 1);
		Velocity2D = .Zero;
	}

	/// Creates a vertex with full control over all fields.
	public this(
		Vector3 position,
		Vector2 size,
		Color color,
		float rotation,
		Vector2 texCoordOffset,
		Vector2 texCoordScale,
		Vector2 velocity2D)
	{
		Position = position;
		Size = size;
		Color = color;
		Rotation = rotation;
		TexCoordOffset = texCoordOffset;
		TexCoordScale = texCoordScale;
		Velocity2D = velocity2D;
	}

	/// Creates a vertex from a particle with texture atlas frame.
	public this(Particle p, int32 frameIndex, int32 columns, int32 rows)
	{
		Position = p.Position;
		Size = p.Size;
		Color = p.Color;
		Rotation = p.Rotation;
		Velocity2D = .Zero;

		// Calculate atlas UV offset and scale
		if (columns > 0 && rows > 0)
		{
			int32 col = frameIndex % columns;
			int32 row = frameIndex / columns;
			float frameWidth = 1.0f / columns;
			float frameHeight = 1.0f / rows;
			TexCoordOffset = .(col * frameWidth, row * frameHeight);
			TexCoordScale = .(frameWidth, frameHeight);
		}
		else
		{
			TexCoordOffset = .Zero;
			TexCoordScale = .(1, 1);
		}
	}
}
