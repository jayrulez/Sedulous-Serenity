using System;
using Sedulous.Drawing;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// How an image is stretched to fill available space.
public enum Stretch
{
	/// No stretching - image displays at natural size.
	None,
	/// Stretch to fill, may distort aspect ratio.
	Fill,
	/// Scale uniformly to fit within bounds (may leave empty space).
	Uniform,
	/// Scale uniformly to fill bounds (may clip image).
	UniformToFill
}

/// Displays an image.
public class Image : Control
{
	private ITexture mSource;
	private Stretch mStretch = .Uniform;
	private HorizontalAlignment mHorizontalContentAlignment = .Center;
	private VerticalAlignment mVerticalContentAlignment = .Center;

	/// The image texture to display.
	public ITexture Source
	{
		get => mSource;
		set
		{
			if (mSource != value)
			{
				mSource = value;
				InvalidateMeasure();
			}
		}
	}

	/// How the image is stretched to fill available space.
	public Stretch Stretch
	{
		get => mStretch;
		set
		{
			if (mStretch != value)
			{
				mStretch = value;
				InvalidateArrange();
			}
		}
	}

	/// Horizontal alignment of the image within the control.
	public HorizontalAlignment HorizontalContentAlignment
	{
		get => mHorizontalContentAlignment;
		set { mHorizontalContentAlignment = value; InvalidateArrange(); }
	}

	/// Vertical alignment of the image within the control.
	public VerticalAlignment VerticalContentAlignment
	{
		get => mVerticalContentAlignment;
		set { mVerticalContentAlignment = value; InvalidateArrange(); }
	}

	public this()
	{
		Focusable = false;
	}

	public this(ITexture source) : this()
	{
		mSource = source;
	}

	protected override DesiredSize MeasureContent(SizeConstraints constraints)
	{
		if (mSource == null)
			return .(0, 0);

		let imageWidth = (float)mSource.Width;
		let imageHeight = (float)mSource.Height;

		switch (mStretch)
		{
		case .None:
			// Natural size
			return .(imageWidth, imageHeight);

		case .Fill:
			// Use available space if constrained, otherwise natural size
			let w = constraints.MaxWidth != SizeConstraints.Infinity ? constraints.MaxWidth : imageWidth;
			let h = constraints.MaxHeight != SizeConstraints.Infinity ? constraints.MaxHeight : imageHeight;
			return .(w, h);

		case .Uniform:
			// Scale to fit within constraints while preserving aspect ratio
			if (constraints.MaxWidth == SizeConstraints.Infinity && constraints.MaxHeight == SizeConstraints.Infinity)
				return .(imageWidth, imageHeight);

			let maxW = constraints.MaxWidth != SizeConstraints.Infinity ? constraints.MaxWidth : float.MaxValue;
			let maxH = constraints.MaxHeight != SizeConstraints.Infinity ? constraints.MaxHeight : float.MaxValue;
			let scale = Math.Min(maxW / imageWidth, maxH / imageHeight);
			return .(imageWidth * scale, imageHeight * scale);

		case .UniformToFill:
			// Scale to fill constraints while preserving aspect ratio
			if (constraints.MaxWidth == SizeConstraints.Infinity && constraints.MaxHeight == SizeConstraints.Infinity)
				return .(imageWidth, imageHeight);

			let fillMaxW = constraints.MaxWidth != SizeConstraints.Infinity ? constraints.MaxWidth : imageWidth;
			let fillMaxH = constraints.MaxHeight != SizeConstraints.Infinity ? constraints.MaxHeight : imageHeight;
			return .(fillMaxW, fillMaxH);
		}
	}

	protected override void RenderContent(DrawContext drawContext)
	{
		if (mSource == null)
			return;

		let bounds = ContentBounds;
		let imageWidth = (float)mSource.Width;
		let imageHeight = (float)mSource.Height;

		// Calculate destination rectangle based on stretch mode
		var destRect = RectangleF(0, 0, 0, 0);
		var srcRect = RectangleF(0, 0, imageWidth, imageHeight);

		switch (mStretch)
		{
		case .None:
			// Draw at natural size, aligned within bounds
			destRect = AlignRect(imageWidth, imageHeight, bounds);

		case .Fill:
			// Fill entire bounds (distorts if necessary)
			destRect = bounds;

		case .Uniform:
			// Scale uniformly to fit
			let scale = Math.Min(bounds.Width / imageWidth, bounds.Height / imageHeight);
			let scaledWidth = imageWidth * scale;
			let scaledHeight = imageHeight * scale;
			destRect = AlignRect(scaledWidth, scaledHeight, bounds);

		case .UniformToFill:
			// Scale uniformly to fill (clips if necessary)
			let fillScale = Math.Max(bounds.Width / imageWidth, bounds.Height / imageHeight);
			let fillWidth = imageWidth * fillScale;
			let fillHeight = imageHeight * fillScale;
			destRect = AlignRect(fillWidth, fillHeight, bounds);

			// Adjust source rectangle for clipping
			if (fillWidth > bounds.Width || fillHeight > bounds.Height)
			{
				// Calculate what portion of image is visible
				let visibleRatioX = bounds.Width / fillWidth;
				let visibleRatioY = bounds.Height / fillHeight;
				let srcW = imageWidth * visibleRatioX;
				let srcH = imageHeight * visibleRatioY;

				var srcX = 0f;
				var srcY = 0f;

				if (mHorizontalContentAlignment == .Center)
					srcX = (imageWidth - srcW) / 2;
				else if (mHorizontalContentAlignment == .Right)
					srcX = imageWidth - srcW;

				if (mVerticalContentAlignment == .Center)
					srcY = (imageHeight - srcH) / 2;
				else if (mVerticalContentAlignment == .Bottom)
					srcY = imageHeight - srcH;

				srcRect = .(srcX, srcY, srcW, srcH);
				destRect = bounds;
			}
		}

		// Draw the image
		drawContext.DrawImage(mSource, destRect, srcRect, Color.White);
	}

	/// Aligns a rectangle of given size within the bounds.
	private RectangleF AlignRect(float width, float height, RectangleF bounds)
	{
		var x = bounds.X;
		var y = bounds.Y;

		switch (mHorizontalContentAlignment)
		{
		case .Left: x = bounds.X;
		case .Center: x = bounds.X + (bounds.Width - width) / 2;
		case .Right: x = bounds.Right - width;
		case .Stretch: x = bounds.X;
		}

		switch (mVerticalContentAlignment)
		{
		case .Top: y = bounds.Y;
		case .Center: y = bounds.Y + (bounds.Height - height) / 2;
		case .Bottom: y = bounds.Bottom - height;
		case .Stretch: y = bounds.Y;
		}

		return .(x, y, width, height);
	}
}
