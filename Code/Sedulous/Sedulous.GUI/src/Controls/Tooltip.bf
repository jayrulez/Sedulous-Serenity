using System;
using Sedulous.Mathematics;
using Sedulous.Drawing;

namespace Sedulous.GUI;

/// A popup that displays helpful information when hovering over a control.
public class Tooltip : ContentControl
{
	// Text content (alternative to setting Content directly)
	private String mText ~ delete _;

	/// Creates a new Tooltip.
	public this()
	{
		// Tooltips have default styling
		Background = Color(50, 50, 50, 240);
		Foreground = Color(220, 220, 220, 255);
		Padding = .(8, 4, 8, 4);

		// Use inherited properties with tooltip-specific defaults
		CornerRadius = 4;
		base.BorderColor = Color(100, 100, 100, 255);
		base.BorderThickness = 1;

		// Don't stretch to fill container - size to content
		HorizontalAlignment = .Left;
		VerticalAlignment = .Top;
	}

	/// Creates a new Tooltip with text.
	public this(StringView text) : this()
	{
		Text = text;
	}

	/// The control type name for theming.
	protected override StringView ControlTypeName => "Tooltip";

	/// The text displayed in the tooltip.
	/// Setting this creates a TextBlock as content.
	public StringView Text
	{
		get => mText ?? "";
		set
		{
			if (mText == null)
				mText = new String(value);
			else
				mText.Set(value);

			// Create or update TextBlock content
			if (Content == null || !(Content is TextBlock))
			{
				Content = new TextBlock(value);
			}
			else if (let textBlock = Content as TextBlock)
			{
				textBlock.Text = value;
			}
		}
	}

	// === Layout ===

	protected override DesiredSize MeasureOverride(SizeConstraints constraints)
	{
		// Measure content
		var size = base.MeasureOverride(constraints);

		// Add padding
		size.Width += Padding.Left + Padding.Right;
		size.Height += Padding.Top + Padding.Bottom;

		return size;
	}

	protected override void ArrangeOverride(RectangleF contentBounds)
	{
		// Arrange content with padding
		let innerBounds = RectangleF(
			contentBounds.X + Padding.Left,
			contentBounds.Y + Padding.Top,
			contentBounds.Width - Padding.Left - Padding.Right,
			contentBounds.Height - Padding.Top - Padding.Bottom
		);

		if (Content != null && Content.Visibility != .Collapsed)
			Content.Arrange(innerBounds);
	}

	// === Rendering ===

	protected override void RenderOverride(DrawContext ctx)
	{
		let bounds = ArrangedBounds;
		let cornerRadius = CornerRadius;
		let borderColor = BorderColor;
		let borderThickness = BorderThickness;

		// Draw background with rounded corners
		if (Background.A > 0)
		{
			if (cornerRadius > 0)
				ctx.FillRoundedRect(bounds, cornerRadius, Background);
			else
				ctx.FillRect(bounds, Background);
		}

		// Render content
		Content?.Render(ctx);

		// Draw border
		if (borderColor.A > 0 && borderThickness > 0)
		{
			if (cornerRadius > 0)
				ctx.DrawRoundedRect(bounds, cornerRadius, borderColor, borderThickness);
			else
				ctx.DrawRect(bounds, borderColor, borderThickness);
		}
	}
}
