using System;

namespace Sedulous.Shell;

/// Represents a platform window.
public interface IWindow
{
	/// Gets the unique window identifier.
	uint32 ID { get; }

	/// Gets or sets the window title.
	StringView Title { get; set; }

	/// Gets or sets the window X position.
	int32 X { get; set; }

	/// Gets or sets the window Y position.
	int32 Y { get; set; }

	/// Gets or sets the window width.
	int32 Width { get; set; }

	/// Gets or sets the window height.
	int32 Height { get; set; }

	/// Gets the current window state.
	WindowState State { get; }

	/// Gets or sets whether the window is visible.
	bool Visible { get; set; }

	/// Gets whether the window has input focus.
	bool Focused { get; }

	/// Shows the window.
	void Show();

	/// Hides the window.
	void Hide();

	/// Minimizes the window.
	void Minimize();

	/// Maximizes the window.
	void Maximize();

	/// Restores the window from minimized/maximized state.
	void Restore();

	/// Requests the window to close.
	void Close();

	/// Sets or clears fullscreen mode.
	void SetFullscreen(bool fullscreen);

	/// Gets the native platform handle for this window.
	/// On Windows, this returns the HWND.
	void* NativeHandle { get; }
}
