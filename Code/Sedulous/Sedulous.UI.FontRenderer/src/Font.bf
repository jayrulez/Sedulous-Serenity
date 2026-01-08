using System;
using System.Collections;
using Sedulous.Mathematics;
using stb_truetype;

namespace Sedulous.UI.FontRenderer;

/// Loaded font with glyph caching.
class Font
{
	/// Cache key for size-specific glyph data.
	private struct GlyphKey : IHashable
	{
		public int32 Codepoint;
		public int32 SizeHash; // Hash of the float size

		public this(int32 codepoint, float size)
		{
			Codepoint = codepoint;
			// Use integer representation for reliable hashing
			SizeHash = (int32)(size * 100);
		}

		public int GetHashCode()
		{
			return Codepoint ^ (SizeHash << 16);
		}
	}

	private String mName ~ delete _;
	private String mPath ~ delete _;
	private uint8[] mFontData ~ delete _;
	private stbtt_fontinfo mFontInfo;
	private bool mIsValid;

	// Font metrics (in unscaled units)
	private int32 mAscent;
	private int32 mDescent;
	private int32 mLineGap;

	// Glyph cache
	private Dictionary<GlyphKey, GlyphMetrics> mGlyphCache = new .() ~ delete _;

	// Atlas per size (or shared atlas)
	private FontAtlas mAtlas ~ delete _;

	/// Creates an empty font.
	public this()
	{
		mFontInfo = .();
		mIsValid = false;
	}

	/// Creates a font from raw data.
	public this(Span<uint8> data, StringView name)
	{
		mName = new String(name);
		mPath = new String();
		mFontData = new uint8[data.Length];
		Internal.MemCpy(mFontData.Ptr, data.Ptr, data.Length);

		mFontInfo = .();
		mIsValid = InitFont();

		// Create default atlas
		mAtlas = new FontAtlas(1024, 1024);
	}

	/// Gets the font name.
	public StringView Name => mName ?? "";

	/// Gets the font file path.
	public StringView Path => mPath ?? "";

	/// Gets whether the font is valid.
	public bool IsValid => mIsValid;

	/// Gets the ascent (distance above baseline) at scale 1.
	public float Ascent => (float)mAscent;

	/// Gets the descent (distance below baseline, typically negative) at scale 1.
	public float Descent => (float)mDescent;

	/// Gets the line gap at scale 1.
	public float LineGap => (float)mLineGap;

	/// Gets the font atlas.
	public FontAtlas Atlas => mAtlas;

	/// Gets the line height for a given pixel size.
	public float GetLineHeight(float size)
	{
		let scale = GetScaleForPixelHeight(size);
		return (float)(mAscent - mDescent + mLineGap) * scale;
	}

	/// Gets the ascent for a given pixel size.
	public float GetScaledAscent(float size)
	{
		let scale = GetScaleForPixelHeight(size);
		return (float)mAscent * scale;
	}

	/// Gets the descent for a given pixel size.
	public float GetScaledDescent(float size)
	{
		let scale = GetScaleForPixelHeight(size);
		return (float)mDescent * scale;
	}

	/// Gets a glyph's metrics, loading it if necessary.
	public GlyphMetrics GetGlyph(int32 codepoint, float size)
	{
		if (!mIsValid)
			return GlyphMetrics();

		let key = GlyphKey(codepoint, size);

		// Check cache
		if (mGlyphCache.TryGetValue(key, let cached))
			return cached;

		// Load the glyph
		let glyph = LoadGlyph(codepoint, size);
		mGlyphCache[key] = glyph;
		return glyph;
	}

	/// Gets kerning between two characters.
	public float GetKerning(int32 left, int32 right, float size)
	{
		if (!mIsValid)
			return 0;

		let scale = GetScaleForPixelHeight(size);
		let kern = stbtt_GetCodepointKernAdvance(&mFontInfo, left, right);
		return (float)kern * scale;
	}

	/// Measures text size.
	public Vector2 MeasureText(StringView text, float size)
	{
		if (!mIsValid || text.IsEmpty)
			return .Zero;

		let scale = GetScaleForPixelHeight(size);
		float width = 0;
		float maxWidth = 0;
		int lineCount = 1;
		int32 prevCodepoint = 0;

		for (let char in text.DecodedChars)
		{
			let codepoint = (int32)char;

			if (codepoint == (int32)'\n')
			{
				maxWidth = Math.Max(maxWidth, width);
				width = 0;
				lineCount++;
				prevCodepoint = 0;
				continue;
			}

			// Add kerning
			if (prevCodepoint != 0)
			{
				let kern = stbtt_GetCodepointKernAdvance(&mFontInfo, prevCodepoint, codepoint);
				width += (float)kern * scale;
			}

			// Get advance
			int32 advance = 0;
			int32 lsb = 0;
			stbtt_GetCodepointHMetrics(&mFontInfo, codepoint, &advance, &lsb);
			width += (float)advance * scale;

			prevCodepoint = codepoint;
		}

		maxWidth = Math.Max(maxWidth, width);
		let height = GetLineHeight(size) * lineCount;

		return Vector2(maxWidth, height);
	}

