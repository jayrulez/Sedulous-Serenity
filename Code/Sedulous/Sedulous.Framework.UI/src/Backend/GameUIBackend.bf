using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.UI;
using Sedulous.UI.FontRenderer;
using Sedulous.RHI;
using Sedulous.Framework.Renderer;

namespace Sedulous.Framework.UI;

/// In-game UI backend integrated with the Framework renderer.
class GameUIBackend : IUIBackend
{
	private RendererService mRenderer;
	private FontManager mFontManager;
	private Dictionary<uint32, Vector2> mTextureSizes = new .() ~ delete _;
	private uint32 mNextTextureId = 1;
	private CursorType mCurrentCursor = .Arrow;
	private float mStartTime;

	/// Creates a game UI backend.
	public this(RendererService renderer, FontManager fontManager)
	{
		mRenderer = renderer;
		mFontManager = fontManager;
		mStartTime = (float)Internal.GetTickCountMicro() / 1000000.0f;
	}

	/// Gets the renderer service.
	public RendererService Renderer => mRenderer;

	/// Gets the font manager.
	public FontManager FontManager => mFontManager;

	// ============ Font Operations ============

	public Result<FontHandle> LoadFont(StringView path)
	{
		// Font loading would be handled through FontManager
		// For now, return stub
		return .Err;
	}

	public Result<FontHandle> LoadFontFromMemory(Span<uint8> data, StringView name)
	{
		// Font loading would be handled through FontManager
		return .Err;
	}

	public void UnloadFont(FontHandle font)
	{
		// Font unloading handled by FontManager
	}

	public Vector2 MeasureText(FontHandle font, float size, StringView text)
	{
		// Approximate measurement when no font loaded
		return Vector2(text.Length * size * 0.5f, size);
	}

	public Vector2 MeasureTextWrapped(FontHandle font, float size, StringView text, float maxWidth)
	{
		// Approximate measurement when no font loaded
		return Vector2(maxWidth, size);
	}

	// ============ Texture Operations ============

	public Result<TextureHandle> LoadTexture(StringView path)
	{
		// For game UI, textures should be loaded through the resource system
		return .Err;
	}

	public Result<TextureHandle> CreateTexture(uint32 width, uint32 height, Span<uint8> data)
	{
		if (mRenderer == null || mRenderer.Device == null)
			return .Err;

		let handle = TextureHandle(mNextTextureId++);
		mTextureSizes[handle.Value] = Vector2((float)width, (float)height);
		return .Ok(handle);
	}

	public void UpdateTexture(TextureHandle texture, uint32 x, uint32 y, uint32 width, uint32 height, Span<uint8> data)
	{
		// Texture update would be implemented here
	}

	public void UnloadTexture(TextureHandle texture)
	{
		mTextureSizes.Remove(texture.Value);
	}

	public Vector2 GetTextureSize(TextureHandle texture)
	{
		if (mTextureSizes.TryGetValue(texture.Value, let size))
			return size;
		return .Zero;
	}

	// ============ Clipboard Operations ============

	public void GetClipboardText(String outText)
	{
		// Clipboard access would go through Shell
	}

	public void SetClipboardText(StringView text)
	{
		// Clipboard access would go through Shell
	}

	// ============ Cursor Operations ============

	public void SetCursor(CursorType cursor)
	{
		mCurrentCursor = cursor;
		// Cursor change would go through Shell
	}

	public CursorType GetCursor() => mCurrentCursor;

	// ============ Time ============

	public float GetTime()
	{
		return (float)Internal.GetTickCountMicro() / 1000000.0f - mStartTime;
	}
}
