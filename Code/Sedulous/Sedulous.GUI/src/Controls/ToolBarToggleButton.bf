using System;
using Sedulous.Mathematics;
using Sedulous.Drawing;

namespace Sedulous.GUI;

/// A toggle button for use in toolbars.
/// Shows checked state with background highlight.
public class ToolBarToggleButton : ToggleButton
{
	private ToolBarButtonDisplayMode mDisplayMode = .TextOnly;

	/// Creates a new ToolBarToggleButton.
	public this() : base()
	{
	}

	/// Creates a new ToolBarToggleButton with text.
	public this(StringView text) : base(text)
	{
	}

	/// Gets the button text (from TextBlock content).
	public StringView Text
	{
		get
		{
			if (let textBlock = Content as TextBlock)
				return textBlock.Text;
			return "";
		}
	}

	/// The control type name for theming.
	protected override StringView ControlTypeName => "ToolBarToggleButton";

	/// The display mode for this button.
	public ToolBarButtonDisplayMode DisplayMode
	{
		get => mDisplayMode;
		set
		{
			if (mDisplayMode != value)
			{
				mDisplayMode = value;
				InvalidateLayout();
			}
		}
	}

	/// Renders the toggle button with flat toolbar styling.
	protected override void RenderOverride(DrawContext ctx)
	{
		let bounds = ArrangedBounds;

		// Background when checked, hovered, or pressed
		if (IsChecked || IsHovered || IsPressed)
		{
			Color bgColor;
			if (IsPressed)
				bgColor = Color(60, 120, 200, 255);
			else if (IsChecked)
				bgColor = Color(60, 100, 160, 255);  // Slightly different for checked state
			else
				bgColor = Color(80, 80, 80, 255);

			ctx.FillRect(bounds, bgColor);

			// Border
			let borderColor = IsChecked ? Color(80, 140, 200, 255) : Color(100, 100, 100, 255);
			ctx.DrawRect(bounds, borderColor, 1);
		}

		// Render content (text)
		Content?.Render(ctx);
	}
}
