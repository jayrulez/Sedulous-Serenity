namespace Sedulous.Drawing.Fonts;

using System;
using System.Collections;
using Sedulous.Fonts;
using Sedulous.Fonts.TTF;
using Sedulous.Drawing;
using Sedulous.RHI;

/// Font service implementation that loads fonts, creates atlas textures on the GPU,
/// and provides them to drawing and UI systems via IFontService.
public class FontService : IFontService
{
	private IDevice mDevice;
	private Dictionary<String, FontEntry> mFonts = new .() ~ { for (let kv in _) { delete kv.key; delete kv.value; } delete _; };
	private String mDefaultFontFamily = new .("Default") ~ delete _;
	private CachedFont mDefaultFont;

	/// A loaded font entry with its atlas texture.
	private class FontEntry
	{
		public CachedFont CachedFont;
		public TextureRef Texture ~ delete _;
		public Sedulous.RHI.ITexture GpuTexture ~ delete _;
		public ITextureView GpuTextureView ~ delete _;

		public ~this()
		{
			delete CachedFont;
		}
	}

	public this(IDevice device)
	{
		mDevice = device;
		TrueTypeFonts.Initialize();
	}

	/// The white pixel UV coordinates from the default font atlas.
	/// Use this for DrawContext.WhitePixelUV for solid color rendering.
	public (float U, float V) WhitePixelUV
	{
		get
		{
			if (mDefaultFont != null && mDefaultFont.Atlas != null)
				return mDefaultFont.Atlas.WhitePixelUV;
			return (0, 0);
		}
	}

	/// Gets the atlas texture view for the UI renderer.
	/// Returns the default font's atlas texture view.
	public ITextureView AtlasTextureView
	{
		get
		{
			for (let kv in mFonts)
			{
				if (kv.value.CachedFont == mDefaultFont)
					return kv.value.GpuTextureView;
			}
			return null;
		}
	}

	/// Loads a font from a file path and creates its GPU atlas texture.
	/// The first font loaded becomes the default.
	public Result<void> LoadFont(StringView familyName, StringView filePath, FontLoadOptions options = .ExtendedLatin)
	{
		if (mDevice == null)
			return .Err;

		// Load font
		IFont font;
		if (FontLoaderFactory.LoadFont(filePath, options) case .Ok(let f))
			font = f;
		else
			return .Err;

		// Create atlas
		IFontAtlas atlas;
		if (FontLoaderFactory.CreateAtlas(font, options) case .Ok(let a))
			atlas = a;
		else
		{
			delete (Object)font;
			return .Err;
		}

		// Create GPU texture from atlas data
		let atlasWidth = atlas.Width;
		let atlasHeight = atlas.Height;
		let r8Data = atlas.PixelData;

		// Convert R8 to RGBA8
		let pixelCount = (int)(atlasWidth * atlasHeight);
		uint8[] rgba8Data = new uint8[pixelCount * 4];
		defer delete rgba8Data;

		for (int i = 0; i < pixelCount; i++)
		{
			rgba8Data[i * 4 + 0] = 255;
			rgba8Data[i * 4 + 1] = 255;
			rgba8Data[i * 4 + 2] = 255;
			rgba8Data[i * 4 + 3] = r8Data[i];
		}

		TextureDescriptor textureDesc = TextureDescriptor.Texture2D(
			atlasWidth, atlasHeight, TextureFormat.RGBA8Unorm, TextureUsage.Sampled | TextureUsage.CopyDst
		);

		Sedulous.RHI.ITexture gpuTexture;
		if (mDevice.CreateTexture(&textureDesc) case .Ok(let tex))
			gpuTexture = tex;
		else
		{
			delete (Object)atlas;
			delete (Object)font;
			return .Err;
		}

		TextureDataLayout dataLayout = .()
		{
			Offset = 0,
			BytesPerRow = atlasWidth * 4,
			RowsPerImage = atlasHeight
		};
		Extent3D writeSize = .(atlasWidth, atlasHeight, 1);
		mDevice.Queue.WriteTexture(gpuTexture, Span<uint8>(rgba8Data.Ptr, rgba8Data.Count), &dataLayout, &writeSize);

		TextureViewDescriptor viewDesc = .() { Format = .RGBA8Unorm };
		ITextureView gpuTextureView;
		if (mDevice.CreateTextureView(gpuTexture, &viewDesc) case .Ok(let view))
			gpuTextureView = view;
		else
		{
			delete gpuTexture;
			delete (Object)atlas;
			delete (Object)font;
			return .Err;
		}

		let textureRef = new TextureRef(gpuTexture, atlasWidth, atlasHeight);
		let cachedFont = new CachedFont(font, atlas);

		let entry = new FontEntry();
		entry.CachedFont = cachedFont;
		entry.Texture = textureRef;
		entry.GpuTexture = gpuTexture;
		entry.GpuTextureView = gpuTextureView;

		let key = new String(familyName);
		mFonts[key] = entry;

		// First font becomes the default
		if (mDefaultFont == null)
		{
			mDefaultFont = cachedFont;
			mDefaultFontFamily.Set(familyName);
		}

		return .Ok;
	}

	// ==================== IFontService Implementation ====================

	public StringView DefaultFontFamily => mDefaultFontFamily;

	public CachedFont GetFont(float pixelHeight)
	{
		return mDefaultFont;
	}

	public CachedFont GetFont(StringView familyName, float pixelHeight)
	{
		if (mFonts.TryGetValue(scope String(familyName), let entry))
			return entry.CachedFont;
		return mDefaultFont;
	}

	public Sedulous.Drawing.ITexture GetAtlasTexture(CachedFont font)
	{
		for (let kv in mFonts)
		{
			if (kv.value.CachedFont == font)
				return kv.value.Texture;
		}
		return null;
	}

	public Sedulous.Drawing.ITexture GetAtlasTexture(StringView familyName, float pixelHeight)
	{
		if (mFonts.TryGetValue(scope String(familyName), let entry))
			return entry.Texture;

		// Fall back to default
		for (let kv in mFonts)
		{
			if (kv.value.CachedFont == mDefaultFont)
				return kv.value.Texture;
		}
		return null;
	}

	public void ReleaseFont(CachedFont font)
	{
		// Fonts are managed by this service - no-op
	}
}
