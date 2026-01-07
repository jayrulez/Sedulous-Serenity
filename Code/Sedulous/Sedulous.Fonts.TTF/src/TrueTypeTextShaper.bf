using System;
using System.Collections;
using Sedulous.Fonts;

namespace Sedulous.Fonts.TTF;

/// Basic text shaper for TrueType fonts
public class TrueTypeTextShaper : ITextShaper
{
	public Result<float> ShapeText(IFont font, StringView text, List<GlyphPosition> outPositions)
	{
		return ShapeText(font, text, 0, 0, outPositions);
	}

	public Result<float> ShapeText(IFont font, StringView text, float startX, float startY, List<GlyphPosition> outPositions)
	{
		outPositions.Clear();

		float x = startX;
		int32 prevCodepoint = 0;
		int32 index = 0;

		for (let c in text.DecodedChars)
		{
			let codepoint = (int32)c;
			let glyphInfo = font.GetGlyphInfo(codepoint);

			// Apply kerning
			if (prevCodepoint != 0)
				x += font.GetKerning(prevCodepoint, codepoint);

			GlyphPosition pos = .(index, codepoint, x, startY, glyphInfo.AdvanceWidth, glyphInfo);
			outPositions.Add(pos);

			x += glyphInfo.AdvanceWidth;
			prevCodepoint = codepoint;
			index++;
		}

		return .Ok(x - startX);
	}

	public Result<void> ShapeTextWrapped(IFont font, StringView text, float maxWidth, List<GlyphPosition> outPositions, out float totalHeight)
	{
		outPositions.Clear();
		totalHeight = 0;

		let lineHeight = font.Metrics.LineHeight;
		float x = 0;
		float y = 0;
		int32 prevCodepoint = 0;
		int32 index = 0;
		int32 lineStartIdx = 0;
		int32 lastSpaceIdx = -1;
		float xAtLastSpace = 0;

		for (let c in text.DecodedChars)
		{
			let codepoint = (int32)c;

			// Handle explicit newlines
			if (codepoint == (int32)'\n')
			{
				y += lineHeight;
				x = 0;
				prevCodepoint = 0;
				lineStartIdx = index + 1;
				lastSpaceIdx = -1;
				index++;
				continue;
			}

			// Skip carriage return
			if (codepoint == (int32)'\r')
			{
				index++;
				continue;
			}

			let glyphInfo = font.GetGlyphInfo(codepoint);

			// Apply kerning
			float kern = 0;
			if (prevCodepoint != 0)
				kern = font.GetKerning(prevCodepoint, codepoint);

			float newX = x + kern + glyphInfo.AdvanceWidth;

			// Track spaces for word wrapping
			if (codepoint == (int32)' ')
			{
				lastSpaceIdx = (int32)outPositions.Count;
				xAtLastSpace = x + kern;
			}

			// Check if we need to wrap
			if (newX > maxWidth && x > 0)
			{
				if (lastSpaceIdx >= lineStartIdx && lastSpaceIdx >= 0)
				{
					// Wrap at last space - reflow glyphs after the space
					y += lineHeight;
					float reflowX = 0;

					for (int32 i = lastSpaceIdx + 1; i < outPositions.Count; i++)
					{
						var pos = ref outPositions[i];
						pos.X = reflowX;
						pos.Y = y;
						reflowX += pos.Advance;
					}

					x = reflowX + kern;
					lineStartIdx = lastSpaceIdx + 1;
				}
				else
				{
					// No space to break at - hard wrap
					y += lineHeight;
					x = 0;
					kern = 0;
					lineStartIdx = index;
				}
				lastSpaceIdx = -1;
			}

			// Add glyph position
			GlyphPosition pos = .(index, codepoint, x + kern, y, glyphInfo.AdvanceWidth, glyphInfo);
			outPositions.Add(pos);

			x = x + kern + glyphInfo.AdvanceWidth;
			prevCodepoint = codepoint;
			index++;
		}

		totalHeight = y + lineHeight;
		return .Ok;
	}
}
