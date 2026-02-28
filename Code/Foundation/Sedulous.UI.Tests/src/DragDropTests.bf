using System;
using System.Collections;

namespace Sedulous.UI.Tests;

class DragDataTests
{
	[Test]
	public static void DragDataSetAndGetData()
	{
		let data = scope DragData();
		let testObj = scope Object();

		data.SetData("text/plain", testObj);
		let retrieved = data.GetData("text/plain");
		Test.Assert(retrieved == testObj);
	}

	[Test]
	public static void DragDataHasData()
	{
		let data = scope DragData();
		let testObj = scope Object();

		Test.Assert(!data.HasData("text/plain"));

		data.SetData("text/plain", testObj);
		Test.Assert(data.HasData("text/plain"));
		Test.Assert(!data.HasData("text/html"));
	}

	[Test]
	public static void DragDataGetNonExistent()
	{
		let data = scope DragData();
		let result = data.GetData("nonexistent");
		Test.Assert(result == null);
	}

	[Test]
	public static void DragDataGetFormats()
	{
		let data = scope DragData();
		let obj1 = scope Object();
		let obj2 = scope Object();

		data.SetData("text/plain", obj1);
		data.SetData("text/html", obj2);

		let formats = scope List<StringView>();
		data.GetFormats(formats);

		Test.Assert(formats.Count == 2);
	}

	[Test]
	public static void DragDataOverwriteExisting()
	{
		let data = scope DragData();
		let obj1 = scope Object();
		let obj2 = scope Object();

		data.SetData("format", obj1);
		Test.Assert(data.GetData("format") == obj1);

		data.SetData("format", obj2);
		Test.Assert(data.GetData("format") == obj2);
	}
}

class DragEventArgsTests
{
	[Test]
	public static void DragEventArgsDefaultValues()
	{
		let args = scope DragEventArgs();
		Test.Assert(args.Data == null);
		Test.Assert(args.X == 0);
		Test.Assert(args.Y == 0);
		Test.Assert(args.Modifiers == .None);
		Test.Assert(args.Source == null);
		Test.Assert(args.Target == null);
		Test.Assert(args.AllowedEffects == .All);
		Test.Assert(args.Effect == .None);
		Test.Assert(!args.Handled);
	}

	[Test]
	public static void DragEventArgsSetProperties()
	{
		let args = scope DragEventArgs();
		let data = scope DragData();
		let source = scope TestDragSource();
		let target = scope TestDropTarget();

		args.Data = data;
		args.X = 100;
		args.Y = 200;
		args.Modifiers = .Ctrl;
		args.Source = source;
		args.Target = target;
		args.AllowedEffects = .Copy | .Move;
		args.Effect = .Copy;
		args.Handled = true;

		Test.Assert(args.Data == data);
		Test.Assert(args.X == 100);
		Test.Assert(args.Y == 200);
		Test.Assert(args.Modifiers == .Ctrl);
		Test.Assert(args.Source == source);
		Test.Assert(args.Target == target);
		Test.Assert(args.AllowedEffects == (.Copy | .Move));
		Test.Assert(args.Effect == .Copy);
		Test.Assert(args.Handled);
	}
}

class DragDropEffectsTests
{
	[Test]
	public static void DragDropEffectsValues()
	{
		Test.Assert((int)DragDropEffects.None == 0);
		Test.Assert((int)DragDropEffects.Copy == 1);
		Test.Assert((int)DragDropEffects.Move == 2);
		Test.Assert((int)DragDropEffects.Link == 4);
		Test.Assert((int)DragDropEffects.Scroll == 8);
	}

	[Test]
	public static void DragDropEffectsAll()
	{
		let all = DragDropEffects.All;
		Test.Assert(all.HasFlag(.Copy));
		Test.Assert(all.HasFlag(.Move));
		Test.Assert(all.HasFlag(.Link));
		Test.Assert(all.HasFlag(.Scroll));
	}

	[Test]
	public static void DragDropEffectsCombine()
	{
		let combined = DragDropEffects.Copy | DragDropEffects.Move;
		Test.Assert(combined.HasFlag(.Copy));
		Test.Assert(combined.HasFlag(.Move));
		Test.Assert(!combined.HasFlag(.Link));
	}
}

/// Test implementation of IDragSource.
class TestDragSource : UIElement, IDragSource
{
	public bool OnDragStartCalled;
	public bool OnDragCompleteCalled;
	public bool OnDragCancelledCalled;
	public DragDropEffects CompletedEffect;