	/// Measures text with wrapping.
	public Vector2 MeasureText(StringView text, float size, float maxWidth, out int lineCount)
	{
		lineCount = 1;

		if (!mIsValid || text.IsEmpty)
			return .Zero;

		let scale = GetScaleForPixelHeight(size);
		float measuredMaxWidth = 0;
		int32 prevCodepoint = 0;
		float lineWidth = 0;

		for (int i = 0; i < text.Length;)
		{
			let (codepoint32, charLen) = text.GetChar32(i);
			let codepoint = (int32)codepoint32;

			if (codepoint == (int32)'\n')
			{
				measuredMaxWidth = Math.Max(measuredMaxWidth, lineWidth);
				lineWidth = 0;
				lineCount++;
				prevCodepoint = 0;
				i += charLen;
				continue;
			}

			// Calculate character width
			float charWidth = 0;
			if (prevCodepoint != 0)
			{
				let kern = stbtt_GetCodepointKernAdvance(&mFontInfo, prevCodepoint, codepoint);
				charWidth += (float)kern * scale;
			}

			int32 advance = 0;
			int32 lsb = 0;
			stbtt_GetCodepointHMetrics(&mFontInfo, codepoint, &advance, &lsb);
			charWidth += (float)advance * scale;

			// Check for wrap
			if (lineWidth + charWidth > maxWidth && lineWidth > 0)
			{
				measuredMaxWidth = Math.Max(measuredMaxWidth, lineWidth);
				lineWidth = 0;
				lineCount++;
				prevCodepoint = 0;
			}

			lineWidth += charWidth;
			prevCodepoint = codepoint;
			i += charLen;
		}

		measuredMaxWidth = Math.Max(measuredMaxWidth, lineWidth);
		let height = GetLineHeight(size) * lineCount;

		return Vector2(measuredMaxWidth, height);
	}

	/// Preloads ASCII glyphs (32-126) at the given size.
	public void PreloadASCII(float size)
	{
		for (int32 c = 32; c <= 126; c++)
		{
			GetGlyph(c, size);
		}
	}

	/// Preloads a range of codepoints at the given size.
	public void PreloadRange(float size, int32 start, int32 end)
	{
		for (int32 c = start; c <= end; c++)
		{
			GetGlyph(c, size);
		}
	}

	/// Initializes the font from loaded data.
	private bool InitFont()
	{
		if (mFontData == null || mFontData.Count == 0)
			return false;

		let offset = stbtt_GetFontOffsetForIndex(mFontData.Ptr, 0);
		if (offset < 0)
			return false;

		if (stbtt_InitFont(&mFontInfo, mFontData.Ptr, offset) == 0)
			return false;

		// Get font metrics
		stbtt_GetFontVMetrics(&mFontInfo, &mAscent, &mDescent, &mLineGap);

		return true;
	}

	/// Gets the scale factor for a given pixel height.
	private float GetScaleForPixelHeight(float pixels)
	{
		return stbtt_ScaleForPixelHeight(&mFontInfo, pixels);
	}

	/// Loads a glyph and adds it to the atlas.
	private GlyphMetrics LoadGlyph(int32 codepoint, float size)
	{
		let scale = GetScaleForPixelHeight(size);
		let glyphIndex = stbtt_FindGlyphIndex(&mFontInfo, codepoint);

		if (glyphIndex == 0 && codepoint != 0)
		{
			// Glyph not found, return empty
			return GlyphMetrics();
		}

		// Get metrics
		int32 advance = 0;
		int32 lsb = 0;
		stbtt_GetGlyphHMetrics(&mFontInfo, glyphIndex, &advance, &lsb);

		// Get bitmap box
		int32 x0 = 0, y0 = 0, x1 = 0, y1 = 0;
		stbtt_GetGlyphBitmapBox(&mFontInfo, glyphIndex, scale, scale, &x0, &y0, &x1, &y1);

		let width = x1 - x0;
		let height = y1 - y0;

		if (width <= 0 || height <= 0)
		{
			// Empty glyph (like space)
			return GlyphMetrics(
				codepoint,
				glyphIndex,
				(float)advance * scale,
				(float)lsb * scale,
				RectangleF((float)x0, (float)y0, (float)width, (float)height),
				.Empty,
				0,
				size
			);
		}

		// Pack into atlas
		let atlasRect = mAtlas.Pack((uint32)width, (uint32)height);
		if (atlasRect.IsEmpty)
		{
			// Atlas full - could expand or create new atlas
			return GlyphMetrics();
		}

		// Render glyph
		let atlasX = (int32)(atlasRect.X * mAtlas.Width);
		let atlasY = (int32)(atlasRect.Y * mAtlas.Height);

		var bitmapData = scope uint8[width * height];
		stbtt_MakeGlyphBitmap(&mFontInfo, bitmapData.Ptr, width, height, width, scale, scale, glyphIndex);

		// Copy to atlas
		mAtlas.SetRegion(atlasX, atlasY, width, height, bitmapData.Ptr, width);

		return GlyphMetrics(
			codepoint,
			glyphIndex,
			(float)advance * scale,
			(float)lsb * scale,
			RectangleF((float)x0, (float)y0, (float)width, (float)height),
			atlasRect,
			0,
			size
		);
	}
}
