using System;

namespace Sedulous.UI.Tests;

/// Test clipboard implementation.
class TestClipboard : IClipboard
{
	private String mText = new .() ~ delete _;

	public Result<void> GetText(String outText)
	{
		outText.Set(mText);
		return .Ok;
	}

	public Result<void> SetText(StringView text)
	{
		mText.Set(text);
		return .Ok;
	}

	public bool HasText => !mText.IsEmpty;
}

/// Simple test element for testing.
/// Extends CompositeControl to support children for hierarchy tests.
class TestElement : CompositeControl
{
	public int MeasureCallCount;
	public int ArrangeCallCount;
	public int RenderCallCount;

	protected override DesiredSize MeasureOverride(SizeConstraints constraints)
	{
		MeasureCallCount++;
		return base.MeasureOverride(constraints);
	}

	protected override void ArrangeOverride(Sedulous.Mathematics.RectangleF contentBounds)
	{
		ArrangeCallCount++;
		base.ArrangeOverride(contentBounds);
	}

	protected override void OnRender(Sedulous.Drawing.DrawContext drawContext)
	{
		RenderCallCount++;
	}
}

class UIContextTests
{
	[Test]
	public static void ContextCreation()
	{
		let context = scope UIContext();
		Test.Assert(context.RootElement == null);
		Test.Assert(context.FocusedElement == null);
		Test.Assert(context.ViewportWidth == 0);
		Test.Assert(context.ViewportHeight == 0);
	}

	[Test]
	public static void SetViewportSize()
	{
		let context = scope UIContext();
		context.SetViewportSize(800, 600);
		Test.Assert(context.ViewportWidth == 800);
		Test.Assert(context.ViewportHeight == 600);
		Test.Assert(context.IsLayoutDirty);
	}

	[Test]
	public static void RegisterClipboard()
	{
		let context = scope UIContext();
		let clipboard = scope TestClipboard();
		context.RegisterClipboard(clipboard);
		Test.Assert(context.Clipboard == clipboard);
	}

	[Test]
	public static void SetRootElement()
	{
		let context = scope UIContext();
		let root = scope TestElement();
		context.RootElement = root;
		Test.Assert(context.RootElement == root);
		Test.Assert(context.IsLayoutDirty);
	}

	[Test]
	public static void UpdatePerformsLayout()
	{
		let context = scope UIContext();
		let root = scope TestElement();
		context.RootElement = root;
		context.SetViewportSize(800, 600);

		Test.Assert(context.IsLayoutDirty);
		context.Update(0.016f, 0.016);
		Test.Assert(!context.IsLayoutDirty);
		Test.Assert(root.MeasureCallCount == 1);
		Test.Assert(root.ArrangeCallCount == 1);
	}

	[Test]
	public static void SetFocus()
	{
		let context = scope UIContext();
		let element = scope TestElement();
		element.Focusable = true;
		context.RootElement = element;

		context.SetFocus(element);
		Test.Assert(context.FocusedElement == element);
		Test.Assert(element.IsFocused);
	}

	[Test]
	public static void ChangeFocus()
	{
		let context = scope UIContext();
		let root = scope TestElement();
		let child1 = new TestElement();
		let child2 = new TestElement();
		child1.Focusable = true;
		child2.Focusable = true;
		root.AddChild(child1);
		root.AddChild(child2);
		context.RootElement = root;

		context.SetFocus(child1);
		Test.Assert(child1.IsFocused);
		Test.Assert(!child2.IsFocused);

		context.SetFocus(child2);
		Test.Assert(!child1.IsFocused);
		Test.Assert(child2.IsFocused);
	}

	[Test]
	public static void MouseCapture()
	{
		let context = scope UIContext();
		let element = scope TestElement();
		context.RootElement = element;

		Test.Assert(context.CapturedElement == null);
		context.CaptureMouse(element);
		Test.Assert(context.CapturedElement == element);
		context.ReleaseMouseCapture();
		Test.Assert(context.CapturedElement == null);
	}

	[Test]
	public static void DebugSettingsDefault()
	{
		let context = scope UIContext();
		Test.Assert(!context.DebugSettings.ShowLayoutBounds);
		Test.Assert(!context.DebugSettings.ShowMargins);
		Test.Assert(!context.DebugSettings.ShowPadding);
	}

	[Test]
	public static void HitTestReturnsRoot()
	{
		let context = scope UIContext();
		let root = scope TestElement();
		root.Width = .Fixed(100);
		root.Height = .Fixed(100);
		context.RootElement = root;
		context.SetViewportSize(800, 600);
		context.Update(0.016f, 0.016);

		let hit = context.HitTest(50, 50);
		Test.Assert(hit == root);
	}

	[Test]
	public static void HitTestOutsideBoundsReturnsNull()
	{
		let context = scope UIContext();
		let root = scope TestElement();
		root.Width = .Fixed(100);
		root.Height = .Fixed(100);
		context.RootElement = root;
		context.SetViewportSize(800, 600);
		context.Update(0.016f, 0.016);

		let hit = context.HitTest(500, 500);
		Test.Assert(hit == null);
	}
}
