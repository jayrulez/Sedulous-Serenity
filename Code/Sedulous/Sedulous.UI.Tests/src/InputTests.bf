using System;
using System.Collections;
using Sedulous.Mathematics;

namespace Sedulous.UI.Tests;

/// Test element that tracks input events received.
/// Extends CompositeControl to support children for hierarchy tests.
class InputTestElement : CompositeControl
{
	public List<String> ReceivedEvents = new .() ~ DeleteContainerAndItems!(_);
	public MouseButtonEventArgs LastMouseDownArgs;
	public MouseButtonEventArgs LastMouseUpArgs;
	public KeyEventArgs LastKeyDownArgs;
	public bool HandleEvents = false;

	protected override void OnMouseDownRouted(MouseButtonEventArgs args)
	{
		base.OnMouseDownRouted(args);
		ReceivedEvents.Add(new String("MouseDown"));
		LastMouseDownArgs = args;
		if (HandleEvents)
			args.Handled = true;
	}

	protected override void OnMouseUpRouted(MouseButtonEventArgs args)
	{
		base.OnMouseUpRouted(args);
		ReceivedEvents.Add(new String("MouseUp"));
		LastMouseUpArgs = args;
		if (HandleEvents)
			args.Handled = true;
	}

	protected override void OnMouseMoveRouted(MouseEventArgs args)
	{
		base.OnMouseMoveRouted(args);
		ReceivedEvents.Add(new String("MouseMove"));
		if (HandleEvents)
			args.Handled = true;
	}

	protected override void OnMouseWheelRouted(MouseWheelEventArgs args)
	{
		base.OnMouseWheelRouted(args);
		ReceivedEvents.Add(new String("MouseWheel"));
		if (HandleEvents)
			args.Handled = true;
	}

	protected override void OnKeyDownRouted(KeyEventArgs args)
	{
		base.OnKeyDownRouted(args);
		ReceivedEvents.Add(new String("KeyDown"));
		LastKeyDownArgs = args;
		if (HandleEvents)
			args.Handled = true;
	}

	protected override void OnKeyUpRouted(KeyEventArgs args)
	{
		base.OnKeyUpRouted(args);
		ReceivedEvents.Add(new String("KeyUp"));
		if (HandleEvents)
			args.Handled = true;
	}

	protected override void OnTextInputRouted(TextInputEventArgs args)
	{
		base.OnTextInputRouted(args);
		ReceivedEvents.Add(new String("TextInput"));
		if (HandleEvents)
			args.Handled = true;
	}

	protected override void OnMouseEnter()
	{
		base.OnMouseEnter();
		ReceivedEvents.Add(new String("MouseEnter"));
	}

	protected override void OnMouseLeave()
	{
		base.OnMouseLeave();
		ReceivedEvents.Add(new String("MouseLeave"));
	}

	protected override void OnGotFocus()
	{
		base.OnGotFocus();
		ReceivedEvents.Add(new String("GotFocus"));
	}

	protected override void OnLostFocus()
	{
		base.OnLostFocus();
		ReceivedEvents.Add(new String("LostFocus"));
	}

	public void ClearEvents()
	{
		DeleteContainerAndItems!(ReceivedEvents);
		ReceivedEvents = new .();
	}

	public bool HasEvent(StringView name)
	{
		for (let e in ReceivedEvents)
			if (e == name)
				return true;
		return false;
	}

	public int EventCount(StringView name)
	{
		int count = 0;
		for (let e in ReceivedEvents)
			if (e == name)
				count++;
		return count;
	}
}

class InputEventArgsTests
{
	[Test]
	public static void MouseEventArgsDefaults()
	{
		let args = scope MouseEventArgs();
		Test.Assert(!args.Handled);
		Test.Assert(args.Source == null);
		Test.Assert(args.ScreenX == 0);
		Test.Assert(args.LocalX == 0);
		Test.Assert(args.Modifiers == .None);
	}

	[Test]
	public static void MouseEventArgsReset()
	{
		let args = scope MouseEventArgs();
		args.ScreenX = 100;
		args.ScreenY = 200;
		args.Handled = true;
		args.Modifiers = .Shift;

		args.Reset();

		Test.Assert(args.ScreenX == 0);
		Test.Assert(args.ScreenY == 0);
		Test.Assert(!args.Handled);
		Test.Assert(args.Modifiers == .None);
	}

	[Test]
	public static void MouseButtonEventArgsButton()
	{
		let args = scope MouseButtonEventArgs();
		args.Button = .Right;
		args.ClickCount = 2;

		Test.Assert(args.Button == .Right);
		Test.Assert(args.ClickCount == 2);
	}

