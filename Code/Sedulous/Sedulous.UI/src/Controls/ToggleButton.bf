using System;
using Sedulous.Drawing;
using Sedulous.Mathematics;
using Sedulous.Foundation.Core;

namespace Sedulous.UI;

/// A button that toggles between checked and unchecked states.
public class ToggleButton : Button
{
	private bool? mIsChecked = false;

	// Checked changed event
	private EventAccessor<delegate void(ToggleButton, bool?)> mCheckedChangedEvent = new .() ~ delete _;

	/// Event fired when the checked state changes.
	public EventAccessor<delegate void(ToggleButton, bool?)> CheckedChanged => mCheckedChangedEvent;

	/// The checked state. Can be true, false, or null (indeterminate).
	public bool? IsChecked
	{
		get => mIsChecked;
		set
		{
			if (mIsChecked != value)
			{
				mIsChecked = value;
				OnCheckedChanged();
				UpdateControlState();
				InvalidateVisual();
			}
		}
	}

	/// Whether the toggle button supports three states (true, false, null).
	public bool IsThreeState { get; set; }

	public this()
	{
	}

	public this(StringView text) : base(text)
	{
	}

	protected override void OnClick()
	{
		// Toggle the state
		if (IsThreeState)
		{
			// Cycle: false -> true -> null -> false
			if (mIsChecked == false)
				IsChecked = true;
			else if (mIsChecked == true)
				IsChecked = null;
			else
				IsChecked = false;
		}
		else
		{
			// Simple toggle
			IsChecked = !(mIsChecked ?? false);
		}

		base.OnClick();
	}

	/// Called when the checked state changes.
	protected virtual void OnCheckedChanged()
	{
		mCheckedChangedEvent.[Friend]Invoke(this, mIsChecked);
	}

	protected override void UpdateControlState()
	{
		base.UpdateControlState();

		// Add checked state
		if (mIsChecked == true)
		{
			ControlState = (Sedulous.UI.ControlState)((int)ControlState | (int)Sedulous.UI.ControlState.Checked);
		}
	}
}

/// A checkbox control with a check mark visual.
public class CheckBox : ToggleButton
{
	private const float CheckBoxSize = 16.0f;
	private const float CheckBoxSpacing = 6.0f;

	public this()
	{
	}

	public this(StringView text) : base(text)
	{
	}

	protected override DesiredSize MeasureContent(SizeConstraints constraints)
	{
		// Checkbox is the check box plus spacing plus content
		let contentSize = base.MeasureContent(constraints);
		let totalWidth = CheckBoxSize + CheckBoxSpacing + contentSize.Width;
		let totalHeight = Math.Max(CheckBoxSize, contentSize.Height);
		return .(totalWidth, totalHeight);
	}

	protected override void OnRender(DrawContext drawContext)
	{
		let bounds = Bounds;

		// Draw the check box
		let boxX = bounds.X + BorderThickness.Left;
		let boxY = bounds.Y + BorderThickness.Top + (bounds.Height - BorderThickness.TotalVertical - CheckBoxSize) / 2;
		let boxRect = RectangleF(boxX, boxY, CheckBoxSize, CheckBoxSize);

		// Box background
		let bgColor = IsEnabled ? Color.White : Color(240, 240, 240);
		drawContext.FillRect(boxRect, bgColor);

		// Box border
		let borderColor = IsEnabled ? (IsFocused ? Color(0, 120, 215) : Color.Gray) : Color(180, 180, 180);
		drawContext.DrawRect(boxRect, borderColor, 1.0f);

		// Draw check mark if checked
		if (IsChecked == true)
		{
			let checkColor = IsEnabled ? Color(0, 120, 215) : Color(150, 150, 150);
			// Draw a simple checkmark using lines
			let cx = boxX + CheckBoxSize / 2;
			let cy = boxY + CheckBoxSize / 2;
			let size = CheckBoxSize * 0.3f;

			// Checkmark as a filled smaller rect for simplicity
			// Real implementation would draw actual check path
			drawContext.FillRect(.(cx - size, cy - size/2, size * 2, size), checkColor);
		}
		else if (IsChecked == null)
		{
			// Indeterminate state - draw a dash
			let dashColor = IsEnabled ? Color(0, 120, 215) : Color(150, 150, 150);
			let dashY = boxY + CheckBoxSize / 2 - 1;
			drawContext.FillRect(.(boxX + 3, dashY, CheckBoxSize - 6, 3), dashColor);
		}

		// Render content (label) to the right of the checkbox
		// Content rendering handled by base class but positioned differently
		RenderContent(drawContext);
	}

	protected override void ArrangeContent(RectangleF contentBounds)
	{
		// Offset content to the right of the checkbox
		let offsetBounds = RectangleF(
			contentBounds.X + CheckBoxSize + CheckBoxSpacing,
			contentBounds.Y,
			contentBounds.Width - CheckBoxSize - CheckBoxSpacing,
			contentBounds.Height
		);

		if (Content != null)
		{
			Content.Arrange(offsetBounds);
		}
	}
}
