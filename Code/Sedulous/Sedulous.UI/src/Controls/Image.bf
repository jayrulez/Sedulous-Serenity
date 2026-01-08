using System;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// Image display widget.
class Image : Widget
{
	private TextureHandle mSource;
	private Stretch mStretch = .Uniform;
	private Color mTint = .White;
	private float mSourceWidth;
	private float mSourceHeight;

	/// Creates an empty image widget.
	public this()
	{
		IsFocusable = false;
	}

	/// Creates an image widget with a texture.
	public this(TextureHandle source, float width, float height)
	{
		mSource = source;
		mSourceWidth = width;
		mSourceHeight = height;
		IsFocusable = false;
	}

	/// Gets or sets the texture source.
	public TextureHandle Source
	{
		get => mSource;
		set { mSource = value; InvalidateMeasure(); }
	}

	/// Gets or sets the source image width.
	public float SourceWidth
	{
		get => mSourceWidth;
		set { if (mSourceWidth != value) { mSourceWidth = value; InvalidateMeasure(); } }
	}

	/// Gets or sets the source image height.
	public float SourceHeight
	{
		get => mSourceHeight;
		set { if (mSourceHeight != value) { mSourceHeight = value; InvalidateMeasure(); } }
	}

	/// Gets or sets the stretch mode.
	public Stretch StretchMode
	{
		get => mStretch;
		set { if (mStretch != value) { mStretch = value; InvalidateArrange(); } }
	}

	/// Gets or sets the tint color.
	public Color Tint
	{
		get => mTint;
		set => mTint = value;
	}

	/// Measures the image size.
	protected override Vector2 MeasureOverride(Vector2 availableSize)
	{
		if (mSourceWidth <= 0 || mSourceHeight <= 0)
			return Vector2(Padding.HorizontalThickness, Padding.VerticalThickness);

		var desiredWidth = mSourceWidth;
		var desiredHeight = mSourceHeight;

		// Apply stretch mode for measuring
		switch (mStretch)
		{
		case .None:
			// Use natural size
			break;
		case .Fill:
			// Fill available space
			if (availableSize.X < float.MaxValue)
				desiredWidth = availableSize.X - Padding.HorizontalThickness;
			if (availableSize.Y < float.MaxValue)
				desiredHeight = availableSize.Y - Padding.VerticalThickness;
		case .Uniform:
			// Scale uniformly to fit
			let availW = availableSize.X - Padding.HorizontalThickness;
			let availH = availableSize.Y - Padding.VerticalThickness;
			if (availW < float.MaxValue && availH < float.MaxValue)
			{
				let scaleX = availW / mSourceWidth;
				let scaleY = availH / mSourceHeight;
				let scale = Math.Min(scaleX, scaleY);
				desiredWidth = mSourceWidth * scale;
				desiredHeight = mSourceHeight * scale;
			}
		case .UniformToFill:
			// Scale uniformly to fill
			let availW2 = availableSize.X - Padding.HorizontalThickness;
			let availH2 = availableSize.Y - Padding.VerticalThickness;
			if (availW2 < float.MaxValue && availH2 < float.MaxValue)
			{
				let scaleX = availW2 / mSourceWidth;
				let scaleY = availH2 / mSourceHeight;
				let scale = Math.Max(scaleX, scaleY);
				desiredWidth = mSourceWidth * scale;
				desiredHeight = mSourceHeight * scale;
			}
		}

		return Vector2(
			desiredWidth + Padding.HorizontalThickness,
			desiredHeight + Padding.VerticalThickness
		);
	}

	/// Renders the image.
	protected override void OnRender(DrawContext dc)
	{
		if (mSourceWidth <= 0 || mSourceHeight <= 0)
			return;

		let contentBounds = ContentBounds;
		var destRect = contentBounds;

		switch (mStretch)
		{
		case .None:
			// Center at natural size
			destRect = RectangleF(
				contentBounds.X + (contentBounds.Width - mSourceWidth) / 2,
				contentBounds.Y + (contentBounds.Height - mSourceHeight) / 2,
				mSourceWidth,
				mSourceHeight
			);
		case .Fill:
			// Fill entire content bounds (stretching)
			destRect = contentBounds;
		case .Uniform:
			// Scale uniformly to fit within bounds
			{
				let scaleX = contentBounds.Width / mSourceWidth;
				let scaleY = contentBounds.Height / mSourceHeight;
				let scale = Math.Min(scaleX, scaleY);
				let scaledWidth = mSourceWidth * scale;
				let scaledHeight = mSourceHeight * scale;
				destRect = RectangleF(
					contentBounds.X + (contentBounds.Width - scaledWidth) / 2,
					contentBounds.Y + (contentBounds.Height - scaledHeight) / 2,
					scaledWidth,
					scaledHeight
				);
			}
		case .UniformToFill:
			// Scale uniformly to fill bounds (may crop)
			{
				let scaleX = contentBounds.Width / mSourceWidth;
				let scaleY = contentBounds.Height / mSourceHeight;
				let scale = Math.Max(scaleX, scaleY);
				let scaledWidth = mSourceWidth * scale;
				let scaledHeight = mSourceHeight * scale;
				destRect = RectangleF(
					contentBounds.X + (contentBounds.Width - scaledWidth) / 2,
					contentBounds.Y + (contentBounds.Height - scaledHeight) / 2,
					scaledWidth,
					scaledHeight
				);
			}
		}

		dc.DrawImage(mSource, destRect, mTint);
	}
}
