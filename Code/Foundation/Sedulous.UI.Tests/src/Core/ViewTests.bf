using System;
using Sedulous.UI;
using Sedulous.Core.Mathematics;

namespace Sedulous.UI.Tests;

/// A concrete View subclass for testing.
class TestView : View
{
	public float DesiredWidth;
	public float DesiredHeight;

	public this(float desiredWidth = 0, float desiredHeight = 0)
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
}

class ViewTests
{
	[Test]
	public static void New_HasValidId()
	{
		let v = scope TestView();
		Test.Assert(v.Id.IsValid);
	}

	[Test]
	public static void TwoViews_HaveDifferentIds()
	{
		let a = scope TestView();
		let b = scope TestView();
		Test.Assert(a.Id != b.Id);
	}

	[Test]
	public static void New_HasNoParent()
	{
		let v = scope TestView();
		Test.Assert(v.Parent == null);
	}

	[Test]
	public static void New_DefaultState()
	{
		let v = scope TestView();
		Test.Assert(v.Visibility == .Visible);
		Test.Assert(v.Alpha == 1.0f);
		Test.Assert(!v.ClipToBounds);
		Test.Assert(v.IsHitTestVisible);
		Test.Assert(v.Enabled);
		Test.Assert(!v.Focusable);
		Test.Assert(!v.IsFocused);
		Test.Assert(!v.IsHovered);
		Test.Assert(!v.IsPressed);
		Test.Assert(!v.IsPendingDeletion);
		Test.Assert(v.CursorType == .Default);
	}

	[Test]
	public static void Measure_StoresDimensions()
	{
		let v = scope TestView(80, 40);
		v.Measure(.MakeAtMost(200), .MakeAtMost(200));
		Test.Assert(v.MeasuredWidth == 80);
		Test.Assert(v.MeasuredHeight == 40);
	}

	[Test]
	public static void Measure_Gone_ReturnsZero()
	{
		let v = scope TestView(80, 40);
		v.Visibility = .Gone;
		v.Measure(.MakeAtMost(200), .MakeAtMost(200));
		Test.Assert(v.MeasuredWidth == 0);
		Test.Assert(v.MeasuredHeight == 0);
	}

	[Test]
	public static void Layout_SetsGeometry()
	{
		let v = scope TestView();
		v.Layout(10, 20, 100, 50);
		Test.Assert(v.Left == 10);
		Test.Assert(v.Top == 20);
		Test.Assert(v.Width == 100);
		Test.Assert(v.Height == 50);
	}

	[Test]
	public static void Layout_ClearsLayoutDirty()
	{
		let v = scope TestView();
		v.InvalidateLayout();
		Test.Assert(v.IsLayoutDirty);
		v.Layout(0, 0, 100, 100);
		Test.Assert(!v.IsLayoutDirty);
	}

	[Test]
	public static void HitTest_InsideBounds_ReturnsSelf()
	{
		let v = scope TestView();
		v.Layout(10, 10, 100, 100);
		let hit = v.HitTest(.(50, 50));
		Test.Assert(hit == v);
	}

	[Test]
	public static void HitTest_OutsideBounds_ReturnsNull()
	{
		let v = scope TestView();
		v.Layout(10, 10, 100, 100);
		Test.Assert(v.HitTest(.(5, 5)) == null);
		Test.Assert(v.HitTest(.(200, 200)) == null);
	}

	[Test]
	public static void HitTest_Invisible_ReturnsNull()
	{
		let v = scope TestView();
		v.Layout(0, 0, 100, 100);
		v.Visibility = .Invisible;
		Test.Assert(v.HitTest(.(50, 50)) == null);
	}

	[Test]
	public static void HitTest_NotHitTestVisible_ReturnsNull()
	{
		let v = scope TestView();
		v.Layout(0, 0, 100, 100);
		v.IsHitTestVisible = false;
		Test.Assert(v.HitTest(.(50, 50)) == null);
	}

	[Test]
	public static void HitTest_PendingDeletion_ReturnsNull()
	{
		let v = scope TestView();
		v.Layout(0, 0, 100, 100);
		v.[Friend]mIsPendingDeletion = true;
		Test.Assert(v.HitTest(.(50, 50)) == null);
	}

	[Test]
	public static void EffectiveCursor_Default_WalksParent()
	{
		// Without a parent, returns Default
		let v = scope TestView();
		Test.Assert(v.EffectiveCursor == .Default);

		// Set cursor on view
		v.CursorType = .Pointer;
		Test.Assert(v.EffectiveCursor == .Pointer);
	}

	[Test]
	public static void ContentBounds_AccountsForPadding()
	{
		let v = scope TestView();
		v.Padding = .(10, 20, 30, 40);
		v.Layout(0, 0, 200, 200);
		let cb = v.ContentBounds;
		Test.Assert(cb.X == 10);
		Test.Assert(cb.Y == 20);
		Test.Assert(cb.Width == 160); // 200 - 10 - 30
		Test.Assert(cb.Height == 140); // 200 - 20 - 40
	}

	[Test]
	public static void Alpha_ClampsToRange()
	{
		let v = scope TestView();
		v.Alpha = 1.5f;
		Test.Assert(v.Alpha == 1.0f);
		v.Alpha = -0.5f;
		Test.Assert(v.Alpha == 0.0f);
		v.Alpha = 0.5f;
		Test.Assert(v.Alpha == 0.5f);
	}

	[Test]
	public static void MinMax_ConstraintsMeasurement()
	{
		let v = scope TestView(10, 10);
		v.MinWidth = 50;
		v.MinHeight = 30;
		v.Measure(.MakeAtMost(200), .MakeAtMost(200));
		Test.Assert(v.MeasuredWidth == 50);
		Test.Assert(v.MeasuredHeight == 30);
	}

	[Test]
	public static void PointToLocal_NoTransform()
	{
		let v = scope TestView();
		v.Layout(10, 20, 100, 100);
		let local = v.PointToLocal(.(50, 60));
		Test.Assert(local.X == 40); // 50 - 10
		Test.Assert(local.Y == 40); // 60 - 20
	}
}
