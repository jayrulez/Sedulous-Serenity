namespace Sedulous.RendererNG;

using System;
using Sedulous.Mathematics;

/// GPU-uploadable sprite vertex data (48 bytes).
[CRepr]
struct SpriteVertex
{
	public Vector3 Position;       // 12 bytes - World position
	public Vector2 Size;           // 8 bytes - Width, height
	public Color Color;            // 4 bytes - RGBA color
	public float Rotation;         // 4 bytes - Screen-space rotation
	public Vector4 UVRect;         // 16 bytes - x, y, width, height
	public uint32 Flags;           // 4 bytes - Billboard mode + flip flags

	public const uint32 Stride = 48;

	public this(SpriteProxy sprite)
	{
		Position = sprite.Position;
		Size = sprite.Size;
		Color = sprite.Color;
		Rotation = sprite.Rotation;
		UVRect = sprite.UVRect;

		// Pack billboard mode and flags
		Flags = (uint32)sprite.Billboard;
		if ((sprite.Flags & .FlipX) != 0)
			Flags |= 0x100;
		if ((sprite.Flags & .FlipY) != 0)
			Flags |= 0x200;
	}
}

/// Sprite uniform data for shaders.
[CRepr]
struct SpriteUniforms
{
	public uint32 UseTexture;      // 0 = no texture, 1 = use texture
	public float DepthBias;        // Depth offset for sorting
	public float _Padding0;
	public float _Padding1;

	public const uint32 Size = 16;

	public static Self Default => .()
	{
		UseTexture = 1,
		DepthBias = 0
	};
}

/// Key for sprite pipeline caching.
struct SpritePipelineKey : IHashable
{
	public ParticleBlendMode BlendMode;
	public bool HasDepth;

	public int GetHashCode()
	{
		int hash = (int)BlendMode;
		hash = hash * 31 + (HasDepth ? 1 : 0);
		return hash;
	}
}

/// Draw batch for sprites grouped by texture.
struct SpriteDrawBatch
{
	public uint32 TextureHandle;
	public uint32 VertexOffset;
	public uint32 SpriteCount;
	public ParticleBlendMode BlendMode;
}

/// Statistics for sprite rendering.
struct SpriteStats
{
	public int32 SpriteCount;
	public int32 BatchCount;
	public int32 DrawCalls;
	public int32 PipelineSwitches;
	public uint64 VertexBytesUsed;
}