	public DragData OnDragStart(float x, float y)
	{
		OnDragStartCalled = true;
		let data = new DragData();
		data.SetData("test", this);
		return data;
	}

	public DragDropEffects GetAllowedEffects()
	{
		return .Copy | .Move;
	}

	public void OnDragComplete(DragDropEffects effect)
	{
		OnDragCompleteCalled = true;
		CompletedEffect = effect;
	}

	public void OnDragCancelled()
	{
		OnDragCancelledCalled = true;
	}
}

/// Test implementation of IDropTarget.
class TestDropTarget : UIElement, IDropTarget
{
	public bool OnDragEnterCalled;
	public bool OnDragOverCalled;
	public bool OnDragLeaveCalled;
	public bool OnDropCalled;
	public bool AcceptDrop = true;
	public DragDropEffects DropEffect = .Copy;

	public void OnDragEnter(DragEventArgs args)
	{
		OnDragEnterCalled = true;
		if (AcceptDrop)
			args.Effect = DropEffect;
	}

	public void OnDragOver(DragEventArgs args)
	{
		OnDragOverCalled = true;
		if (AcceptDrop)
			args.Effect = DropEffect;
	}

	public void OnDragLeave(DragEventArgs args)
	{
		OnDragLeaveCalled = true;
	}

	public void OnDrop(DragEventArgs args)
	{
		OnDropCalled = true;
		if (AcceptDrop)
		{
			args.Effect = DropEffect;
			args.Handled = true;
		}
	}
}

class DragDropManagerTests
{
	[Test]
	public static void DragDropManagerInitialState()
	{
		let context = scope UIContext();
		let manager = scope DragDropManager(context);

		Test.Assert(!manager.IsDragging);
		Test.Assert(manager.DragData == null);
		Test.Assert(manager.DragSource == null);
		Test.Assert(manager.CurrentTarget == null);
	}

	[Test]
	public static void StartDragWithData()
	{
		let context = scope UIContext();
		let root = scope Border();
		root.Width = 800;
		root.Height = 600;
		context.RootElement = root;
		context.SetViewportSize(800, 600);
		context.Update(0.016f, 0.016);

		let manager = scope DragDropManager(context);
		let source = new TestDragSource();
		root.Child = source;

		let data = new DragData();
		let result = manager.StartDrag(source, data, .Copy | .Move, 100, 100);

		Test.Assert(result);
		Test.Assert(manager.IsDragging);
		Test.Assert(manager.DragData == data);
		Test.Assert(manager.DragSource == source);

		// Clean up
		manager.CancelDrag();
	}

	[Test]
	public static void StartDragWithNullDataFails()
	{
		let context = scope UIContext();
		let root = scope Border();
		context.RootElement = root;

		let manager = scope DragDropManager(context);
		let source = new TestDragSource();
		root.Child = source;

		let result = manager.StartDrag(source, null, .All, 100, 100);
		Test.Assert(!result);
		Test.Assert(!manager.IsDragging);
	}

	[Test]
	public static void StartDragFromIDragSource()
	{
		let context = scope UIContext();
		let root = scope Border();
		root.Width = 800;
		root.Height = 600;
		context.RootElement = root;
		context.SetViewportSize(800, 600);
		context.Update(0.016f, 0.016);

		let manager = scope DragDropManager(context);
		let source = new TestDragSource();
		root.Child = source;

		let result = manager.StartDrag(source, 50, 50);

		Test.Assert(result);
		Test.Assert(source.OnDragStartCalled);
		Test.Assert(manager.IsDragging);

		manager.CancelDrag();
	}

	[Test]
	public static void CancelDragNotifiesSource()
	{
		let context = scope UIContext();
		let root = scope Border();
		root.Width = 800;
		root.Height = 600;
		context.RootElement = root;
		context.SetViewportSize(800, 600);
		context.Update(0.016f, 0.016);

		let manager = scope DragDropManager(context);
		let source = new TestDragSource();
		root.Child = source;

		manager.StartDrag(source, 50, 50);
		Test.Assert(manager.IsDragging);

		manager.CancelDrag();

		Test.Assert(!manager.IsDragging);
		Test.Assert(source.OnDragCancelledCalled);
	}

	[Test]
	public static void CancelDragWhenNotDraggingDoesNothing()
	{
		let context = scope UIContext();
		let manager = scope DragDropManager(context);

		// Should not throw or crash
		manager.CancelDrag();
		Test.Assert(!manager.IsDragging);
	}
}
