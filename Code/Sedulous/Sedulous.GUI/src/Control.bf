using System;
using Sedulous.Mathematics;
using Sedulous.Drawing;

namespace Sedulous.GUI;

/// The visual state of a control.
public enum ControlState
{
	/// Normal state.
	Normal,
	/// Mouse is hovering over the control.
	Hover,
	/// Control is being pressed.
	Pressed,
	/// Control is disabled.
	Disabled,
	/// Control has keyboard focus.
	Focused
}

/// Base class for interactive controls with theming and state management.
/// Controls can be focused, enabled/disabled, and have visual states.
public abstract class Control : UIElement
{
	// State
	private bool mIsEnabled = true;
	private bool mIsFocused = false;
	private bool mIsHovered = false;
	private bool mIsPressed = false;
	private ControlState mCurrentState = .Normal;

	// Focus/Tab
	private bool mIsFocusable = true;
	private bool mIsTabStop = true;
	private int mTabIndex = 0;

	// Theming
	private Color mBackground = Color.Transparent;
	private Color mForeground = Color.White;
	private Color mBorderColor = Color.Gray;
	private float mBorderThickness = 0;
	private float mCornerRadius = 0;

	// Focus visual
	private Color mFocusBorderColor = Color(100, 149, 237, 255); // CornflowerBlue
	private float mFocusBorderThickness = 2;

	/// Whether this control is enabled.
	public bool IsEnabled
	{
		get => mIsEnabled;
		set
		{
			if (mIsEnabled != value)
			{
				mIsEnabled = value;
				UpdateControlState();
			}
		}
	}

	/// Whether this control is effectively enabled (considering parent chain).
	public bool IsEffectivelyEnabled
	{
		get
		{
			if (!mIsEnabled)
				return false;
			if (let parentControl = Parent as Control)
				return parentControl.IsEffectivelyEnabled;
			return true;
		}
	}

	/// Whether this control has keyboard focus.
	public bool IsFocused
	{
		get => mIsFocused;
		set
		{
			if (mIsFocused != value)
			{
				mIsFocused = value;
				UpdateControlState();
				if (value)
					OnGotFocus(scope FocusEventArgs());
				else
					OnLostFocus(scope FocusEventArgs());
			}
		}
	}

	/// Whether the mouse is hovering over this control.
	public bool IsHovered
	{
		get => mIsHovered;
		set
		{
			if (mIsHovered != value)
			{
				mIsHovered = value;
				UpdateControlState();
			}
		}
	}

	/// Whether this control is being pressed.
	public bool IsPressed
	{
		get => mIsPressed;
		set
		{
			if (mIsPressed != value)
			{
				mIsPressed = value;
				UpdateControlState();
			}
		}
	}

	/// The current visual state of the control.
	public ControlState CurrentState => mCurrentState;

	/// Whether this control can receive keyboard focus.
	public bool IsFocusable
	{
		get => mIsFocusable;
		set => mIsFocusable = value;
	}

	/// Whether this control participates in tab navigation.
	public bool IsTabStop
	{
		get => mIsTabStop;
		set => mIsTabStop = value;
	}

	/// Tab order for keyboard navigation. Lower values come first.
	public int TabIndex
	{
		get => mTabIndex;
		set => mTabIndex = value;
	}

	/// Whether focus is within this control or any descendant.
	public virtual bool IsFocusWithin
	{
		get => mIsFocused;
	}

	// === Theming Properties ===

	/// Background color.
	public Color Background
	{
		get => mBackground;
		set => mBackground = value;
	}

	/// Foreground (text) color.
	public Color Foreground
	{
		get => mForeground;
		set => mForeground = value;
	}

	/// Border color.
	public Color BorderColor
	{
		get => mBorderColor;
		set => mBorderColor = value;
	}

	/// Border thickness.
	public float BorderThickness
	{
		get => mBorderThickness;
		set
		{
			if (mBorderThickness != value)
			{
				mBorderThickness = value;
				InvalidateLayout();
			}
		}
	}

