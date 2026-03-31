namespace Sedulous.UI.Toolkit;

/// Interface for a window containing a dockable panel.
/// Implemented by FloatingWindow.
public interface IDockableWindow
{
	DockablePanel DetachPanel();
}
