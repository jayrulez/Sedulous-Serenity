namespace Sedulous.Renderer;

using System;
using Sedulous.Mathematics;
using Sedulous.RHI;

/// Render proxy for a billboard sprite in the scene.
/// Decoupled from gameplay entities - stores only render-relevant data.
[Reflect]
struct SpriteProxy
{
	/// Unique ID for this proxy.
	public uint32 Id;

	/// World position of sprite center.
	public Vector3 Position;

	/// Width and height in world units.
	public Vector2 Size;

	/// UV rectangle (minU, minV, maxU, maxV).
	public Vector4 UVRect;

	/// Tint color (RGBA).
	public Color Color;

	/// Texture view for this sprite (null = use default white texture).
	public ITextureView Texture;

	/// World-space bounding box (for culling).
	public BoundingBox WorldBounds;

	/// Flags for rendering behavior.
	public SpriteProxyFlags Flags;

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
			p.Size = .(1, 1);
			p.UVRect = .(0, 0, 1, 1);
			p.Color = .White;
			p.Texture = null;
			p.WorldBounds = .(.Zero, .Zero);
			p.Flags = .None;
			p.LayerMask = 0xFFFFFFFF;
			p.DistanceToCamera = 0;
			p.SortKey = 0;
			return p;
		}
	}

	/// Creates a sprite proxy with the given parameters.
	public this(uint32 id, Vector3 position, Vector2 size, Color color = .White)
	{
		Id = id;
		Position = position;
		Size = size;
		UVRect = .(0, 0, 1, 1);
		Color = color;
		Texture = null;
		WorldBounds = CalculateBounds(position, size);
		Flags = .Visible;
		LayerMask = 0xFFFFFFFF;
		DistanceToCamera = 0;
		SortKey = 0;
	}

	/// Creates a sprite proxy with UV rect.
	public this(uint32 id, Vector3 position, Vector2 size, Vector4 uvRect, Color color)
	{
		Id = id;
		Position = position;
		Size = size;
		UVRect = uvRect;
		Color = color;
		Texture = null;
		WorldBounds = CalculateBounds(position, size);
		Flags = .Visible;
		LayerMask = 0xFFFFFFFF;
		DistanceToCamera = 0;
		SortKey = 0;
	}

	/// Creates a sprite proxy with texture.
	public this(uint32 id, Vector3 position, Vector2 size, ITextureView texture, Color color = .White)
	{
		Id = id;
		Position = position;
		Size = size;
		UVRect = .(0, 0, 1, 1);
		Color = color;
		Texture = texture;
		WorldBounds = CalculateBounds(position, size);
		Flags = .Visible;
		LayerMask = 0xFFFFFFFF;
		DistanceToCamera = 0;
		SortKey = 0;
	}

	/// Updates position and recalculates bounds.
	public void SetPosition(Vector3 position) mut
	{
		Position = position;
		WorldBounds = CalculateBounds(position, Size);
	}

	/// Updates size and recalculates bounds.
	public void SetSize(Vector2 size) mut
	{
		Size = size;
		WorldBounds = CalculateBounds(Position, size);
	}

	/// Updates position and size together, recalculating bounds once.
	public void SetPositionAndSize(Vector3 position, Vector2 size) mut
	{
		Position = position;
		Size = size;
		WorldBounds = CalculateBounds(position, size);
	}

	/// Calculates a bounding box for a billboard sprite.
	/// The box is axis-aligned and sized for the max extent of the sprite from any viewing angle.
	private static BoundingBox CalculateBounds(Vector3 position, Vector2 size)
	{
		// For a billboard, the sprite can face any direction, so use the max dimension
		float halfW = size.X * 0.5f;
		float halfH = size.Y * 0.5f;
		float maxHalf = Math.Max(halfW, halfH);
		let extent = Vector3(maxHalf, maxHalf, maxHalf);
		return .(position - extent, position + extent);
	}

	/// Converts to SpriteInstance for GPU upload.
	public SpriteInstance ToSpriteInstance()
	{
		return .(Position, Size, UVRect, Color);
	}

	/// Checks if this proxy is valid.
	public bool IsValid => Id != uint32.MaxValue;

	/// Checks if visible.
	public bool IsVisible => Flags.HasFlag(.Visible);

	/// Checks if was culled this frame.
	public bool IsCulled => Flags.HasFlag(.Culled);
}

/// Flags controlling sprite proxy behavior.
enum SpriteProxyFlags : uint16
{
	None = 0,
	/// Sprite is visible for rendering.
	Visible = 1 << 0,
	/// Sprite was culled this frame.
	Culled = 1 << 1,
	/// Sprite is affected by lighting (lit sprites).
	Lit = 1 << 2,
	/// Sprite casts shadows (expensive, rarely used).
	CastsShadows = 1 << 3,
	/// Sprite uses additive blending.
	Additive = 1 << 4,
	/// Sprite is screen-space (not world-space billboard).
	ScreenSpace = 1 << 5
}