	/// Corner radius for rounded corners.
	public float CornerRadius
	{
		get => mCornerRadius;
		set => mCornerRadius = value;
	}

	/// Focus indicator border color.
	public Color FocusBorderColor
	{
		get => mFocusBorderColor;
		set => mFocusBorderColor = value;
	}

	/// Focus indicator border thickness.
	public float FocusBorderThickness
	{
		get => mFocusBorderThickness;
		set => mFocusBorderThickness = value;
	}

	/// Updates the current control state based on flags.
	protected void UpdateControlState()
	{
		if (!IsEffectivelyEnabled)
			mCurrentState = .Disabled;
		else if (mIsPressed)
			mCurrentState = .Pressed;
		else if (mIsFocused)
			mCurrentState = .Focused;
		else if (mIsHovered)
			mCurrentState = .Hover;
		else
			mCurrentState = .Normal;
	}

	/// Gets the background color for the current state.
	protected virtual Color GetStateBackground()
	{
		switch (mCurrentState)
		{
		case .Disabled:
			return Color(mBackground.R / 2, mBackground.G / 2, mBackground.B / 2, mBackground.A);
		case .Pressed:
			return Color(
				(uint8)Math.Min(255, mBackground.R * 0.7f),
				(uint8)Math.Min(255, mBackground.G * 0.7f),
				(uint8)Math.Min(255, mBackground.B * 0.7f),
				mBackground.A);
		case .Hover:
			return Color(
				(uint8)Math.Min(255, mBackground.R + 20),
				(uint8)Math.Min(255, mBackground.G + 20),
				(uint8)Math.Min(255, mBackground.B + 20),
				mBackground.A);
		default:
			return mBackground;
		}
	}

	/// Gets the border color for the current state.
	protected virtual Color GetStateBorderColor()
	{
		if (mIsFocused)
			return mFocusBorderColor;
		return mBorderColor;
	}

	/// Gets the border thickness for the current state.
	protected virtual float GetStateBorderThickness()
	{
		if (mIsFocused && mFocusBorderThickness > mBorderThickness)
			return mFocusBorderThickness;
		return mBorderThickness;
	}

	/// Renders the control background and border.
	protected virtual void RenderBackground(DrawContext ctx)
	{
		let bounds = ArrangedBounds;
		let bgColor = GetStateBackground();
		let borderColor = GetStateBorderColor();
		let borderThickness = GetStateBorderThickness();

		// Draw background
		if (bgColor.A > 0)
		{
			if (mCornerRadius > 0)
				ctx.FillRoundedRect(bounds, mCornerRadius, bgColor);
			else
				ctx.FillRect(bounds, bgColor);
		}

		// Draw border
		if (borderThickness > 0 && borderColor.A > 0)
		{
			if (mCornerRadius > 0)
			{
				// For rounded borders, we'd need a stroke rounded rect
				// For now, just draw a regular rect outline
				ctx.DrawRect(bounds, borderColor, borderThickness);
			}
			else
			{
				ctx.DrawRect(bounds, borderColor, borderThickness);
			}
		}
	}

	/// Default render implementation draws background/border.
	protected override void RenderOverride(DrawContext ctx)
	{
		RenderBackground(ctx);
	}

	// === Input Handling ===

	protected override void OnMouseEnter(MouseEventArgs e)
	{
		IsHovered = true;
		base.OnMouseEnter(e);
	}

	protected override void OnMouseLeave(MouseEventArgs e)
	{
		IsHovered = false;
		IsPressed = false;
		base.OnMouseLeave(e);
	}

	protected override void OnMouseDown(MouseButtonEventArgs e)
	{
		if (e.Button == .Left && IsEffectivelyEnabled)
		{
			IsPressed = true;
			// Request focus when clicked
			if (mIsFocusable)
				Context?.FocusManager?.SetFocus(this);
		}
		base.OnMouseDown(e);
	}

	protected override void OnMouseUp(MouseButtonEventArgs e)
	{
		if (e.Button == .Left)
		{
			IsPressed = false;
		}
		base.OnMouseUp(e);
	}
}
