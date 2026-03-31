using System;
using Sedulous.UI;

namespace Sedulous.UI.Tests;

class ControlStateTests
{
	[Test]
	public static void Default_IsNormal()
	{
		let view = scope TestView();
		Test.Assert(view.GetControlState() == .Normal);
	}

	[Test]
	public static void Disabled_TakesPriority()
	{
		let view = scope TestView();
		view.Enabled = false;
		view.[Friend]mIsHovered = true;
		view.[Friend]mIsPressed = true;
		view.[Friend]mIsFocused = true;
		Test.Assert(view.GetControlState() == .Disabled);
	}

	[Test]
	public static void Pressed_OverridesFocusedAndHovered()
	{
		let view = scope TestView();
		view.[Friend]mIsPressed = true;
		view.[Friend]mIsFocused = true;
		view.[Friend]mIsHovered = true;
		Test.Assert(view.GetControlState() == .Pressed);
	}

	[Test]
	public static void Focused_OverridesHovered()
	{
		let view = scope TestView();
		view.[Friend]mIsFocused = true;
		view.[Friend]mIsHovered = true;
		Test.Assert(view.GetControlState() == .Focused);
	}

	[Test]
	public static void Hovered_WhenOnlyHovered()
	{
		let view = scope TestView();
		view.[Friend]mIsHovered = true;
		Test.Assert(view.GetControlState() == .Hover);
	}
}
