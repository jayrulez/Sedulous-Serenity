namespace Sedulous.UI;

/// Bridge between a docking system (UI layer) and the application (framework layer).
/// Abstracts whether floating windows are real OS windows or virtual (PopupLayer) windows.
/// Implement in the Application class and assign to DockManager.FloatingWindowHost.
public interface IFloatingWindowHost
{
	/// Whether this host supports creating real OS windows.
	bool SupportsOSWindows { get; }

	/// Create a real OS window to host the given floating window view.
	/// The view becomes the root of a new UIContext in the secondary window.
	/// screenX/screenY: desired global screen position (-1 = OS default).
	/// onCloseRequested is called when the OS window close button is clicked.
	void CreateFloatingWindow(View floatingWindow, float width, float height,
		float screenX = -1, float screenY = -1,
		delegate void(View) onCloseRequested = null);

	/// Destroy the OS window hosting the given floating window view.
	void DestroyFloatingWindow(View floatingWindow);
}
