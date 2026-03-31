namespace Sedulous.UI.Tests;

using Sedulous.UI;

/// Shared test utility for setting up a UIContext with a RootView.
static class TestHelper
{
	/// Create a RootView, add the content view to it, register with UIContext,
	/// set it as ActiveInputRoot, and run one frame of measure/layout.
	public static RootView SetupContext(UIContext ctx, View content, float w = 400, float h = 300)
	{
		let rootView = new RootView();
		rootView.SetSize(w, h);
		if (content != null)
			rootView.AddView(content);
		ctx.AddRootView(rootView);
		ctx.ActiveInputRoot = rootView;
		ctx.BeginFrame(0);
		ctx.UpdateRootView(rootView, 0);
		return rootView;
	}

	/// Run one frame (BeginFrame + UpdateRootView).
	public static void UpdateFrame(UIContext ctx, RootView rootView, float deltaTime = 0)
	{
		ctx.BeginFrame(deltaTime);
		ctx.UpdateRootView(rootView, deltaTime);
	}
}
