using System;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// Simple text label widget.
class Label : Widget
{
	private String mText ~ delete _;
	private FontHandle mFont;
	private float mFontSize = 14.0f;
	private Color mTextColor = .White;
	private TextAlignment mTextAlignment = .Start;
	private TextWrapping mTextWrapping = .NoWrap;
	private TextTrimming mTextTrimming = .None;

	/// Creates an empty label.
	public this()
	{
		IsFocusable = false;
	}

	/// Creates a label with the specified text.
	public this(StringView text)
	{
		mText = new String(text);
		IsFocusable = false;
	}

	/// Gets or sets the label text.
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

	/// Gets or sets the font size in pixels.
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

	/// Gets or sets the text alignment.
	public TextAlignment TextAlign
	{
		get => mTextAlignment;
		set { if (mTextAlignment != value) { mTextAlignment = value; InvalidateVisual(); } }
	}

	/// Gets or sets the text wrapping mode.
	public TextWrapping TextWrap
	{
		get => mTextWrapping;
		set { if (mTextWrapping != value) { mTextWrapping = value; InvalidateMeasure(); } }
	}

	/// Gets or sets the text trimming mode.
	public TextTrimming Trimming
	{
		get => mTextTrimming;
		set { if (mTextTrimming != value) { mTextTrimming = value; InvalidateVisual(); } }
	}

	/// Measures the label size based on text content.
	protected override Vector2 MeasureOverride(Vector2 availableSize)
	{
		if (mText == null || mText.IsEmpty)
			return Vector2(Padding.HorizontalThickness, Padding.VerticalThickness + mFontSize);

		// TODO: Use font renderer for accurate measurement
		// For now, estimate based on character count
		let textWidth = mText.Length * mFontSize * 0.5f;
		let textHeight = mFontSize;

		var width = textWidth + Padding.HorizontalThickness;
		var height = textHeight + Padding.VerticalThickness;

		// Handle wrapping
		if (mTextWrapping != .NoWrap && availableSize.X < width)
		{
			let maxWidth = availableSize.X - Padding.HorizontalThickness;
			if (maxWidth > 0)
			{
				let lineCount = (int)Math.Ceiling(textWidth / maxWidth);
				height = (lineCount * mFontSize) + Padding.VerticalThickness;
				width = availableSize.X;
			}
		}

		return Vector2(width, height);
	}

	/// Renders the label.
	protected override void OnRender(DrawContext dc)
	{
		if (mText == null || mText.IsEmpty)
			return;

		let contentBounds = ContentBounds;

		dc.DrawText(
			mText,
			mFont,
			mFontSize,
			contentBounds,
			mTextColor,
			mTextAlignment,
			.Start,
			mTextWrapping != .NoWrap
		);
	}
}