	[Test]
	public static void MouseWheelEventArgsDelta()
	{
		let args = scope MouseWheelEventArgs();
		args.DeltaX = 0;
		args.DeltaY = -120;

		Test.Assert(args.DeltaY == -120);
	}

	[Test]
	public static void KeyEventArgsModifiers()
	{
		let args = scope KeyEventArgs();
		args.Key = .A;
		args.Modifiers = (KeyModifiers)((int32)KeyModifiers.Ctrl | (int32)KeyModifiers.Shift);

		Test.Assert(args.HasModifier(.Ctrl));
		Test.Assert(args.HasModifier(.Shift));
		Test.Assert(!args.HasModifier(.Alt));
	}

	[Test]
	public static void TextInputEventArgsCharacter()
	{
		let args = scope TextInputEventArgs();
		args.Character = 'A';

		Test.Assert(args.Character == 'A');
	}

	[Test]
	public static void FocusEventArgsOtherElement()
	{
		let args = scope FocusEventArgs();
		let element = scope InputTestElement();
		args.OtherElement = element;

		Test.Assert(args.OtherElement == element);
	}
}

class HitTestingTests
{
	[Test]
	public static void HitTestSingleElement()
	{
		let context = new UIContext();
		defer delete context;

		let element = scope InputTestElement();
		element.Width = .Fixed(100);
		element.Height = .Fixed(100);
		context.RootElement = element;
		context.SetViewportSize(400, 300);
		context.Update(0, 0);

		// Hit inside
		let hit = context.HitTest(50, 50);
		Test.Assert(hit == element);

		// Miss outside
		let miss = context.HitTest(200, 200);
		Test.Assert(miss == null);
	}

	[Test]
	public static void HitTestNestedElements()
	{
		let context = new UIContext();
		defer delete context;

		// Use StackPanel for proper child layout
		let parent = scope StackPanel();
		parent.Width = .Fixed(200);
		parent.Height = .Fixed(200);
		parent.Orientation = .Vertical;

		let child = new InputTestElement();
		child.Width = .Fixed(100);
		child.Height = .Fixed(100);

		parent.AddChild(child);
		context.RootElement = parent;
		context.SetViewportSize(400, 300);
		context.Update(0, 0);

		// Child should be at (0,0) to (100,100) inside the StackPanel
		// But with Stretch alignment, it fills horizontally (0,0) to (200,100)
		let hitChild = context.HitTest(50, 50);
		Test.Assert(hitChild == child);

		// Below the child - hits parent
		let hitParent = context.HitTest(50, 150);
		Test.Assert(hitParent == parent);
	}

	[Test]
	public static void HitTestOverlappingElements()
	{
		let context = new UIContext();
		defer delete context;

		// Use Canvas for absolute positioning
		let parent = scope Canvas();
		parent.Width = .Fixed(200);
		parent.Height = .Fixed(200);

		// Two overlapping children - second added is "on top"
		let child1 = new InputTestElement();
		child1.Width = .Fixed(100);
		child1.Height = .Fixed(100);
		parent.SetLeft(child1, 0);
		parent.SetTop(child1, 0);

		let child2 = new InputTestElement();
		child2.Width = .Fixed(100);
		child2.Height = .Fixed(100);
		parent.SetLeft(child2, 50);
		parent.SetTop(child2, 50); // Overlaps at (50,50)-(100,100)

		parent.AddChild(child1);
		parent.AddChild(child2);
		context.RootElement = parent;
		context.SetViewportSize(400, 300);
		context.Update(0, 0);

		// Overlap region should hit child2 (added later, on top)
		let hit = context.HitTest(60, 60);
		Test.Assert(hit == child2);

		// child1 only region
		let hitChild1 = context.HitTest(25, 25);
		Test.Assert(hitChild1 == child1);
	}
}

class MouseEventTests
{
	[Test]
	public static void MouseEnterLeave()
	{
		let context = new UIContext();
		defer delete context;

		let element = scope InputTestElement();
		element.Width = .Fixed(100);
		element.Height = .Fixed(100);
		context.RootElement = element;
		context.SetViewportSize(400, 300);
		context.Update(0, 0);

		// Move into element
		context.ProcessMouseMove(50, 50);
		Test.Assert(element.IsMouseOver);
		Test.Assert(element.HasEvent("MouseEnter"));

		element.ClearEvents();

		// Move out of element
		context.ProcessMouseMove(200, 200);
		Test.Assert(!element.IsMouseOver);
		Test.Assert(element.HasEvent("MouseLeave"));
	}

