using System;
using System.Collections;

namespace Sedulous.Fonts;

/// Text shaping and layout interface
public interface ITextShaper
{
	/// Shape text and output positioned glyphs
	/// Returns total width of shaped text
	Result<float> ShapeText(IFont font, StringView text, List<GlyphPosition> outPositions);

	/// Shape text with explicit starting position
	Result<float> ShapeText(IFont font, StringView text, float startX, float startY, List<GlyphPosition> outPositions);

	/// Shape multi-line text with word wrapping
	Result<void> ShapeTextWrapped(IFont font, StringView text, float maxWidth, List<GlyphPosition> outPositions, out float totalHeight);
}

/// Horizontal text alignment options
public enum TextAlignment
{
	Left,
	Center,
	Right
}

/// Vertical text alignment options
public enum VerticalAlignment
{
	Top,
	Middle,
	Bottom,
	Baseline
}
