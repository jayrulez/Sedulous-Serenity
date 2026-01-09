using System;
using System.IO;
using Sedulous.Resources;
using Sedulous.Imaging;

namespace Sedulous.Engine.Renderer;

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
	public const int32 FileVersion = 1;
	public const int32 FileType = 8; // ResourceFileType.Texture
	private const uint32 TextureMagic = 0x54455854; // "TEXT"

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

	// ---- Serialization (Binary format) ----

	/// Save this texture resource to a binary file.
	public Result<void> SaveToFile(StringView path)
	{
		if (mImage == null)
			return .Err;

		let stream = scope FileStream();

		if (stream.Create(path, .Write) case .Err)
			return .Err;

		// Write header
		stream.Write(TextureMagic);
		stream.Write((int32)FileVersion);
		stream.Write((int32)FileType);

		// Write name
		int32 nameLen = (int32)Name.Length;
		stream.Write(nameLen);
		if (nameLen > 0)
			stream.TryWrite(.((uint8*)Name.Ptr, nameLen));

		// Write image properties
		stream.Write((uint32)mImage.Width);
		stream.Write((uint32)mImage.Height);
		stream.Write((int32)mImage.Format);

		// Write texture settings
		stream.Write((int32)MinFilter);
		stream.Write((int32)MagFilter);
		stream.Write((int32)WrapU);
		stream.Write((int32)WrapV);
		stream.Write((int32)WrapW);
		stream.Write(GenerateMipmaps ? (uint8)1 : (uint8)0);
		stream.Write(Anisotropy);

		// Write pixel data
		let data = mImage.Data;
		stream.Write((int32)data.Length);
		stream.TryWrite(data);

		stream.Close();
		return .Ok;
	}

	/// Load a texture resource from a binary file.
	public static Result<TextureResource> LoadFromFile(StringView path)
	{
		let stream = scope FileStream();

		if (stream.Open(path, .Read) case .Err)
			return .Err;

		// Read and verify header
		uint32 magic = ReadUInt32(stream);
		if (magic != TextureMagic)
			return .Err;

		int32 version = ReadInt32(stream);
		if (version > FileVersion)
			return .Err;

		int32 fileType = ReadInt32(stream);
		if (fileType != FileType)
			return .Err;

		// Read name
		int32 nameLen = ReadInt32(stream);
		String name = scope String();
		if (nameLen > 0)
		{
			let nameBytes = scope uint8[nameLen];
			stream.TryRead(nameBytes);
			name.Append((char8*)nameBytes.Ptr, nameLen);
		}

		// Read image properties
		uint32 width = ReadUInt32(stream);
		uint32 height = ReadUInt32(stream);
		int32 formatInt = ReadInt32(stream);
		let format = (Image.PixelFormat)formatInt;

		// Read texture settings
		int32 minFilter = ReadInt32(stream);
		int32 magFilter = ReadInt32(stream);
		int32 wrapU = ReadInt32(stream);
		int32 wrapV = ReadInt32(stream);
		int32 wrapW = ReadInt32(stream);
		uint8 generateMipmaps = ReadUInt8(stream);
		float anisotropy = ReadFloat(stream);

		// Read pixel data
		int32 dataLen = ReadInt32(stream);

		let data = new uint8[dataLen];
		stream.TryRead(data);

		// Create image and resource
		let image = new Image(width, height, format, data);
		delete data;

		let resource = new TextureResource(image, true);
		resource.Name.Set(name);
		resource.MinFilter = (TextureFilter)minFilter;
		resource.MagFilter = (TextureFilter)magFilter;
		resource.WrapU = (TextureWrap)wrapU;
		resource.WrapV = (TextureWrap)wrapV;
		resource.WrapW = (TextureWrap)wrapW;
		resource.GenerateMipmaps = generateMipmaps != 0;
		resource.Anisotropy = anisotropy;

		stream.Close();
		return .Ok(resource);
	}

	// Binary read helpers
	private static uint8 ReadUInt8(Stream stream)
	{
		uint8[1] buf = default;
		stream.TryRead(buf);
		return buf[0];
	}

	private static int32 ReadInt32(Stream stream)
	{
		uint8[4] buf = default;
		stream.TryRead(buf);
		return (int32)buf[0] | ((int32)buf[1] << 8) | ((int32)buf[2] << 16) | ((int32)buf[3] << 24);
	}

	private static uint32 ReadUInt32(Stream stream)
	{
		uint8[4] buf = default;
		stream.TryRead(buf);
		return (uint32)buf[0] | ((uint32)buf[1] << 8) | ((uint32)buf[2] << 16) | ((uint32)buf[3] << 24);
	}

	private static float ReadFloat(Stream stream)
	{
		uint8[4] buf = default;
		stream.TryRead(buf);
		uint32 bits = (uint32)buf[0] | ((uint32)buf[1] << 8) | ((uint32)buf[2] << 16) | ((uint32)buf[3] << 24);
		return *(float*)&bits;
	}
}
