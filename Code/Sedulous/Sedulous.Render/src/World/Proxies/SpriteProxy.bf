namespace Sedulous.Render;

using Sedulous.Mathematics;
using Sedulous.RHI;

/// Proxy for a sprite in the render world.
public struct SpriteProxy
{
	/// World-space position.
	public Vector3 Position;

	/// Billboard size (width, height).
	public Vector2 Size;

	/// Tint color.
	public Color Color;

	/// Texture for this sprite.
	public ITextureView Texture;

	/// UV rect for atlas sub-region (minU, minV, maxU, maxV).
	/// Default: (0, 0, 1, 1) = full texture.
	public Vector4 UVRect;

	/// Whether the sprite is active.
	public bool IsActive;

	/// Generation counter for handle validation.
	public uint32 Generation;

	/// Render layer mask.
	public uint32 LayerMask;

	/// Creates a default sprite proxy.
	public static Self CreateDefault()
	{
		var sprite = Self();
		sprite.Position = .Zero;
		sprite.Size = .(1, 1);
		sprite.Color = .(1.0f, 1.0f, 1.0f, 1.0f);
		sprite.Texture = null;
		sprite.UVRect = .(0, 0, 1, 1);
		sprite.IsActive = true;
		sprite.LayerMask = 0xFFFFFFFF;
		return sprite;
	}

	/// Resets the proxy for reuse.
	public void Reset() mut
	{
		Position = .Zero;
		Size = .(1, 1);
		Color = .(1.0f, 1.0f, 1.0f, 1.0f);
		Texture = null;
		UVRect = .(0, 0, 1, 1);
		IsActive = false;
		Generation = 0;
		LayerMask = 0xFFFFFFFF;
	}
}
