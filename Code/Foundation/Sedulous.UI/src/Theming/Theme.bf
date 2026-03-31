namespace Sedulous.UI;

using System;
using System.Collections;
using Sedulous.Core.Mathematics;

/// Defines the visual appearance of UI controls.
/// Uses typed dictionaries keyed by "ControlType.Property" strings.
public class Theme
{
	/// The palette of seed colors for this theme.
	public Palette Palette;

	/// Display name for this theme.
	public String Name ~ delete _;

	/// Optional font family name for this theme.
	/// When set, the application should switch to this font family.
	public String FontFamily ~ delete _;

	// Per-control-type color overrides (e.g. "Button.background", "CheckBox.accent")
	private Dictionary<String, Color> mColors = new .() ~ DeleteDictionaryAndKeys!(_);

	// Per-control-type dimension overrides (e.g. "Button.cornerRadius")
	private Dictionary<String, float> mDimensions = new .() ~ DeleteDictionaryAndKeys!(_);

	// App-level named colors (e.g. "danger", "success")
	private Dictionary<String, Color> mNamedColors = new .() ~ DeleteDictionaryAndKeys!(_);

	// App-level named dimensions
	private Dictionary<String, float> mNamedDimensions = new .() ~ DeleteDictionaryAndKeys!(_);

	// Per-control-type padding overrides (e.g. "Button.padding")
	private Dictionary<String, Thickness> mPaddings = new .() ~ DeleteDictionaryAndKeys!(_);

	// Per-control-type string values (e.g. "TreeView.expandedSymbol")
	private Dictionary<String, String> mStrings = new .() ~ { for (let kv in _) { delete kv.key; delete kv.value; } delete _; };

	// Per-control-type drawable overrides (e.g. "Button.background")
	// Values are non-owning references — actual ownership is in mOwnedDrawables.
	private Dictionary<String, Drawable> mDrawables = new .() ~ DeleteDictionaryAndKeys!(_);

	// Drawables owned by this theme (deleted on dispose)
	private List<Drawable> mOwnedDrawables = new .() ~ { for (let d in _) delete d; delete _; };

	// Static registry of theme extensions from external libraries
	private static List<IThemeExtension> sExtensions;

	public this()
	{
		Palette = Sedulous.UI.Palette.Dark;
	}

	//==========================================================================
	// Theme Extensions
	//==========================================================================

	/// Register a theme extension. The Theme class takes ownership of the extension object.
	/// Extensions are applied to all themes created via DarkTheme/LightTheme factories.
	public static void RegisterExtension(IThemeExtension ext)
	{
		if (sExtensions == null)
			sExtensions = new .();
		sExtensions.Add(ext);
	}

	/// Apply all registered extensions to a theme.
	/// Called by DarkTheme.Create() and LightTheme.Create() after setting base colors.
	public static void ApplyRegisteredExtensions(Theme theme)
	{
		if (sExtensions == null) return;
		for (let ext in sExtensions)
			ext.ApplyDefaults(theme);
	}

	/// Clean up the static extension registry. Call at program shutdown if desired.
	public static void ShutdownExtensions()
	{
		if (sExtensions != null)
		{
			for (let ext in sExtensions)
				delete ext;
			delete sExtensions;
			sExtensions = null;
		}
	}

	//==========================================================================
	// Control-type colors
	//==========================================================================

	/// Set a color for a control type and property.
	public void SetColor(StringView controlType, StringView property, Color color)
	{
		let key = BuildKey(controlType, property);
		if (mColors.TryGetValue(key, let existing))
		{
			mColors[key] = color;
			delete key;
		}
		else
		{
			mColors[key] = color;
		}
	}

	/// Get a color for a control type and property, or null if not set.
	public Color? GetColor(StringView controlType, StringView property)
	{
		let key = scope String()..AppendF("{}.{}", controlType, property);
		if (mColors.TryGetValue(key, let color))
			return color;
		return null;
	}

	//==========================================================================
	// Control-type dimensions
	//==========================================================================

	/// Set a dimension for a control type and property.
	public void SetDimension(StringView controlType, StringView property, float value)
	{
		let key = BuildKey(controlType, property);
		if (mDimensions.TryGetValue(key, let existing))
		{
			mDimensions[key] = value;
			delete key;
		}
		else
		{
			mDimensions[key] = value;
		}
	}

