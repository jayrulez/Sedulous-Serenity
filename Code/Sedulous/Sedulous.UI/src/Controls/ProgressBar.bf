using System;
using Sedulous.Drawing;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// Displays a progress indicator.
public class ProgressBar : Control
{
	private float mValue = 0;
	private float mMinimum = 0;
	private float mMaximum = 100;
	private bool mIsIndeterminate = false;
	private Orientation mOrientation = .Horizontal;

	// Colors
	private Color? mProgressColor = null;
	private Color? mTrackColor = null;

	/// The current value (between Minimum and Maximum).
	public float Value
	{
		get => mValue;
		set
		{
			let clamped = Math.Clamp(value, mMinimum, mMaximum);
			if (mValue != clamped)
			{
				mValue = clamped;
				InvalidateVisual();
			}
		}
	}

	/// The minimum value.
	public float Minimum
	{
		get => mMinimum;
		set
		{
			if (mMinimum != value)
			{
				mMinimum = value;
				if (mValue < mMinimum) mValue = mMinimum;
				if (mMaximum < mMinimum) mMaximum = mMinimum;
				InvalidateVisual();
			}
		}
	}

	/// The maximum value.
	public float Maximum
	{
		get => mMaximum;
		set
		{
			if (mMaximum != value)
			{
				mMaximum = value;
				if (mValue > mMaximum) mValue = mMaximum;
				if (mMinimum > mMaximum) mMinimum = mMaximum;
				InvalidateVisual();
			}
		}
	}

	/// Whether to show an indeterminate (animated) progress indicator.
	public bool IsIndeterminate
	{
		get => mIsIndeterminate;
		set { mIsIndeterminate = value; InvalidateVisual(); }
	}

	/// The orientation of the progress bar.
	public Orientation Orientation
	{
		get => mOrientation;
		set { mOrientation = value; InvalidateMeasure(); }
	}

	/// The color of the progress fill.
	public Color? ProgressColor
	{
		get => mProgressColor;
		set { mProgressColor = value; InvalidateVisual(); }
	}

	/// The color of the track behind the progress.
	public Color? TrackColor
	{
		get => mTrackColor;
		set { mTrackColor = value; InvalidateVisual(); }
	}

	/// Gets the current progress as a value between 0 and 1.
	public float Progress
	{
		get
		{
			let range = mMaximum - mMinimum;
			if (range <= 0) return 0;
			return (mValue - mMinimum) / range;
		}
	}

	public this()
	{
		Focusable = false;
		MinHeight = 4;
		MinWidth = 100;
	}

	protected override DesiredSize MeasureContent(SizeConstraints constraints)
	{
		if (mOrientation == .Horizontal)
			return .(constraints.MaxWidth != SizeConstraints.Infinity ? constraints.MaxWidth : 100, 20);
		else
			return .(20, constraints.MaxHeight != SizeConstraints.Infinity ? constraints.MaxHeight : 100);
	}

	protected override void RenderContent(DrawContext drawContext)
	{
		let bounds = ContentBounds;

		// Get colors from theme or defaults
		let trackColor = mTrackColor ?? Color(220, 220, 220);
		let progressColor = mProgressColor ?? Color(0, 120, 215);

		// Draw track
		drawContext.FillRect(bounds, trackColor);

		// Draw progress fill
		if (!mIsIndeterminate)
		{
			var fillRect = RectangleF(0, 0, 0, 0);
			let progress = Progress;

			if (mOrientation == .Horizontal)
			{
				let fillWidth = bounds.Width * progress;
				fillRect = .(bounds.X, bounds.Y, fillWidth, bounds.Height);
			}
			else
			{
				let fillHeight = bounds.Height * progress;
				fillRect = .(bounds.X, bounds.Bottom - fillHeight, bounds.Width, fillHeight);
			}

			if (fillRect.Width > 0 && fillRect.Height > 0)
				drawContext.FillRect(fillRect, progressColor);
		}
		else
		{
			// Indeterminate mode - draw a sliding block
			// This would need animation support for proper implementation
			let blockSize = mOrientation == .Horizontal ? bounds.Width * 0.3f : bounds.Height * 0.3f;
			if (mOrientation == .Horizontal)
			{
				let blockX = bounds.X + bounds.Width * 0.35f; // Static position for now
				drawContext.FillRect(.(blockX, bounds.Y, blockSize, bounds.Height), progressColor);
			}
			else
			{
				let blockY = bounds.Y + bounds.Height * 0.35f;
				drawContext.FillRect(.(bounds.X, blockY, bounds.Width, blockSize), progressColor);
			}
		}

		// Draw border if specified
		let borderColor = BorderBrush;
		if (borderColor.HasValue)
		{
			drawContext.DrawRect(bounds, borderColor.Value, 1);
		}
	}
}
