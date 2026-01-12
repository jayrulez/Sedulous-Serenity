namespace TowerDefense.UI;

using System;
using Sedulous.Fonts;
using Sedulous.Drawing;
using Sedulous.UI;

/// Simple font service for Tower Defense UI.
class GameFontService : IFontService
{
	private CachedFont mCachedFont;
	private ITexture mFontTexture;
	private String mDefaultFontFamily = new .("Roboto") ~ delete _;

	public this(CachedFont cachedFont, ITexture texture)
	{
		mCachedFont = cachedFont;
		mFontTexture = texture;
	}

	public StringView DefaultFontFamily => mDefaultFontFamily;

	public CachedFont GetFont(float pixelHeight) => mCachedFont;
	public CachedFont GetFont(StringView familyName, float pixelHeight) => mCachedFont;
	public ITexture GetAtlasTexture(CachedFont font) => mFontTexture;
	public ITexture GetAtlasTexture(StringView familyName, float pixelHeight) => mFontTexture;
	public void ReleaseFont(CachedFont font) { }
}
