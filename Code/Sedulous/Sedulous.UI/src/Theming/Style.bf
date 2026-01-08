using System;
using System.Collections;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// Represents a style state for property overrides.
class StyleState
{
	private Dictionary<String, Color> mColors ~ DeleteDictionaryAndKeys!(_);
	private Dictionary<String, float> mFloats ~ DeleteDictionaryAndKeys!(_);
	private Dictionary<String, Thickness> mThicknesses ~ DeleteDictionaryAndKeys!(_);
	private Dictionary<String, CornerRadius> mCornerRadii ~ DeleteDictionaryAndKeys!(_);

	/// Creates a new style state.
	public this()
	{
		mColors = new Dictionary<String, Color>();
		mFloats = new Dictionary<String, float>();
		mThicknesses = new Dictionary<String, Thickness>();
		mCornerRadii = new Dictionary<String, CornerRadius>();
	}

	/// Sets a color property.
	public void SetColor(StringView name, Color color)
	{
		let key = new String(name);
		if (mColors.ContainsKey(key))
		{
			mColors[key] = color;
			delete key;
		}
		else
		{
			mColors[key] = color;
		}
	}

	/// Sets a float property.
	public void SetFloat(StringView name, float value)
	{
		let key = new String(name);
		if (mFloats.ContainsKey(key))
		{
			mFloats[key] = value;
			delete key;
		}
		else
		{
			mFloats[key] = value;
		}
	}

	/// Sets a thickness property.
	public void SetThickness(StringView name, Thickness value)
	{
		let key = new String(name);
		if (mThicknesses.ContainsKey(key))
		{
			mThicknesses[key] = value;
			delete key;
		}
		else
		{
			mThicknesses[key] = value;
		}
	}

	/// Sets a corner radius property.
	public void SetCornerRadius(StringView name, CornerRadius value)
	{
		let key = new String(name);
		if (mCornerRadii.ContainsKey(key))
		{
			mCornerRadii[key] = value;
			delete key;
		}
		else
		{
			mCornerRadii[key] = value;
		}
	}

	/// Gets a color property value.
	public Result<Color> GetColor(StringView name)
	{
		if (mColors.TryGetValue(scope String(name), let value))
			return value;
		return .Err;
	}

	/// Gets a float property value.
	public Result<float> GetFloat(StringView name)
	{
		if (mFloats.TryGetValue(scope String(name), let value))
			return value;
		return .Err;
	}

	/// Gets a thickness property value.
	public Result<Thickness> GetThickness(StringView name)
	{
		if (mThicknesses.TryGetValue(scope String(name), let value))
			return value;
		return .Err;
	}

	/// Gets a corner radius property value.
	public Result<CornerRadius> GetCornerRadius(StringView name)
	{
		if (mCornerRadii.TryGetValue(scope String(name), let value))
			return value;
		return .Err;
	}

	/// Checks if a color property exists.
	public bool HasColor(StringView name) => mColors.ContainsKey(scope String(name));

	/// Checks if a float property exists.
	public bool HasFloat(StringView name) => mFloats.ContainsKey(scope String(name));

	/// Checks if a thickness property exists.
	public bool HasThickness(StringView name) => mThicknesses.ContainsKey(scope String(name));

	/// Checks if a corner radius property exists.
	public bool HasCornerRadius(StringView name) => mCornerRadii.ContainsKey(scope String(name));
}

/// Defines a style for a widget type.
class Style
{
	private String mTargetType ~ delete _;
	private String mBasedOn ~ delete _;
	private StyleState mBase ~ delete _;
	private StyleState mNormal ~ delete _;
	private StyleState mHover ~ delete _;
	private StyleState mPressed ~ delete _;
	private StyleState mFocused ~ delete _;
	private StyleState mDisabled ~ delete _;

	/// Creates a new style.
	public this()
	{
		mBase = new StyleState();
		mNormal = new StyleState();
		mHover = new StyleState();
		mPressed = new StyleState();
		mFocused = new StyleState();
		mDisabled = new StyleState();
	}

	/// Creates a style for a specific widget type.
	public this(StringView targetType) : this()
	{
		mTargetType = new String(targetType);
	}

	/// Gets or sets the target widget type name.
	public StringView TargetType
	{
		get => mTargetType ?? "";
		set
		{
			delete mTargetType;
			mTargetType = value.IsEmpty ? null : new String(value);
		}
	}

	/// Gets or sets the parent style name this style is based on.
	public StringView BasedOn
	{
		get => mBasedOn ?? "";
		set
		{
			delete mBasedOn;
			mBasedOn = value.IsEmpty ? null : new String(value);
		}
	}

	/// Gets the base properties (always applied).
	public StyleState Base => mBase;

	/// Gets the normal state style.
	public StyleState Normal => mNormal;

	/// Gets the hover state style.
	public StyleState Hover => mHover;

	/// Gets the pressed state style.
	public StyleState Pressed => mPressed;

	/// Gets the focused state style.
	public StyleState Focused => mFocused;

	/// Gets the disabled state style.
	public StyleState Disabled => mDisabled;

	/// Gets a color property, checking states in priority order.
	public Result<Color> GetColor(StringView name, bool isHovered, bool isPressed, bool isFocused, bool isDisabled)
	{
		// Check state-specific properties first
		if (isDisabled)
		{
			if (mDisabled.GetColor(name) case .Ok(let val))
				return val;
		}
		else
		{
			if (isPressed)
			{
				if (mPressed.GetColor(name) case .Ok(let val))
					return val;
			}
			if (isHovered)
			{
				if (mHover.GetColor(name) case .Ok(let val))
					return val;
			}
			if (isFocused)
			{
				if (mFocused.GetColor(name) case .Ok(let val))
					return val;
			}
		}

		// Check normal state
		if (mNormal.GetColor(name) case .Ok(let val))
			return val;

		// Check base properties
		return mBase.GetColor(name);
	}

	/// Gets a float property, checking states in priority order.
	public Result<float> GetFloat(StringView name, bool isHovered, bool isPressed, bool isFocused, bool isDisabled)
	{
		if (isDisabled)
		{
			if (mDisabled.GetFloat(name) case .Ok(let val))
				return val;
		}
		else
		{
			if (isPressed)
			{
				if (mPressed.GetFloat(name) case .Ok(let val))
					return val;
			}
			if (isHovered)
			{
				if (mHover.GetFloat(name) case .Ok(let val))
					return val;
			}
			if (isFocused)
			{
				if (mFocused.GetFloat(name) case .Ok(let val))
					return val;
			}
		}

		if (mNormal.GetFloat(name) case .Ok(let val))
			return val;

		return mBase.GetFloat(name);
	}

	/// Standard property names.
	public static class PropertyNames
	{
		public static readonly StringView BackgroundColor = "BackgroundColor";
		public static readonly StringView ForegroundColor = "ForegroundColor";
		public static readonly StringView BorderColor = "BorderColor";
		public static readonly StringView BorderWidth = "BorderWidth";
		public static readonly StringView CornerRadius = "CornerRadius";
		public static readonly StringView Padding = "Padding";
		public static readonly StringView Margin = "Margin";
		public static readonly StringView FontSize = "FontSize";
		public static readonly StringView TextColor = "TextColor";
		public static readonly StringView Opacity = "Opacity";
	}
}
