namespace Sedulous.UI;

using System;
using Sedulous.Core.Mathematics;
using Sedulous.Drawing;

/// A drawable that selects a child drawable based on the current ControlState.
/// Owns all child drawables.
public class StateListDrawable : Drawable
{
	private Drawable[(int)ControlState.Focused + 1] mDrawables;
	private Drawable mDefault ~ delete _;

	public this() { }

	public ~this()
	{
		for (let d in mDrawables)
			delete d;
	}

	/// Set the drawable for a specific state. Takes ownership.
	public void SetDrawable(ControlState state, Drawable drawable)
	{
		delete mDrawables[(int)state];
		mDrawables[(int)state] = drawable;
	}

	/// Set the default drawable used when no state-specific one exists. Takes ownership.
	public void SetDefault(Drawable drawable)
	{
		delete mDefault;
		mDefault = drawable;
	}

	/// Get the drawable for a specific state (falls back to default).
	public Drawable GetDrawable(ControlState state)
	{
		return mDrawables[(int)state] ?? mDefault;
	}

	/// Draw using default state (Normal).
	public override void Draw(DrawContext ctx, RectangleF bounds)
	{
		Draw(ctx, bounds, .Normal);
	}

	/// Draw using the specified control state.
	public override void Draw(DrawContext ctx, RectangleF bounds, ControlState state)
	{
		let drawable = GetDrawable(state);
		drawable?.Draw(ctx, bounds);
	}

	/// Delegate intrinsic size to the default drawable.
	public override Size2F IntrinsicSize => (mDefault != null) ? mDefault.IntrinsicSize : .(0, 0);
}
