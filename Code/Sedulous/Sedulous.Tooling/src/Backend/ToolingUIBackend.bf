namespace Sedulous.Tooling;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;
using Sedulous.UI;
using Sedulous.UI.FontRenderer;

/// Tooling UI backend using RHI for rendering.
class ToolingUIBackend : IUIBackend
{
	private IDevice mDevice;
	private FontManager mFontManager ~ delete _;
	private UIRenderer mRenderer ~ delete _;

	// Font handle management
	private Dictionary<uint32, Font> mFonts = new .() ~ DeleteDictionaryAndValues!(_);
	private uint32 mNextFontHandle = 1;

	// Texture handle management
	private Dictionary<uint32, TextureResource> mTextures = new .() ~ DeleteDictionaryAndValues!(_);
	private uint32 mNextTextureHandle = 1;

	// Clipboard (simplified - in real impl would use Shell)
	private String mClipboard = new .() ~ delete _;

	// Cursor
	private CursorType mCurrentCursor = .Arrow;

	// Time tracking
	private float mStartTime;

	/// Internal texture resource.
	private class TextureResource
	{
		public ITexture Texture ~ delete _;
		public ITextureView View ~ delete _;
		public uint32 Width;
		public uint32 Height;
	}

	/// Creates a tooling UI backend.
	public this(IDevice device)
	{
		mDevice = device;
		mFontManager = new FontManager();
		mRenderer = new UIRenderer(device);
		mStartTime = 0; // Would use actual time in real impl
	}

	/// Initializes the backend.
	public Result<void> Initialize(TextureFormat colorFormat)
	{
		return mRenderer.Initialize(colorFormat);
	}

	/// Gets the UI renderer.
	public UIRenderer Renderer => mRenderer;

	// ============ Font Operations ============

	public Result<FontHandle> LoadFont(StringView path)
	{
		if (mFontManager.LoadFont(path) case .Ok(let font))
		{
			let handle = FontHandle(mNextFontHandle++);
			mFonts[handle.Value] = font;
			return handle;
		}
		return .Err;
	}

	public Result<FontHandle> LoadFontFromMemory(Span<uint8> data, StringView name)
	{
		if (mFontManager.LoadFontFromMemory(data, name) case .Ok(let font))
		{
			let handle = FontHandle(mNextFontHandle++);
			mFonts[handle.Value] = font;
			return handle;
		}
		return .Err;
	}

	public void UnloadFont(FontHandle font)
	{
		if (mFonts.TryGetValue(font.Value, let f))
		{
			mFontManager.UnloadFont(f);
			mFonts.Remove(font.Value);
		}
	}

	public Vector2 MeasureText(FontHandle font, float size, StringView text)
	{
		if (mFonts.TryGetValue(font.Value, let f))
		{
			return f.MeasureText(text, size);
		}
		// Fallback approximation
		return Vector2(text.Length * size * 0.5f, size);
	}

	public Vector2 MeasureTextWrapped(FontHandle font, float size, StringView text, float maxWidth)
	{
		if (mFonts.TryGetValue(font.Value, let f))
		{
			int lineCount = 0;
			return f.MeasureText(text, size, maxWidth, out lineCount);
		}
		// Fallback approximation
		return Vector2(maxWidth, size);
	}

	// ============ Texture Operations ============

	public Result<TextureHandle> LoadTexture(StringView path)
	{
		// Would use image loading in real implementation
		// For now, return error (not implemented)
		return .Err;
	}

	public Result<TextureHandle> CreateTexture(uint32 width, uint32 height, Span<uint8> data)
	{
		TextureDescriptor texDesc = .();
		texDesc.Width = width;
		texDesc.Height = height;
		texDesc.Depth = 1;
		texDesc.Format = .RGBA8Unorm;
		texDesc.Usage = .Sampled | .CopyDst;
		texDesc.MipLevelCount = 1;
		texDesc.SampleCount = 1;
		texDesc.Dimension = .Texture2D;

		if (mDevice.CreateTexture(&texDesc) not case .Ok(let texture))
			return .Err;

		TextureViewDescriptor viewDesc = .();
		if (mDevice.CreateTextureView(texture, &viewDesc) not case .Ok(let view))
		{
			delete texture;
			return .Err;
		}

		// Upload data
		if (data.Length > 0)
		{
			// Would upload texture data here
		}

		let resource = new TextureResource();
		resource.Texture = texture;
		resource.View = view;
		resource.Width = width;
		resource.Height = height;

		let handle = TextureHandle(mNextTextureHandle++);
		mTextures[handle.Value] = resource;
		return handle;
	}

	public void UpdateTexture(TextureHandle texture, uint32 x, uint32 y, uint32 width, uint32 height, Span<uint8> data)
	{
		if (mTextures.TryGetValue(texture.Value, let res))
		{
			// Would update texture region here
		}
	}

	public void UnloadTexture(TextureHandle texture)
	{
		if (mTextures.TryGetValue(texture.Value, let res))
		{
			delete res;
			mTextures.Remove(texture.Value);
		}
	}

	public Vector2 GetTextureSize(TextureHandle texture)
	{
		if (mTextures.TryGetValue(texture.Value, let res))
		{
			return Vector2((float)res.Width, (float)res.Height);
		}
		return .Zero;
	}

	// ============ Clipboard Operations ============

	public void GetClipboardText(String outText)
	{
		outText.Set(mClipboard);
	}

	public void SetClipboardText(StringView text)
	{
		mClipboard.Set(text);
	}

	// ============ Cursor Operations ============

	public void SetCursor(CursorType cursor)
	{
		mCurrentCursor = cursor;
		// Would set actual cursor via Shell in real implementation
	}

	public CursorType GetCursor()
	{
		return mCurrentCursor;
	}

	// ============ Time ============

	public float GetTime()
	{
		// Would return actual time in real implementation
		return 0;
	}

	// ============ Internal Helpers ============

	/// Gets a font by handle.
	public Font GetFont(FontHandle handle)
	{
		if (mFonts.TryGetValue(handle.Value, let font))
			return font;
		return null;
	}

	/// Gets a texture view by handle.
	public ITextureView GetTextureView(TextureHandle handle)
	{
		if (mTextures.TryGetValue(handle.Value, let res))
			return res.View;
		return null;
	}
}
