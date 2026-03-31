namespace Sedulous.UI;

/// Interface for libraries to register theme defaults.
/// Implementations are registered via Theme.RegisterExtension() and
/// automatically applied when DarkTheme.Create() or LightTheme.Create() is called.
public interface IThemeExtension
{
	/// Apply default theme values for this extension's controls.
	/// The theme's Palette is already set, so use palette-relative colors
	/// to support both dark and light themes.
	void ApplyDefaults(Theme theme);
}