	[Test]
	public static void MouseMoveEvent()
	{
		let context = new UIContext();
		defer delete context;

		let element = scope InputTestElement();
		element.Width = .Fixed(100);
		element.Height = .Fixed(100);
		context.RootElement = element;
		context.SetViewportSize(400, 300);
		context.Update(0, 0);

		context.ProcessMouseMove(50, 50);
		Test.Assert(element.HasEvent("MouseMove"));
	}

	[Test]
	public static void MouseDownUp()
	{
		let context = new UIContext();
		defer delete context;

		let element = scope InputTestElement();
		element.Width = .Fixed(100);
		element.Height = .Fixed(100);
		element.Focusable = true;
		context.RootElement = element;
		context.SetViewportSize(400, 300);
		context.Update(0, 0);

		context.ProcessMouseDown(.Left, 50, 50);
		Test.Assert(element.HasEvent("MouseDown"));
		Test.Assert(element.LastMouseDownArgs != null);
		Test.Assert(element.LastMouseDownArgs.Button == .Left);

		context.ProcessMouseUp(.Left, 50, 50);
		Test.Assert(element.HasEvent("MouseUp"));
	}

	[Test]
	public static void MouseClickSetsFocus()
	{
		let context = new UIContext();
		defer delete context;

		let element = scope InputTestElement();
		element.Width = .Fixed(100);
		element.Height = .Fixed(100);
		element.Focusable = true;
		context.RootElement = element;
		context.SetViewportSize(400, 300);
		context.Update(0, 0);

		Test.Assert(context.FocusedElement == null);

		context.ProcessMouseDown(.Left, 50, 50);

		Test.Assert(context.FocusedElement == element);
		Test.Assert(element.IsFocused);
	}

	[Test]
	public static void MouseWheelEvent()
	{
		let context = new UIContext();
		defer delete context;

		let element = scope InputTestElement();
		element.Width = .Fixed(100);
		element.Height = .Fixed(100);
		context.RootElement = element;
		context.SetViewportSize(400, 300);
		context.Update(0, 0);

		// Move mouse into element first
		context.ProcessMouseMove(50, 50);
		element.ClearEvents();

		context.ProcessMouseWheel(0, 120, 50, 50);
		Test.Assert(element.HasEvent("MouseWheel"));
	}
}

class KeyboardEventTests
{
	[Test]
	public static void KeyDownUp()
	{
		let context = new UIContext();
		defer delete context;

		let element = scope InputTestElement();
		element.Width = .Fixed(100);
		element.Height = .Fixed(100);
		element.Focusable = true;
		context.RootElement = element;
		context.SetViewportSize(400, 300);
		context.Update(0, 0);

		context.SetFocus(element);

		context.ProcessKeyDown(.A);
		Test.Assert(element.HasEvent("KeyDown"));
		Test.Assert(element.LastKeyDownArgs != null);
		Test.Assert(element.LastKeyDownArgs.Key == .A);

		context.ProcessKeyUp(.A);
		Test.Assert(element.HasEvent("KeyUp"));
	}

	[Test]
	public static void KeyEventsRequireFocus()
	{
		let context = new UIContext();
		defer delete context;

		let element = scope InputTestElement();
		element.Width = .Fixed(100);
		element.Height = .Fixed(100);
		element.Focusable = true;
		context.RootElement = element;
		context.SetViewportSize(400, 300);
		context.Update(0, 0);

		// No focus set
		context.ProcessKeyDown(.A);
		Test.Assert(!element.HasEvent("KeyDown"));
	}

	[Test]
	public static void TextInput()
	{
		let context = new UIContext();
		defer delete context;

		let element = scope InputTestElement();
		element.Width = .Fixed(100);
		element.Height = .Fixed(100);
		element.Focusable = true;
		context.RootElement = element;
		context.SetViewportSize(400, 300);
		context.Update(0, 0);

		context.SetFocus(element);
		context.ProcessTextInput('A');
		Test.Assert(element.HasEvent("TextInput"));
	}
}

class EventBubblingTests
{
	[Test]
	public static void EventBubblesToParent()
	{
		let context = new UIContext();
		defer delete context;

		let parent = scope InputTestElement();
		parent.Width = .Fixed(200);
		parent.Height = .Fixed(200);

		let child = new InputTestElement();
		child.Width = .Fixed(100);
		child.Height = .Fixed(100);

		parent.AddChild(child);
		context.RootElement = parent;
		context.SetViewportSize(400, 300);
		context.Update(0, 0);

		// Click on child
		context.ProcessMouseDown(.Left, 50, 50);

		// Both child and parent should receive event
		Test.Assert(child.HasEvent("MouseDown"));
		Test.Assert(parent.HasEvent("MouseDown"));
	}

