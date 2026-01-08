using System;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// Toggleable checkbox control.
class CheckBox : Widget
{
	private String mText ~ delete _;
	private FontHandle mFont;
	private float mFontSize = 14.0f;
	private bool mIsChecked;
	private bool mIsThreeState;
	private CheckState mCheckState = .Unchecked;

	private Color mTextColor = .White;
	private Color mBoxColor = Color(60, 60, 60, 255);
	private Color mBoxHoverColor = Color(80, 80, 80, 255);
	private Color mBoxPressedColor = Color(40, 40, 40, 255);
	private Color mBorderColor = Color(100, 100, 100, 255);
	private Color mCheckColor = Color(60, 180, 60, 255);
	private Color mIndeterminateColor = Color(100, 150, 200, 255);

	private float mBoxSize = 16;
	private float mSpacing = 6;
	private CornerRadius mCornerRadius = .Uniform(3);

	private bool mIsHovered;
	private bool mIsPressed;

	/// Check state for three-state checkboxes.
	public enum CheckState
	{
		Unchecked,
		Checked,
		Indeterminate
	}

	/// Event raised when the checked state changes.
	public Event<delegate void(bool)> OnCheckedChanged ~ _.Dispose();

	/// Event raised when the check state changes (three-state).
	public Event<delegate void(CheckState)> OnCheckStateChanged ~ _.Dispose();

	/// Creates an empty checkbox.
	public this()
	{
		IsFocusable = true;
		Padding = Thickness(4, 2, 4, 2);
	}

	/// Creates a checkbox with the specified text.
	public this(StringView text)
	{
		mText = new String(text);
		IsFocusable = true;
		Padding = Thickness(4, 2, 4, 2);
	}

	/// Gets or sets the checkbox text.
	public StringView Text
	{
		get => mText ?? "";
		set
		{
			if (mText == null)
				mText = new String(value);
			else if (mText != value)
				mText.Set(value);
			else
				return;

			InvalidateMeasure();
		}
	}

	/// Gets or sets the font.
	public FontHandle Font
	{
		get => mFont;
		set { mFont = value; InvalidateMeasure(); }
	}

	/// Gets or sets the font size.
	public float FontSize
	{
		get => mFontSize;
		set { if (mFontSize != value) { mFontSize = value; InvalidateMeasure(); } }
	}

	/// Gets or sets whether the checkbox is checked.
	public bool IsChecked
	{
		get => mIsChecked;
		set
		{
			if (mIsChecked != value)
			{
				mIsChecked = value;
				mCheckState = value ? .Checked : .Unchecked;
				InvalidateVisual();
				OnCheckedChanged(mIsChecked);
				OnCheckStateChanged(mCheckState);
			}
		}
	}

	/// Gets or sets whether this is a three-state checkbox.
	public bool IsThreeState
	{
		get => mIsThreeState;
		set => mIsThreeState = value;
	}

	/// Gets or sets the check state (for three-state checkboxes).
	public CheckState State
	{
		get => mCheckState;
		set
		{
			if (mCheckState != value)
			{
				mCheckState = value;
				mIsChecked = (value == .Checked);
				InvalidateVisual();
				OnCheckedChanged(mIsChecked);
				OnCheckStateChanged(mCheckState);
			}
		}
	}

	/// Gets or sets the text color.
	public Color TextColor
	{
		get => mTextColor;
		set => mTextColor = value;
	}

	/// Gets or sets the box background color.
	public Color BoxColor
	{
		get => mBoxColor;
		set => mBoxColor = value;
	}

	/// Gets or sets the check mark color.
	public Color CheckColor
	{
		get => mCheckColor;
		set => mCheckColor = value;
	}

	/// Gets or sets the box size.
	public float BoxSize
	{
		get => mBoxSize;
		set { if (mBoxSize != value) { mBoxSize = value; InvalidateMeasure(); } }
	}

	/// Gets or sets the spacing between box and text.
	public float Spacing
	{
		get => mSpacing;
		set { if (mSpacing != value) { mSpacing = value; InvalidateMeasure(); } }
	}

	/// Gets or sets the corner radius.
	public CornerRadius CornerRadius
	{
		get => mCornerRadius;
		set => mCornerRadius = value;
	}

	/// Measures the checkbox size.
	protected override Vector2 MeasureOverride(Vector2 availableSize)
	{
		var textWidth = 0.0f;
		var textHeight = mFontSize;

		if (mText != null && !mText.IsEmpty)
		{
			// TODO: Use font renderer for accurate measurement
			textWidth = mText.Length * mFontSize * 0.5f;
		}

		let totalWidth = mBoxSize + (textWidth > 0 ? mSpacing + textWidth : 0);
		let totalHeight = Math.Max(mBoxSize, textHeight);

		return Vector2(
			totalWidth + Padding.HorizontalThickness,
			totalHeight + Padding.VerticalThickness
		);
	}

