namespace Sedulous.RendererNG;

using Sedulous.Mathematics;
using System;

/// Billboard mode for sprites.
enum BillboardMode : uint8
{
	/// No billboarding (uses transform).
	None,
	/// Face camera on all axes.
	Full,
	/// Face camera on Y axis only.
	AxisY,
	/// Face camera on specified axis.
	CustomAxis
}

/// Proxy for a sprite/billboard.
/// Contains all data needed to render a 2D sprite in 3D space.
struct SpriteProxy
{
	/// World position of the sprite center.
	public Vector3 Position;

	/// Sprite size (width, height).
	public Vector2 Size;

	/// Rotation angle in radians (for screen-space rotation).
	public float Rotation;

	/// UV rectangle (x, y, width, height) in texture coordinates.
	public Vector4 UVRect;

	/// Sprite color (RGBA).
	public Color Color;

	/// Handle to the sprite texture.
	public uint32 TextureHandle;

	/// Billboard mode.
	public BillboardMode Billboard;

	/// Blend mode for rendering.
	public ParticleBlendMode BlendMode;

	/// Sprite flags.
	public SpriteFlags Flags;

	/// Layer mask for visibility.
	public uint32 LayerMask;

	/// Sort key for render order.
	public uint32 SortKey;

	/// Custom billboard axis (when Billboard = CustomAxis).
	public Vector3 BillboardAxis;

	/// Depth offset for sorting.
	public float DepthOffset;

	/// Returns true if this sprite is visible.
	public bool IsVisible => (Flags & .Visible) != 0;

	/// Creates a default sprite proxy.
	public static Self Default => .()
	{
		Position = .Zero,
		Size = .(1, 1),
		Rotation = 0,
		UVRect = .(0, 0, 1, 1),
		Color = .White,
		TextureHandle = 0,
		Billboard = .Full,
		BlendMode = .AlphaBlend,
		Flags = .Visible,
		LayerMask = 0xFFFFFFFF,
		SortKey = 0,
		BillboardAxis = .(0, 1, 0),
		DepthOffset = 0
	};
}

/// Flags for sprite behavior.
[AllowDuplicates]
enum SpriteFlags : uint32
{
	None = 0,

	/// Sprite is visible.
	Visible = 1 << 0,

	/// Sprite casts shadows.
	CastShadow = 1 << 1,

	/// Flip sprite horizontally.
	FlipX = 1 << 2,

	/// Flip sprite vertically.
	FlipY = 1 << 3,

	/// Use pixel-perfect rendering.
	PixelPerfect = 1 << 4,

	/// Default flags.
	Default = Visible
}
