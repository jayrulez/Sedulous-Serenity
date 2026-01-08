using System;
using System.IO;
using System.Collections;

namespace Sedulous.UI.FontRenderer;

/// Manages font loading and caching.
class FontManager
{
	private List<Font> mFonts = new .() ~ DeleteContainerAndItems!(_);
	private uint32 mAtlasWidth = 1024;
	private uint32 mAtlasHeight = 1024;
	private Font mDefaultFont;

	/// Creates a font manager.
	public this()
	{
	}

	/// Gets the default font (first loaded font).
	public Font DefaultFont => mDefaultFont;

	/// Gets all loaded fonts.
	public List<Font> Fonts => mFonts;

	/// Sets the atlas size for newly loaded fonts.
	public void SetAtlasSize(uint32 width, uint32 height)
	{
		mAtlasWidth = width;
		mAtlasHeight = height;
	}

	/// Loads a font from a file.
	public Result<Font> LoadFont(StringView path)
	{
		// Open file
		let stream = scope FileStream();
		if (stream.Open(path, .Read) case .Err)
			return .Err;

		// Read all bytes
		let fileSize = stream.Length;
		var data = new uint8[fileSize];
		defer delete data;

		if (stream.TryRead(data) case .Err)
			return .Err;

		// Extract filename for name
		var name = scope String();
		Path.GetFileNameWithoutExtension(path, name);

		let font = new Font(data, name);
		if (!font.IsValid)
		{
			delete font;
			return .Err;
		}

		mFonts.Add(font);

		if (mDefaultFont == null)
			mDefaultFont = font;

		return .Ok(font);
	}

	/// Loads a font from memory.
	public Result<Font> LoadFontFromMemory(Span<uint8> data, StringView name)
	{
		let font = new Font(data, name);
		if (!font.IsValid)
		{
			delete font;
			return .Err;
		}

		mFonts.Add(font);

		if (mDefaultFont == null)
			mDefaultFont = font;

		return .Ok(font);
	}

	/// Unloads a font.
	public void UnloadFont(Font font)
	{
		if (font == null)
			return;

		if (mFonts.Remove(font))
		{
			if (mDefaultFont == font)
				mDefaultFont = mFonts.Count > 0 ? mFonts[0] : null;

			delete font;
		}
	}

	/// Gets a font by name.
	public Font GetFont(StringView name)
	{
		for (let font in mFonts)
		{
			if (font.Name == name)
				return font;
		}
		return null;
	}

	/// Preloads ASCII glyphs for all fonts at the given size.
	public void PreloadASCII(float size)
	{
		for (let font in mFonts)
		{
			font.PreloadASCII(size);
		}
	}

	/// Preloads ASCII glyphs for a specific font at the given size.
	public void PreloadASCII(Font font, float size)
	{
		font?.PreloadASCII(size);
	}

	/// Preloads a range of codepoints for a specific font.
	public void PreloadRange(Font font, float size, int32 start, int32 end)
	{
		font?.PreloadRange(size, start, end);
	}
}
