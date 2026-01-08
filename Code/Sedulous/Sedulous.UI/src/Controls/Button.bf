using System;
using Sedulous.Drawing;
using Sedulous.Mathematics;
using Sedulous.Foundation.Core;

namespace Sedulous.UI;

/// A button control that can be clicked.
public class Button : ContentControl
{
	private bool mIsPressed;
	private bool mIsDefault;
	private bool mIsCancel;

	// Click event
	private EventAccessor<delegate void(Button)> mClickEvent = new .() ~ delete _;

	/// Event fired when the button is clicked.
	public EventAccessor<delegate void(Button)> Click => mClickEvent;

	/// Whether this is the default button (responds to Enter key).
	public bool IsDefault
	{
		get => mIsDefault;
		set => mIsDefault = value;
	}

	/// Whether this is the cancel button (responds to Escape key).
	public bool IsCancel
	{
		get => mIsCancel;
		set => mIsCancel = value;
	}

	/// Whether the button is currently pressed.
	public bool IsPressed => mIsPressed;

	public this()
	{
		// Buttons are focusable
		Focusable = true;
	}

	public this(StringView text) : this()
	{
		ContentText = text;
	}

	protected override void OnMouseDownRouted(MouseButtonEventArgs args)
	{
		base.OnMouseDownRouted(args);

		if (args.Button == .Left && IsEnabled)
		{
			mIsPressed = true;
			UpdateControlState();
			Context?.CaptureMouse(this);
			args.Handled = true;
		}
	}

	protected override void OnMouseUpRouted(MouseButtonEventArgs args)
	{
		base.OnMouseUpRouted(args);

		if (args.Button == .Left && mIsPressed)
		{
			Context?.ReleaseMouseCapture();
			mIsPressed = false;
			UpdateControlState();

			// Fire click if mouse is still over button
			if (IsMouseOver && IsEnabled)
			{
				OnClick();
			}

			args.Handled = true;
		}
	}

	protected override void OnMouseLeave()
	{
		base.OnMouseLeave();
		// Visual update but don't release press state
		// (allows drag-back to click)
	}

	protected override void OnKeyDownRouted(KeyEventArgs args)
	{
		base.OnKeyDownRouted(args);

		// Space or Enter activates button
		if (IsEnabled && (args.KeyCode == 32 || args.KeyCode == 13)) // Space or Enter
		{
			mIsPressed = true;
			UpdateControlState();
			args.Handled = true;
		}
	}

	protected override void OnKeyUpRouted(KeyEventArgs args)
	{
		base.OnKeyUpRouted(args);

		if (mIsPressed && (args.KeyCode == 32 || args.KeyCode == 13))
		{
			mIsPressed = false;
			UpdateControlState();
			OnClick();
			args.Handled = true;
		}
	}

	/// Called when the button is clicked.
	protected override void OnClick()
	{
		mClickEvent.[Friend]Invoke(this);
		base.OnClick();
	}

	protected override void UpdateControlState()
	{
		var state = Sedulous.UI.ControlState.Normal;

		if (!IsEnabled)
			state = (Sedulous.UI.ControlState)((int)state | (int)Sedulous.UI.ControlState.Disabled);
		if (IsFocused)
			state = (Sedulous.UI.ControlState)((int)state | (int)Sedulous.UI.ControlState.Focused);
		if (IsMouseOver)
			state = (Sedulous.UI.ControlState)((int)state | (int)Sedulous.UI.ControlState.Hovered);
		if (mIsPressed)
			state = (Sedulous.UI.ControlState)((int)state | (int)Sedulous.UI.ControlState.Pressed);

		ControlState = state;
	}

	protected override void OnRender(DrawContext drawContext)
	{
		let bounds = Bounds;

		// Get colors based on state
		var bgColor = Background ?? GetStateColor();
		let borderColor = BorderBrush ?? Color.Gray;

		// Draw background
		if (bgColor.HasValue)
		{
			drawContext.FillRect(bounds, bgColor.Value);
		}

		// Draw border
		let bt = BorderThickness;
		if (bt.TotalHorizontal > 0 || bt.TotalVertical > 0)
		{
			if (bt.Top > 0)
				drawContext.FillRect(.(bounds.X, bounds.Y, bounds.Width, bt.Top), borderColor);
			if (bt.Bottom > 0)
				drawContext.FillRect(.(bounds.X, bounds.Bottom - bt.Bottom, bounds.Width, bt.Bottom), borderColor);
			if (bt.Left > 0)
				drawContext.FillRect(.(bounds.X, bounds.Y + bt.Top, bt.Left, bounds.Height - bt.TotalVertical), borderColor);
			if (bt.Right > 0)
				drawContext.FillRect(.(bounds.Right - bt.Right, bounds.Y + bt.Top, bt.Right, bounds.Height - bt.TotalVertical), borderColor);
		}

		// Render content
		RenderContent(drawContext);
	}

	/// Gets a default color based on the current control state.
	private Color? GetStateColor()
	{
		let state = ControlState;

		if (((int)state & (int)Sedulous.UI.ControlState.Disabled) != 0)
			return Color(200, 200, 200, 255);
		if (((int)state & (int)Sedulous.UI.ControlState.Pressed) != 0)
			return Color(180, 180, 180, 255);
		if (((int)state & (int)Sedulous.UI.ControlState.Hovered) != 0)
			return Color(225, 225, 225, 255);

		return Color(240, 240, 240, 255);
	}
}
