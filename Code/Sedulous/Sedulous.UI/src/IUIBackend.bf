using System;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// Backend interface for platform-specific UI operations.
/// Implementations provide font rendering, texture management, and clipboard access.
interface IUIBackend
{
	// ============ Font Operations ============

	/// Loads a font from a file path.
	Result<FontHandle> LoadFont(StringView path);

	/// Loads a font from memory.
	Result<FontHandle> LoadFontFromMemory(Span<uint8> data, StringView name);

	/// Unloads a font.
	void UnloadFont(FontHandle font);

	/// Measures text with a font at a given size.
	Vector2 MeasureText(FontHandle font, float size, StringView text);

	/// Measures text with wrapping.
	Vector2 MeasureTextWrapped(FontHandle font, float size, StringView text, float maxWidth);

	// ============ Texture Operations ============

	/// Loads a texture from a file path.
	Result<TextureHandle> LoadTexture(StringView path);

	/// Creates a texture from raw pixel data.
	Result<TextureHandle> CreateTexture(uint32 width, uint32 height, Span<uint8> data);

	/// Updates texture data.
	void UpdateTexture(TextureHandle texture, uint32 x, uint32 y, uint32 width, uint32 height, Span<uint8> data);

	/// Unloads a texture.
	void UnloadTexture(TextureHandle texture);

	/// Gets the size of a texture.
	Vector2 GetTextureSize(TextureHandle texture);

	// ============ Clipboard Operations ============

	/// Gets the current clipboard text.
	void GetClipboardText(String outText);

	/// Sets the clipboard text.
	void SetClipboardText(StringView text);

	// ============ Cursor Operations ============

	/// Sets the mouse cursor type.
	void SetCursor(CursorType cursor);

	/// Gets the current cursor type.
	CursorType GetCursor();

	// ============ Time ============

	/// Gets the current time in seconds.
	float GetTime();
}

/// Null/stub backend for testing or when no backend is available.
class NullUIBackend : IUIBackend
{
	private float mStartTime;

	public this()
	{
		mStartTime = 0;
	}

	public Result<FontHandle> LoadFont(StringView path) => .Err;
	public Result<FontHandle> LoadFontFromMemory(Span<uint8> data, StringView name) => .Err;
	public void UnloadFont(FontHandle font) { }
	public Vector2 MeasureText(FontHandle font, float size, StringView text) => Vector2(text.Length * size * 0.5f, size);
	public Vector2 MeasureTextWrapped(FontHandle font, float size, StringView text, float maxWidth) => Vector2(maxWidth, size);

	public Result<TextureHandle> LoadTexture(StringView path) => .Err;
	public Result<TextureHandle> CreateTexture(uint32 width, uint32 height, Span<uint8> data) => .Err;
	public void UpdateTexture(TextureHandle texture, uint32 x, uint32 y, uint32 width, uint32 height, Span<uint8> data) { }
	public void UnloadTexture(TextureHandle texture) { }
	public Vector2 GetTextureSize(TextureHandle texture) => .Zero;

	public void GetClipboardText(String outText) { }
	public void SetClipboardText(StringView text) { }

	public void SetCursor(CursorType cursor) { }
	public CursorType GetCursor() => .Arrow;

	public float GetTime() => 0;
}