	/// Toggles the checkbox state.
	public void Toggle()
	{
		if (!IsEnabled)
			return;

		if (mIsThreeState)
		{
			// Cycle: Unchecked -> Checked -> Indeterminate -> Unchecked
			switch (mCheckState)
			{
			case .Unchecked:
				State = .Checked;
			case .Checked:
				State = .Indeterminate;
			case .Indeterminate:
				State = .Unchecked;
			}
		}
		else
		{
			IsChecked = !mIsChecked;
		}
	}

	/// Renders the checkbox.
	protected override void OnRender(DrawContext dc)
	{
		let bounds = ContentBounds;

		// Calculate box position (vertically centered)
		let boxY = bounds.Y + (bounds.Height - mBoxSize) / 2;
		let boxRect = RectangleF(bounds.X, boxY, mBoxSize, mBoxSize);

		// Determine box color based on state
		var bgColor = mBoxColor;
		if (!IsEnabled)
			bgColor = Color(45, 45, 45, 255);
		else if (mIsPressed)
			bgColor = mBoxPressedColor;
		else if (mIsHovered)
			bgColor = mBoxHoverColor;

		// Draw box background
		if (mCornerRadius.IsZero)
		{
			dc.FillRect(boxRect, bgColor);
			dc.DrawRect(boxRect, mBorderColor, 1);
		}
		else
		{
			dc.FillRoundedRect(boxRect, mCornerRadius, bgColor);
			dc.DrawRoundedRect(boxRect, mCornerRadius, mBorderColor, 1);
		}

		// Draw check mark or indeterminate indicator
		if (mCheckState == .Checked)
		{
			// Simplified checkmark using filled rect (proper checkmark would need line drawing)
			let checkPadding = mBoxSize * 0.2f;
			let checkRect = RectangleF(
				boxRect.X + checkPadding,
				boxRect.Y + checkPadding,
				mBoxSize - checkPadding * 2,
				mBoxSize - checkPadding * 2
			);
			dc.FillRoundedRect(checkRect, .Uniform(2), mCheckColor);
		}
		else if (mCheckState == .Indeterminate)
		{
			// Draw horizontal line for indeterminate state
			let linePadding = mBoxSize * 0.25f;
			let lineHeight = mBoxSize * 0.15f;
			let lineRect = RectangleF(
				boxRect.X + linePadding,
				boxRect.Y + (mBoxSize - lineHeight) / 2,
				mBoxSize - linePadding * 2,
				lineHeight
			);
			dc.FillRect(lineRect, mIndeterminateColor);
		}

		// Draw focus ring
		if (IsFocused)
		{
			let focusRect = RectangleF(
				boxRect.X - 2,
				boxRect.Y - 2,
				mBoxSize + 4,
				mBoxSize + 4
			);
			dc.DrawRoundedRect(focusRect, mCornerRadius, Color(100, 150, 255, 200), 1);
		}

		// Draw text
		if (mText != null && !mText.IsEmpty)
		{
			let textX = bounds.X + mBoxSize + mSpacing;
			let textRect = RectangleF(textX, bounds.Y, bounds.Width - mBoxSize - mSpacing, bounds.Height);
			let textColor = IsEnabled ? mTextColor : Color(150, 150, 150, 255);
			dc.DrawText(mText, mFont, mFontSize, textRect, textColor, .Start, .Center, false);
		}
	}

	/// Handles mouse enter.
	protected override bool OnMouseEnter(MouseEventArgs e)
	{
		mIsHovered = true;
		InvalidateVisual();
		return false;
	}

	/// Handles mouse leave.
	protected override bool OnMouseLeave(MouseEventArgs e)
	{
		mIsHovered = false;
		mIsPressed = false;
		InvalidateVisual();
		return false;
	}

	/// Handles mouse down.
	protected override bool OnMouseDown(MouseButtonEventArgs e)
	{
		if (e.Button == .Left && IsEnabled)
		{
			mIsPressed = true;
			Context?.Input.CaptureMouse(this);
			InvalidateVisual();
			return true;
		}
		return false;
	}

	/// Handles mouse up.
	protected override bool OnMouseUp(MouseButtonEventArgs e)
	{
		if (e.Button == .Left && mIsPressed)
		{
			Context?.Input.ReleaseMouse();
			mIsPressed = false;
			InvalidateVisual();

			// Toggle if still over checkbox
			if (mIsHovered && IsEnabled)
			{
				Toggle();
			}
			return true;
		}
		return false;
	}

	/// Handles key down.
	protected override bool OnKeyDown(KeyEventArgs e)
	{
		if (e.Key == .Space && IsEnabled)
		{
			mIsPressed = true;
			InvalidateVisual();
			return true;
		}
		return false;
	}

	/// Handles key up.
	protected override bool OnKeyUp(KeyEventArgs e)
	{
		if (e.Key == .Space && mIsPressed)
		{
			mIsPressed = false;
			InvalidateVisual();

			if (IsEnabled)
			{
				Toggle();
			}
			return true;
		}
		return false;
	}
}
