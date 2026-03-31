namespace Sedulous.UI.Toolkit;

using System;
using Sedulous.UI;
using Sedulous.Drawing;
using Sedulous.Core.Mathematics;

/// Horizontal tool strip with themed background.
/// A thin wrapper around LinearLayout for organizing toolbar buttons and separators.
public class Toolbar : LinearLayout
{
	public this()
	{
		Orientation = .Horizontal;
		BaselineAligned = false;
		Padding = .(4, 2, 4, 2);
		Spacing = 2;
		MinHeight = 36;
		Gravity = .CenterV;
	}

	/// Convenience: add a button with the given text.
	public Button AddButton(StringView text)
	{
		let btn = new Button(text);
		btn.Padding = .(8, 4, 8, 4);
		AddView(btn);
		return btn;
	}

	/// Convenience: add a vertical separator.
	public Separator AddSeparator()
	{
		let sep = new Separator();
		sep.Orientation = .Vertical;
		sep.MinHeight = 20;
		AddView(sep);
		return sep;
	}

	protected override void OnDraw(DrawContext ctx)
	{
		let theme = Context?.Theme;
		let palette = theme?.Palette ?? Palette.Dark;

		// Background
		let bg = theme?.GetColor("Toolbar", "background") ?? Palette.Darken(palette.Surface, 0.1f);
		ctx.FillRect(.(0, 0, Width, Height), bg);

		// Bottom border
		let borderColor = theme?.GetColor("Toolbar", "border") ?? palette.Border;
		ctx.FillRect(.(0, Height - 1, Width, 1), borderColor);

		// Draw children
		base.OnDraw(ctx);
	}
}
