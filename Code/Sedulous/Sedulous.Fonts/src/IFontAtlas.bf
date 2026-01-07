using System;
using Sedulous.Imaging;

namespace Sedulous.Fonts;

/// Interface for a font atlas (texture containing pre-rendered glyphs)
public interface IFontAtlas
{
	/// Width of the atlas texture in pixels
	uint32 Width { get; }

	/// Height of the atlas texture in pixels
	uint32 Height { get; }

	/// Raw pixel data (single channel, 8-bit grayscale)
	Span<uint8> PixelData { get; }

	/// Get the atlas region for a specific codepoint
	/// Returns false if codepoint not in atlas
	bool TryGetRegion(int32 codepoint, out AtlasRegion region);

	/// Get quad for rendering a character at the given position
	/// Updates cursorX to the position for the next character
	bool GetGlyphQuad(int32 codepoint, ref float cursorX, float cursorY, out GlyphQuad quad);

	/// Check if atlas contains a specific codepoint
	bool Contains(int32 codepoint);

	/// Convert atlas to an Image for GPU upload
	Image ToImage();
}
