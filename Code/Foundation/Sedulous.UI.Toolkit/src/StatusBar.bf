namespace Sedulous.UI.Toolkit;

using System;
using Sedulous.UI;
using Sedulous.Drawing;
using Sedulous.Core.Mathematics;

/// Bottom status strip with themed background and top border.
/// A thin wrapper around LinearLayout for displaying status information.
public class StatusBar : LinearLayout
{
	private Label mDefaultLabel;

	public this()
	{
		Orientation = .Horizontal;
		BaselineAligned = false;
		Padding = .(8, 2, 8, 2);
		Spacing = 12;
		MinHeight = 24;
		Gravity = .CenterV;
	}

	/// Set the default label text. Creates the label on first use.
	public void SetText(StringView text)
	{
		if (mDefaultLabel == null)
		{
			mDefaultLabel = new Label(text);
			mDefaultLabel.FontSize = 12;
			InsertView(mDefaultLabel, 0);
		}
		else
		{
			mDefaultLabel.Text = text;
		}
	}

	/// Add a new label section to the status bar. Returns the label for customization.
	public Label AddSection(StringView text = "")
	{
		let label = new Label(text);
		label.FontSize = 12;
		AddView(label);
		return label;
	}

	protected override void OnDraw(DrawContext ctx)
	{
		let theme = Context?.Theme;
		let palette = theme?.Palette ?? Palette.Dark;

		// Background
		let bg = theme?.GetColor("StatusBar", "background") ?? Palette.Darken(palette.Surface, 0.15f);
		ctx.FillRect(.(0, 0, Width, Height), bg);

		// Top border
		let borderColor = theme?.GetColor("StatusBar", "borderColor") ?? palette.Border;
		ctx.FillRect(.(0, 0, Width, 1), borderColor);

		// Draw children
		base.OnDraw(ctx);
	}
}