	/// Get a dimension for a control type and property, or null if not set.
	public float? GetDimension(StringView controlType, StringView property)
	{
		let key = scope String()..AppendF("{}.{}", controlType, property);
		if (mDimensions.TryGetValue(key, let value))
			return value;
		return null;
	}

	//==========================================================================
	// Named colors
	//==========================================================================

	/// Set an app-level named color.
	public void SetNamedColor(StringView name, Color color)
	{
		let key = new String(name);
		if (mNamedColors.TryGetValue(key, let existing))
		{
			mNamedColors[key] = color;
			delete key;
		}
		else
		{
			mNamedColors[key] = color;
		}
	}

	/// Get an app-level named color, or null if not set.
	public Color? GetNamedColor(StringView name)
	{
		let key = scope String(name);
		if (mNamedColors.TryGetValue(key, let color))
			return color;
		return null;
	}

	//==========================================================================
	// Named dimensions
	//==========================================================================

	/// Set an app-level named dimension.
	public void SetNamedDimension(StringView name, float value)
	{
		let key = new String(name);
		if (mNamedDimensions.TryGetValue(key, let existing))
		{
			mNamedDimensions[key] = value;
			delete key;
		}
		else
		{
			mNamedDimensions[key] = value;
		}
	}

	/// Get an app-level named dimension, or null if not set.
	public float? GetNamedDimension(StringView name)
	{
		let key = scope String(name);
		if (mNamedDimensions.TryGetValue(key, let value))
			return value;
		return null;
	}

	//==========================================================================
	// Control-type padding
	//==========================================================================

	/// Set padding for a control type.
	public void SetPadding(StringView controlType, StringView property, Thickness padding)
	{
		let key = BuildKey(controlType, property);
		if (mPaddings.TryGetValue(key, let existing))
		{
			mPaddings[key] = padding;
			delete key;
		}
		else
		{
			mPaddings[key] = padding;
		}
	}

	/// Get padding for a control type, or null if not set.
	public Thickness? GetPadding(StringView controlType, StringView property)
	{
		let key = scope String()..AppendF("{}.{}", controlType, property);
		if (mPaddings.TryGetValue(key, let value))
			return value;
		return null;
	}

	//==========================================================================
	// Control-type strings
	//==========================================================================

	/// Set a string value for a control type and property.
	public void SetString(StringView controlType, StringView property, StringView value)
	{
		let key = BuildKey(controlType, property);
		if (mStrings.TryGetValue(key, let existing))
		{
			existing.Set(value);
			delete key;
		}
		else
		{
			mStrings[key] = new String(value);
		}
	}

	/// Get a string value for a control type and property, or null if not set.
	public String GetString(StringView controlType, StringView property)
	{
		let key = scope String()..AppendF("{}.{}", controlType, property);
		if (mStrings.TryGetValue(key, let value))
			return value;
		return null;
	}

	//==========================================================================
	// Control-type drawables
	//==========================================================================

	/// Set a drawable for a control type and property. The theme takes ownership.
	public void SetDrawable(StringView controlType, StringView property, Drawable drawable)
	{
		let key = BuildKey(controlType, property);
		if (mDrawables.TryGetValue(key, let existing))
		{
			mDrawables[key] = drawable;
			delete key;
		}
		else
		{
			mDrawables[key] = drawable;
		}
		mOwnedDrawables.Add(drawable);
	}

	/// Get a drawable for a control type and property, or null if not set.
	public Drawable GetDrawable(StringView controlType, StringView property)
	{
		let key = scope String()..AppendF("{}.{}", controlType, property);
		if (mDrawables.TryGetValue(key, let drawable))
			return drawable;
		return null;
	}

	//==========================================================================
	// Drawable ownership
	//==========================================================================

	/// Register a drawable to be owned (and deleted) by this theme.
	/// Returns the drawable for chaining.
	public T OwnDrawable<T>(T drawable) where T : Drawable
	{
		mOwnedDrawables.Add(drawable);
		return drawable;
	}

	//==========================================================================
	// Internal helpers
	//==========================================================================

	private static String BuildKey(StringView controlType, StringView property)
	{
		let key = new String();
		key.AppendF("{}.{}", controlType, property);
		return key;
	}
}
