using System;
using System.Collections;
using Sedulous.Mathematics;

namespace Sedulous.UI.FontRenderer;

/// Shaped glyph ready for rendering.
struct ShapedGlyph
{
	/// The unicode codepoint.
	public int32 Codepoint;

	/// Position to render the glyph (top-left of bounds).
	public Vector2 Position;

	/// Size of the glyph in pixels.
	public Vector2 Size;

	/// UV rectangle in the atlas (0-1 range).
	public RectangleF AtlasRect;

	/// Which atlas page this glyph is on.
	public int32 AtlasIndex;

	/// Line index (0-based).
	public int32 Line;
}

/// Text shaper for complex text layout.
class TextShaper
{
	private Font mFont;

	/// Creates a text shaper for the specified font.
	public this(Font font)
	{
		mFont = font;
	}

	/// Gets/sets the font used for shaping.
	public Font Font
	{
		get => mFont;
		set => mFont = value;
	}

	/// Shapes text into renderable glyphs.
	public void Shape(StringView text, float size, List<ShapedGlyph> outGlyphs)
	{
		outGlyphs.Clear();

		if (mFont == null || !mFont.IsValid || text.IsEmpty)
			return;

		float x = 0;
		float y = mFont.GetScaledAscent(size);
		int32 prevCodepoint = 0;
		int32 line = 0;

		for (let char in text.DecodedChars)
		{
			let codepoint = (int32)char;

			if (codepoint == (int32)'\n')
			{
				x = 0;
				y += mFont.GetLineHeight(size);
				line++;
				prevCodepoint = 0;
				continue;
			}

			if (codepoint == (int32)'\r')
			{
				prevCodepoint = 0;
				continue;
			}

			// Add kerning
			if (prevCodepoint != 0)
			{
				x += mFont.GetKerning(prevCodepoint, codepoint, size);
			}

			// Get glyph metrics
			let glyph = mFont.GetGlyph(codepoint, size);

			if (glyph.IsValid)
			{
				// Only add visible glyphs (non-empty bounds)
				if (!glyph.AtlasRect.IsEmpty)
				{
					var shaped = ShapedGlyph();
					shaped.Codepoint = codepoint;
					shaped.Position = Vector2(
						x + glyph.Bounds.X,
						y + glyph.Bounds.Y
					);
					shaped.Size = Vector2(glyph.Bounds.Width, glyph.Bounds.Height);
					shaped.AtlasRect = glyph.AtlasRect;
					shaped.AtlasIndex = glyph.AtlasIndex;
					shaped.Line = line;
					outGlyphs.Add(shaped);
				}

				x += glyph.AdvanceWidth;
			}

			prevCodepoint = codepoint;
		}
	}

	/// Shapes text with word wrapping.
	public void ShapeWrapped(StringView text, float size, float maxWidth, List<ShapedGlyph> outGlyphs)
	{
		outGlyphs.Clear();

		if (mFont == null || !mFont.IsValid || text.IsEmpty || maxWidth <= 0)
			return;

		float x = 0;
		float y = mFont.GetScaledAscent(size);
		int32 prevCodepoint = 0;
		int32 line = 0;

		// Track word boundaries for wrapping
		float wordStartX = 0;
		int lastSpaceGlyphIndex = -1;
		float lastSpaceX = 0;

		for (int i = 0; i < text.Length;)
		{
			let (codepoint32, charLen) = text.GetChar32(i);
			let codepoint = (int32)codepoint32;

			if (codepoint == (int32)'\n')
			{
				x = 0;
				y += mFont.GetLineHeight(size);
				line++;
				prevCodepoint = 0;
				wordStartX = 0;
				lastSpaceGlyphIndex = -1;
				i += charLen;
				continue;
			}

			if (codepoint == (int32)'\r')
			{
				prevCodepoint = 0;
				i += charLen;
				continue;
			}

			// Track word boundaries
			let isSpace = codepoint == (int32)' ' || codepoint == (int32)'\t';
			if (isSpace)
			{
				lastSpaceGlyphIndex = outGlyphs.Count;
				lastSpaceX = x;
			}

			// Calculate advance
			float advance = 0;
			if (prevCodepoint != 0)
			{
				advance += mFont.GetKerning(prevCodepoint, codepoint, size);
			}

			let glyph = mFont.GetGlyph(codepoint, size);
			if (glyph.IsValid)
			{
				advance += glyph.AdvanceWidth;
			}

			// Check for wrap
			if (x + advance > maxWidth && x > 0)
			{
				// Need to wrap
				if (lastSpaceGlyphIndex >= 0 && !isSpace)
				{
					// Wrap at last space - move glyphs after space to new line
					float offsetX = lastSpaceX;
					for (int j = lastSpaceGlyphIndex; j < outGlyphs.Count; j++)
					{
						var g = outGlyphs[j];
						g.Position.X -= offsetX;
						g.Position.Y += mFont.GetLineHeight(size);
						g.Line++;
						outGlyphs[j] = g;
					}
					x = x - offsetX;
				}
				else
				{
					// Wrap at current position
					x = 0;
				}

				y += mFont.GetLineHeight(size);
				line++;
				lastSpaceGlyphIndex = -1;
				lastSpaceX = 0;
				wordStartX = 0;
			}

			// Add kerning for current position
			if (prevCodepoint != 0)
			{
				x += mFont.GetKerning(prevCodepoint, codepoint, size);
			}

			// Add glyph
			if (glyph.IsValid && !glyph.AtlasRect.IsEmpty)
			{
				var shaped = ShapedGlyph();
				shaped.Codepoint = codepoint;
				shaped.Position = Vector2(
					x + glyph.Bounds.X,
					y + glyph.Bounds.Y
				);
				shaped.Size = Vector2(glyph.Bounds.Width, glyph.Bounds.Height);
				shaped.AtlasRect = glyph.AtlasRect;
				shaped.AtlasIndex = glyph.AtlasIndex;
				shaped.Line = line;
				outGlyphs.Add(shaped);
			}

			if (glyph.IsValid)
			{
				x += glyph.AdvanceWidth;
			}

			prevCodepoint = codepoint;
			i += charLen;
		}
	}

	/// Gets the bounds of shaped text.
	public static RectangleF GetBounds(List<ShapedGlyph> glyphs)
	{
		if (glyphs.Count == 0)
			return .Empty;

		float minX = float.MaxValue;
		float minY = float.MaxValue;
		float maxX = float.MinValue;
		float maxY = float.MinValue;

		for (let glyph in glyphs)
		{
			minX = Math.Min(minX, glyph.Position.X);
			minY = Math.Min(minY, glyph.Position.Y);
			maxX = Math.Max(maxX, glyph.Position.X + glyph.Size.X);
			maxY = Math.Max(maxY, glyph.Position.Y + glyph.Size.Y);
		}

		return RectangleF(minX, minY, maxX - minX, maxY - minY);
	}

	/// Offsets all shaped glyphs by the given amount.
	public static void Offset(List<ShapedGlyph> glyphs, Vector2 offset)
	{
		for (int i = 0; i < glyphs.Count; i++)
		{
			var g = glyphs[i];
			g.Position.X += offset.X;
			g.Position.Y += offset.Y;
			glyphs[i] = g;
		}
	}
}
