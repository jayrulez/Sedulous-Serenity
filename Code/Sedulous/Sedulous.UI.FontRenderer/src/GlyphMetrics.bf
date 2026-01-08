using System;
using Sedulous.Mathematics;

namespace Sedulous.UI.FontRenderer;

/// Metrics for a single glyph.
struct GlyphMetrics
{
	/// The unicode codepoint.
	public int32 Codepoint;

	/// The glyph index in the font.
	public int32 GlyphIndex;

	/// Horizontal advance width in pixels.
	public float AdvanceWidth;

	/// Left side bearing (offset from current position to left edge).
	public float LeftSideBearing;

	/// Bounding box in local coordinates.
	public RectangleF Bounds;

	/// Position in the font atlas (UV coordinates 0-1).
	public RectangleF AtlasRect;

	/// Which atlas page this glyph is on.
	public int32 AtlasIndex;

	/// The pixel size this glyph was rendered at.
	public float Size;

	/// Whether this glyph is valid/loaded.
	public bool IsValid;

	/// Creates empty glyph metrics.
	public this()
	{
		Codepoint = 0;
		GlyphIndex = 0;
		AdvanceWidth = 0;
		LeftSideBearing = 0;
		Bounds = .Empty;
		AtlasRect = .Empty;
		AtlasIndex = -1;
		Size = 0;
		IsValid = false;
	}

	/// Creates glyph metrics with the given values.
	public this(int32 codepoint, int32 glyphIndex, float advanceWidth, float leftSideBearing,
		RectangleF bounds, RectangleF atlasRect, int32 atlasIndex, float size)
	{
		Codepoint = codepoint;
		GlyphIndex = glyphIndex;
		AdvanceWidth = advanceWidth;
		LeftSideBearing = leftSideBearing;
		Bounds = bounds;
		AtlasRect = atlasRect;
		AtlasIndex = atlasIndex;
		Size = size;
		IsValid = true;
	}
}
