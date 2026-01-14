namespace Sedulous.RendererNext.Resources;

using System;
using Sedulous.Resources;
using Sedulous.Imaging;

/// Texture filtering mode.
enum TextureFilter
{
	Nearest,
	Linear,
	MipmapNearest,
	MipmapLinear
}

/// Texture wrap mode.
enum TextureWrap
{
	Repeat,
	ClampToEdge,
	ClampToBorder,
	MirroredRepeat
}

/// CPU-side texture resource wrapping an Image.
class TextureResource : Resource
{
	private Image mImage;
	private bool mOwnsImage;

	/// The underlying image data.
	public Image Image => mImage;

	/// Min filter mode.
	public TextureFilter MinFilter = .Linear;

	/// Mag filter mode.
	public TextureFilter MagFilter = .Linear;

	/// Wrap mode for U coordinate.
	public TextureWrap WrapU = .Repeat;

	/// Wrap mode for V coordinate.
	public TextureWrap WrapV = .Repeat;

	/// Whether to generate mipmaps.
	public bool GenerateMipmaps = true;

	/// Anisotropic filtering level (1 = disabled).
	public float Anisotropy = 1.0f;

	/// sRGB color space (for color textures).
	public bool IsSRGB = true;

	public this()
	{
		mImage = null;
		mOwnsImage = false;
	}

	public this(Image image, bool ownsImage = false)
	{
		mImage = image;
		mOwnsImage = ownsImage;
	}

	public ~this()
	{
		if (mOwnsImage && mImage != null)
			delete mImage;
	}

	/// Sets the image. Takes ownership if ownsImage is true.
	public void SetImage(Image image, bool ownsImage = false)
	{
		if (mOwnsImage && mImage != null)
			delete mImage;
		mImage = image;
		mOwnsImage = ownsImage;
	}

	/// Image width.
	public uint32 Width => mImage?.Width ?? 0;

	/// Image height.
	public uint32 Height => mImage?.Height ?? 0;

	/// Setup for UI textures (no mipmaps, linear, clamped).
	public void SetupForUI()
	{
		MinFilter = .Linear;
		MagFilter = .Linear;
		WrapU = .ClampToEdge;
		WrapV = .ClampToEdge;
		GenerateMipmaps = false;
		Anisotropy = 1.0f;
		IsSRGB = true;
	}

	/// Setup for sprite textures (nearest, clamped).
	public void SetupForSprite()
	{
		MinFilter = .Nearest;
		MagFilter = .Nearest;
		WrapU = .ClampToEdge;
		WrapV = .ClampToEdge;
		GenerateMipmaps = false;
		Anisotropy = 1.0f;
		IsSRGB = true;
	}

	/// Setup for 3D textures (mipmaps, linear, anisotropic).
	public void SetupFor3D()
	{
		MinFilter = .MipmapLinear;
		MagFilter = .Linear;
		WrapU = .Repeat;
		WrapV = .Repeat;
		GenerateMipmaps = true;
		Anisotropy = 16.0f;
		IsSRGB = true;
	}

	/// Setup for normal maps (linear color space).
	public void SetupForNormalMap()
	{
		MinFilter = .MipmapLinear;
		MagFilter = .Linear;
		WrapU = .Repeat;
		WrapV = .Repeat;
		GenerateMipmaps = true;
		Anisotropy = 16.0f;
		IsSRGB = false;  // Normal maps are in linear space
	}
}
