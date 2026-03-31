namespace Sedulous.Renderer;

using System;
using Sedulous.RHI;

/// GPU-side texture data.
public class GPUTexture
{
	/// The texture.
	public ITexture Texture;
	/// Default view.
	public ITextureView DefaultView;
	/// Width.
	public uint32 Width;
	/// Height.
	public uint32 Height;
	/// Array layer count (6 for cubemaps, 1 for non-array textures).
	public uint32 ArrayLayerCount;
	/// Mip levels.
	public uint32 MipLevels;
	/// Format.
	public TextureFormat Format;
	/// Reference count.
	public int32 RefCount;
	/// Generation for handle validation.
	public uint32 Generation;
	/// Whether this slot is in use.
	public bool IsActive;

	/// Frees GPU resources.
	public void Release(IDevice device)
	{
		if (DefaultView != null)
			device.DestroyTextureView(ref DefaultView);
		if (Texture != null)
			device.DestroyTexture(ref Texture);
		IsActive = false;
	}
}
