using System;
using Sedulous.Mathematics;
using Sedulous.Drawing;

namespace Sedulous.GUI;

/// A horizontal separator line in a menu.
public class MenuSeparator : Control
{
	private float mHeight = 9;
	private float mLineThickness = 1;
	private Color mLineColor = Color(80, 80, 80, 255);
	private float mMarginLeft = 8;
	private float mMarginRight = 8;

	/// Creates a new MenuSeparator.
	public this()
	{
		IsFocusable = false;
		IsTabStop = false;
		Background = Color(0, 0, 0, 0);  // Transparent
	}

	/// The control type name for theming.
	protected override StringView ControlTypeName => "MenuSeparator";

	/// The color of the separator line.
	public Color LineColor
	{
		get => mLineColor;
		set => mLineColor = value;
	}

	/// The thickness of the separator line.
	public float LineThickness
	{
		get => mLineThickness;
		set => mLineThickness = value;
	}

	// === Layout ===

	protected override DesiredSize MeasureOverride(SizeConstraints constraints)
	{
		// Return minimal width - separator will stretch to fill available space during arrange
		return .(0, mHeight);
	}

	// === Rendering ===

	protected override void RenderOverride(DrawContext ctx)
	{
		let bounds = ArrangedBounds;
		let centerY = bounds.Y + bounds.Height / 2;

		// Draw horizontal line
		let startX = bounds.X + mMarginLeft;
		let endX = bounds.Right - mMarginRight;

		ctx.DrawLine(.(startX, centerY), .(endX, centerY), mLineColor, mLineThickness);
	}
}