	[Test]
	public static void HandledStopsBubbling()
	{
		let context = new UIContext();
		defer delete context;

		let parent = scope InputTestElement();
		parent.Width = .Fixed(200);
		parent.Height = .Fixed(200);

		let child = new InputTestElement();
		child.Width = .Fixed(100);
		child.Height = .Fixed(100);
		child.HandleEvents = true; // Mark events as handled

		parent.AddChild(child);
		context.RootElement = parent;
		context.SetViewportSize(400, 300);
		context.Update(0, 0);

		// Click on child
		context.ProcessMouseDown(.Left, 50, 50);

		// Child receives event
		Test.Assert(child.HasEvent("MouseDown"));
		// Parent should NOT receive event (stopped by Handled flag)
		Test.Assert(!parent.HasEvent("MouseDown"));
	}
}

class FocusTests
{
	[Test]
	public static void SetFocusFiresEvents()
	{
		let context = new UIContext();
		defer delete context;

		let element = scope InputTestElement();
		element.Width = .Fixed(100);
		element.Height = .Fixed(100);
		element.Focusable = true;
		context.RootElement = element;
		context.SetViewportSize(400, 300);
		context.Update(0, 0);

		context.SetFocus(element);
		Test.Assert(element.HasEvent("GotFocus"));
		Test.Assert(element.IsFocused);
	}

	[Test]
	public static void ChangeFocusFiresBothEvents()
	{
		let context = new UIContext();
		defer delete context;

		let element1 = new InputTestElement();
		element1.Width = .Fixed(100);
		element1.Height = .Fixed(50);
		element1.Focusable = true;

		let element2 = new InputTestElement();
		element2.Width = .Fixed(100);
		element2.Height = .Fixed(50);
		element2.Margin = Thickness(0, 50, 0, 0);
		element2.Focusable = true;

		let parent = scope InputTestElement();
		parent.Width = .Fixed(100);
		parent.Height = .Fixed(100);
		parent.AddChild(element1);
		parent.AddChild(element2);

		context.RootElement = parent;
		context.SetViewportSize(400, 300);
		context.Update(0, 0);

		context.SetFocus(element1);
		element1.ClearEvents();
		element2.ClearEvents();

		context.SetFocus(element2);

		Test.Assert(element1.HasEvent("LostFocus"));
		Test.Assert(!element1.IsFocused);
		Test.Assert(element2.HasEvent("GotFocus"));
		Test.Assert(element2.IsFocused);
	}
}

class MouseCaptureTests
{
	[Test]
	public static void CaptureReceivesEventsOutsideBounds()
	{
		let context = new UIContext();
		defer delete context;

		let element = scope InputTestElement();
		element.Width = .Fixed(100);
		element.Height = .Fixed(100);
		context.RootElement = element;
		context.SetViewportSize(400, 300);
		context.Update(0, 0);

		context.CaptureMouse(element);

		// Move outside bounds - should still receive event due to capture
		context.ProcessMouseMove(200, 200);
		Test.Assert(element.HasEvent("MouseMove"));

		context.ReleaseMouseCapture();

		element.ClearEvents();

		// After release, should not receive events outside bounds
		context.ProcessMouseMove(200, 200);
		Test.Assert(!element.HasEvent("MouseMove"));
	}
}

class InputManagerTests
{
	[Test]
	public static void InputManagerCreated()
	{
		let context = new UIContext();
		defer delete context;

		Test.Assert(context.InputManager != null);
	}

	[Test]
	public static void InputManagerTracksMousePosition()
	{
		let context = new UIContext();
		defer delete context;

		let element = scope InputTestElement();
		element.Width = .Fixed(100);
		element.Height = .Fixed(100);
		context.RootElement = element;
		context.SetViewportSize(400, 300);
		context.Update(0, 0);

		context.ProcessMouseMove(75, 80);

		Test.Assert(context.InputManager.MouseX == 75);
		Test.Assert(context.InputManager.MouseY == 80);
	}

	[Test]
	public static void InputManagerTracksButtonState()
	{
		let context = new UIContext();
		defer delete context;

		let element = scope InputTestElement();
		element.Width = .Fixed(100);
		element.Height = .Fixed(100);
		context.RootElement = element;
		context.SetViewportSize(400, 300);
		context.Update(0, 0);

		Test.Assert(!context.InputManager.IsButtonPressed(.Left));

		context.ProcessMouseDown(.Left, 50, 50);
		Test.Assert(context.InputManager.IsButtonPressed(.Left));

		context.ProcessMouseUp(.Left, 50, 50);
		Test.Assert(!context.InputManager.IsButtonPressed(.Left));
	}
}
