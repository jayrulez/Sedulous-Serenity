using System;
using Sedulous.UI;

namespace Sedulous.UI.Tests;

/// A test view that tracks which input handlers were called.
class InputTestView : View
{
	public float DesiredWidth;
	public float DesiredHeight;

	// Tracking flags
	public bool MouseDownCalled;
	public bool MouseUpCalled;
	public bool MouseMoveCalled;
	public bool MouseWheelCalled;
	public bool MouseEnterCalled;
	public bool MouseLeaveCalled;
	public bool KeyDownCalled;
	public bool KeyUpCalled;
	public bool TextInputCalled;
	public bool FocusGainedCalled;
	public bool FocusLostCalled;

	// Last received values
	public MouseButton LastButton;
	public int32 LastClickCount;
	public KeyCode LastKey;
	public char32 LastChar;
	public bool LastHandled;

	/// If true, marks events as Handled.
	public bool HandlesEvents;

	public this(float desiredWidth = 50, float desiredHeight = 50)
	{
		DesiredWidth = desiredWidth;
		DesiredHeight = desiredHeight;
	}

	protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		SetMeasuredDimension(
			widthSpec.Resolve(DesiredWidth, MinWidth, MaxWidth),
			heightSpec.Resolve(DesiredHeight, MinHeight, MaxHeight)
		);
	}

	public void ClearFlags()
	{
		MouseDownCalled = false;
		MouseUpCalled = false;
		MouseMoveCalled = false;
		MouseWheelCalled = false;
		MouseEnterCalled = false;
		MouseLeaveCalled = false;
		KeyDownCalled = false;
		KeyUpCalled = false;
		TextInputCalled = false;
		FocusGainedCalled = false;
		FocusLostCalled = false;
	}

	public override void OnMouseDown(MouseButtonEventArgs e)
	{
		MouseDownCalled = true;
		LastButton = e.Button;
		LastClickCount = e.ClickCount;
		if (HandlesEvents) e.Handled = true;
	}

	public override void OnMouseUp(MouseButtonEventArgs e)
	{
		MouseUpCalled = true;
		if (HandlesEvents) e.Handled = true;
	}

	public override void OnMouseMove(MouseEventArgs e)
	{
		MouseMoveCalled = true;
		if (HandlesEvents) e.Handled = true;
	}

	public override void OnMouseWheel(MouseWheelEventArgs e)
	{
		MouseWheelCalled = true;
		if (HandlesEvents) e.Handled = true;
	}

	public override void OnMouseEnter(MouseEventArgs e) { MouseEnterCalled = true; }
	public override void OnMouseLeave(MouseEventArgs e) { MouseLeaveCalled = true; }

	public override void OnKeyDown(KeyEventArgs e)
	{
		KeyDownCalled = true;
		LastKey = e.Key;
		if (HandlesEvents) e.Handled = true;
	}

	public override void OnKeyUp(KeyEventArgs e)
	{
		KeyUpCalled = true;
		if (HandlesEvents) e.Handled = true;
	}

	public override void OnTextInput(TextInputEventArgs e)
	{
		TextInputCalled = true;
		LastChar = e.Character;
	}

	public override void OnFocusGained(FocusEventArgs e) { FocusGainedCalled = true; }
	public override void OnFocusLost(FocusEventArgs e) { FocusLostCalled = true; }
}
