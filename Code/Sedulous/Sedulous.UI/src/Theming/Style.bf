using System;
using System.Collections;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// A state-specific style that applies when a control is in a particular state.
public class StateStyle
{
	public ControlState State;
	public Dictionary<String, Color> ColorProperties = new .() ~ DeleteDictionaryAndKeys!(_);
	public Dictionary<String, float> FloatProperties = new .() ~ DeleteDictionaryAndKeys!(_);
	public Dictionary<String, Thickness> ThicknessProperties = new .() ~ DeleteDictionaryAndKeys!(_);

	public this(ControlState state)
	{
		State = state;
	}

	public void SetColor(StringView name, Color value)
	{
		let key = new String(name);
		if (ColorProperties.ContainsKeyAlt(name))
		{
			ColorProperties[key] = value;
			delete key;
		}
		else
			ColorProperties[key] = value;
	}

	public void SetFloat(StringView name, float value)
	{
		let key = new String(name);
		if (FloatProperties.ContainsKeyAlt(name))
		{
			FloatProperties[key] = value;
			delete key;
		}
		else
			FloatProperties[key] = value;
	}

	public void SetThickness(StringView name, Thickness value)
	{
		let key = new String(name);
		if (ThicknessProperties.ContainsKeyAlt(name))
		{
			ThicknessProperties[key] = value;
			delete key;
		}
		else
			ThicknessProperties[key] = value;
	}
}

/// A collection of property setters that define the visual appearance of a control.
public class Style
{
	private Dictionary<String, Color> mColorProperties = new .() ~ DeleteDictionaryAndKeys!(_);
	private Dictionary<String, float> mFloatProperties = new .() ~ DeleteDictionaryAndKeys!(_);
	private Dictionary<String, Thickness> mThicknessProperties = new .() ~ DeleteDictionaryAndKeys!(_);
	private List<StateStyle> mStateStyles = new .() ~ DeleteContainerAndItems!(_);

	/// State-specific styles.
	public List<StateStyle> StateStyles => mStateStyles;

	/// Sets a Color property value.
	public void SetColor(StringView propertyName, Color color)
	{
		let key = new String(propertyName);
		if (mColorProperties.ContainsKeyAlt(propertyName))
		{
			mColorProperties[key] = color;
			delete key;
		}
		else
			mColorProperties[key] = color;
	}

	/// Sets a float property value.
	public void SetFloat(StringView propertyName, float value)
	{
		let key = new String(propertyName);
		if (mFloatProperties.ContainsKeyAlt(propertyName))
		{
			mFloatProperties[key] = value;
			delete key;
		}
		else
			mFloatProperties[key] = value;
	}

	/// Sets a Thickness property value.
	public void SetThickness(StringView propertyName, Thickness value)
	{
		let key = new String(propertyName);
		if (mThicknessProperties.ContainsKeyAlt(propertyName))
		{
			mThicknessProperties[key] = value;
			delete key;
		}
		else
			mThicknessProperties[key] = value;
	}

	/// Adds a state-specific style.
	public StateStyle AddStateStyle(ControlState state)
	{
		let stateStyle = new StateStyle(state);
		mStateStyles.Add(stateStyle);
		return stateStyle;
	}

	/// Gets a Color property value, considering the current state.
	public bool TryGetColor(StringView propertyName, ControlState state, out Color value)
	{
		// Check state-specific styles first
		for (let stateStyle in mStateStyles)
		{
			if (HasState(state, stateStyle.State) && stateStyle.State != .Normal)
			{
				if (stateStyle.ColorProperties.TryGetValueAlt(propertyName, let color))
				{
					value = color;
					return true;
				}
			}
		}

		// Fall back to base properties
		if (mColorProperties.TryGetValueAlt(propertyName, let color))
		{
			value = color;
			return true;
		}

		value = default;
		return false;
	}

	/// Gets a float property value, considering the current state.
	public bool TryGetFloat(StringView propertyName, ControlState state, out float value)
	{
		for (let stateStyle in mStateStyles)
		{
			if (HasState(state, stateStyle.State) && stateStyle.State != .Normal)
			{
				if (stateStyle.FloatProperties.TryGetValueAlt(propertyName, let f))
				{
					value = f;
					return true;
				}
			}
		}

		if (mFloatProperties.TryGetValueAlt(propertyName, let f))
		{
			value = f;
			return true;
		}

		value = default;
		return false;
	}

	/// Gets a Thickness property value, considering the current state.
	public bool TryGetThickness(StringView propertyName, ControlState state, out Thickness value)
	{
		for (let stateStyle in mStateStyles)
		{
			if (HasState(state, stateStyle.State) && stateStyle.State != .Normal)
			{
				if (stateStyle.ThicknessProperties.TryGetValueAlt(propertyName, let t))
				{
					value = t;
					return true;
				}
			}
		}

		if (mThicknessProperties.TryGetValueAlt(propertyName, let t))
		{
			value = t;
			return true;
		}

		value = default;
		return false;
	}

	/// Checks if currentState has all the flags in requiredState.
	private static bool HasState(ControlState currentState, ControlState requiredState)
	{
		return ((int)currentState & (int)requiredState) == (int)requiredState;
	}
}
