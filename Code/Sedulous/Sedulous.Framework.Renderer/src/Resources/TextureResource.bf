using System;
using Sedulous.Resources;
using Sedulous.Imaging;

namespace Sedulous.Framework.Renderer;

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

	/// Wrap mode for W coordinate.
	public TextureWrap WrapW = .Repeat;

	/// Whether to generate mipmaps.
	public bool GenerateMipmaps = true;

	/// Anisotropic filtering level.
	public float Anisotropy = 1.0f;

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

	/// Setup for UI textures (no mipmaps, linear, clamped).
	public void SetupForUI()
	{
		MinFilter = .Linear;
		MagFilter = .Linear;
		WrapU = .ClampToEdge;
		WrapV = .ClampToEdge;
		GenerateMipmaps = false;
		Anisotropy = 1.0f;
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
	}

	/// Setup for skybox (clamped, no mipmaps).
	public void SetupForSkybox()
	{
		MinFilter = .Linear;
		MagFilter = .Linear;
		WrapU = .ClampToEdge;
		WrapV = .ClampToEdge;
		WrapW = .ClampToEdge;
		GenerateMipmaps = false;
		Anisotropy = 1.0f;
	}
}
