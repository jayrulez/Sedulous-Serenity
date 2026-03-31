using System;
using Sedulous.UI;

namespace Sedulous.UI.Tests;

class ElementHandleTests
{
	[Test]
	public static void Empty_IsNotValid()
	{
		let handle = ViewHandle.Empty;
		Test.Assert(!handle.IsValid);
	}

	[Test]
	public static void FromView_IsValid()
	{
		let view = scope TestView();
		ViewHandle handle = view;
		Test.Assert(handle.IsValid);
		Test.Assert(handle.Id == view.Id);
	}

	[Test]
	public static void FromNull_IsNotValid()
	{
		ViewHandle handle = .(null);
		Test.Assert(!handle.IsValid);
	}

	[Test]
	public static void TryResolve_RegisteredView_Succeeds()
	{
		let ctx = scope UIContext();
		let view = scope TestView();
		ctx.RegisterElement(view);

		ViewHandle handle = view;
		let resolved = handle.TryResolve(ctx);
		Test.Assert(resolved == view);
	}

	[Test]
	public static void TryResolve_UnregisteredView_ReturnsNull()
	{
		let ctx = scope UIContext();
		let view = scope TestView();
		// Don't register

		ViewHandle handle = view;
		let resolved = handle.TryResolve(ctx);
		Test.Assert(resolved == null);
	}

	[Test]
	public static void TryResolve_PendingDeletion_ReturnsNull()
	{
		let ctx = scope UIContext();
		let view = scope TestView();
		ctx.RegisterElement(view);
		view.[Friend]mIsPendingDeletion = true;

		ViewHandle handle = view;
		let resolved = handle.TryResolve(ctx);
		Test.Assert(resolved == null);
	}

	[Test]
	public static void TryResolve_NullContext_ReturnsNull()
	{
		let view = scope TestView();
		ViewHandle handle = view;
		Test.Assert(handle.TryResolve(null) == null);
	}

	[Test]
	public static void Clear_InvalidatesHandle()
	{
		let view = scope TestView();
		ViewHandle handle = view;
		Test.Assert(handle.IsValid);
		handle.Clear();
		Test.Assert(!handle.IsValid);
	}

	[Test]
	public static void TypedHandle_ResolvesToCorrectType()
	{
		let ctx = scope UIContext();
		let view = scope TestView();
		ctx.RegisterElement(view);

		ElementHandle<TestView> handle = view;
		let resolved = handle.TryResolve(ctx);
		Test.Assert(resolved == view);
	}
}
