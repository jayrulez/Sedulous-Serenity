using System;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// Clickable button widget.
class Button : Widget
{
	private String mText ~ delete _;
	private FontHandle mFont;
	private float mFontSize = 14.0f;
	private Color mTextColor = .White;
	private Color mBackgroundColor = Color(60, 60, 60, 255);
	private Color mHoverColor = Color(80, 80, 80, 255);
	private Color mPressedColor = Color(40, 40, 40, 255);
	private Color mDisabledColor = Color(45, 45, 45, 255);
	private Color mBorderColor = Color(100, 100, 100, 255);
	private float mBorderWidth = 1.0f;
	private CornerRadius mCornerRadius = .Uniform(4);

	private bool mIsHovered;
	private bool mIsPressed;
	private bool mIsDefault;
	private bool mIsCancel;

	/// Event raised when the button is clicked.
	public Event<delegate void()> OnClick ~ _.Dispose();

	/// Creates an empty button.
	public this()
	{
		IsFocusable = true;
		Padding = Thickness(12, 6, 12, 6);
	}

	/// Creates a button with the specified text.
	public this(StringView text)
	{
		mText = new String(text);
		IsFocusable = true;
		Padding = Thickness(12, 6, 12, 6);
	}

	/// Gets or sets the button text.
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

	/// Gets or sets the text color.
	public Color TextColor
	{
		get => mTextColor;
		set => mTextColor = value;
	}

	/// Gets or sets the background color.
	public Color BackgroundColor
	{
		get => mBackgroundColor;
		set => mBackgroundColor = value;
	}

	/// Gets or sets the hover color.
	public Color HoverColor
	{
		get => mHoverColor;
		set => mHoverColor = value;
	}

	/// Gets or sets the pressed color.
	public Color PressedColor
	{
		get => mPressedColor;
		set => mPressedColor = value;
	}

	/// Gets or sets the border color.
	public Color BorderColor
	{
		get => mBorderColor;
		set => mBorderColor = value;
	}

	/// Gets or sets the border width.
	public float BorderWidth
	{
		get => mBorderWidth;
		set => mBorderWidth = value;
	}

	/// Gets or sets the corner radius.
	public CornerRadius CornerRadius
	{
		get => mCornerRadius;
		set => mCornerRadius = value;
	}

	/// Gets whether the button is currently pressed.
	public bool IsPressed => mIsPressed;

	/// Gets whether the button is currently hovered.
	public bool IsHovered => mIsHovered;

	/// Gets or sets whether this is the default button (responds to Enter).
	public bool IsDefault
	{
		get => mIsDefault;
		set => mIsDefault = value;
	}

	/// Gets or sets whether this is the cancel button (responds to Escape).
	public bool IsCancel
	{
		get => mIsCancel;
		set => mIsCancel = value;
	}

	/// Measures the button size.
	protected override Vector2 MeasureOverride(Vector2 availableSize)
	{
		var textWidth = 0.0f;
		var textHeight = mFontSize;

		if (mText != null && !mText.IsEmpty)
		{
			// TODO: Use font renderer for accurate measurement
			textWidth = mText.Length * mFontSize * 0.5f;
		}

		return Vector2(
			textWidth + Padding.HorizontalThickness,
			textHeight + Padding.VerticalThickness
		);
	}

	/// Renders the button.
	protected override void OnRender(DrawContext dc)
	{
		let bounds = Bounds;

		// Determine background color based on state
		var bgColor = mBackgroundColor;
		if (!IsEnabled)
			bgColor = mDisabledColor;
		else if (mIsPressed)
			bgColor = mPressedColor;
		else if (mIsHovered)
			bgColor = mHoverColor;

		// Draw background
		if (mCornerRadius.IsZero)
		{
			dc.FillRect(bounds, bgColor);
			if (mBorderWidth > 0)
				dc.DrawRect(bounds, mBorderColor, mBorderWidth);
		}
		else
		{
			dc.FillRoundedRect(bounds, mCornerRadius, bgColor);
			if (mBorderWidth > 0)
				dc.DrawRoundedRect(bounds, mCornerRadius, mBorderColor, mBorderWidth);
		}

		// Draw focus indicator
		if (IsFocused)
		{
			let focusBounds = RectangleF(
				bounds.X + 2,
				bounds.Y + 2,
				bounds.Width - 4,
				bounds.Height - 4
			);
			dc.DrawRoundedRect(focusBounds, mCornerRadius, Color(100, 150, 255, 200), 1);
		}

		// Draw text
		if (mText != null && !mText.IsEmpty)
		{
			let textColor = IsEnabled ? mTextColor : Color(150, 150, 150, 255);
			dc.DrawText(mText, mFont, mFontSize, ContentBounds, textColor, .Center, .Center, false);
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

			// Fire click if still over button
			if (mIsHovered && IsEnabled)
			{
				OnClick();
			}
			return true;
		}
		return false;
	}

	/// Handles key down.
	protected override bool OnKeyDown(KeyEventArgs e)
	{
		if (e.Key == .Space || e.Key == .Enter)
		{
			if (IsEnabled)
			{
				mIsPressed = true;
				InvalidateVisual();
				return true;
			}
		}
		return false;
	}

	/// Handles key up.
	protected override bool OnKeyUp(KeyEventArgs e)
	{
		if ((e.Key == .Space || e.Key == .Enter) && mIsPressed)
		{
			mIsPressed = false;
			InvalidateVisual();

			if (IsEnabled)
			{
				OnClick();
			}
			return true;
		}
		return false;
	}
}
