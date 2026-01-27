using System;
using Sedulous.Fonts;

namespace Sedulous.Drawing;

/// A minimal font service implementation that returns null for all fonts.
/// Use this for testing DrawContext when actual fonts aren't needed.
/// The WhitePixelUV defaults to (0, 0) which works for solid color rendering
/// when the texture's top-left corner is white (common for test textures).
public class NullFontService : IFontService
{
	private float mWhitePixelU;
	private float mWhitePixelV;

	/// Creates a NullFontService with default WhitePixelUV of (0, 0).
	public this()
	{
		mWhitePixelU = 0;
		mWhitePixelV = 0;
	}

	/// Creates a NullFontService with the specified WhitePixelUV.
	public this(float whiteU, float whiteV)
	{
		mWhitePixelU = whiteU;
		mWhitePixelV = whiteV;
	}

	public CachedFont GetFont(float pixelHeight) => null;

	public CachedFont GetFont(StringView familyName, float pixelHeight) => null;

	public ITexture GetAtlasTexture(CachedFont font) => null;

	public ITexture GetAtlasTexture(StringView familyName, float pixelHeight) => null;

	public void ReleaseFont(CachedFont font) { }

	public StringView DefaultFontFamily => "";

	public (float U, float V) WhitePixelUV => (mWhitePixelU, mWhitePixelV);
}
