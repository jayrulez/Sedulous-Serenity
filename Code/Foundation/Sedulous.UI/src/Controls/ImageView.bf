namespace Sedulous.UI;

using System;
using Sedulous.Drawing;
using Sedulous.Core.Mathematics;

/// Image display control with scaling options.
/// Does not own the IImageData — caller manages image lifetime.
public class ImageView : View
{
	private IImageData mSource;
	private ScaleType mScaleType = .FitCenter;
	private Color? mTint;

	public IImageData Source
	{
		get => mSource;
		set
		{
			mSource = value;
			InvalidateLayout();
		}
	}

	public ScaleType ScaleType
	{
		get => mScaleType;
		set { mScaleType = value; Invalidate(); }
	}

	public Color? Tint
	{
		get => mTint;
		set { mTint = value; Invalidate(); }
	}

	protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		float desiredW = 0;
		float desiredH = 0;

		if (mSource != null)
		{
			desiredW = mSource.Width;
			desiredH = mSource.Height;
		}

		desiredW += Padding.Horizontal;
		desiredH += Padding.Vertical;

		SetMeasuredDimension(
			widthSpec.Resolve(desiredW, MinWidth, MaxWidth),
			heightSpec.Resolve(desiredH, MinHeight, MaxHeight)
		);
	}

	protected override void OnDraw(DrawContext ctx)
	{
		if (mSource == null)
			return;

		let content = ContentBounds;
		let tint = mTint ?? Color.White;
		let srcRect = RectangleF(0, 0, mSource.Width, mSource.Height);

		RectangleF destRect;

		switch (mScaleType)
		{
		case .None:
			destRect = .(content.X, content.Y, mSource.Width, mSource.Height);
		case .FitCenter:
			destRect = FitCenter(content, mSource.Width, mSource.Height);
		case .FillBounds:
			destRect = content;
		case .CenterCrop:
			destRect = CenterCrop(content, mSource.Width, mSource.Height);
		}

		ctx.DrawImage(mSource, destRect, srcRect, tint);
	}

	private static RectangleF FitCenter(RectangleF bounds, uint32 imgW, uint32 imgH)
	{
		if (imgW == 0 || imgH == 0)
			return bounds;

		float aspect = (float)imgW / (float)imgH;
		float boundsAspect = bounds.Width / bounds.Height;

		float w, h;
		if (aspect > boundsAspect)
		{
			w = bounds.Width;
			h = w / aspect;
		}
		else
		{
			h = bounds.Height;
			w = h * aspect;
		}

		return .(bounds.X + (bounds.Width - w) * 0.5f, bounds.Y + (bounds.Height - h) * 0.5f, w, h);
	}

	private static RectangleF CenterCrop(RectangleF bounds, uint32 imgW, uint32 imgH)
	{
		if (imgW == 0 || imgH == 0)
			return bounds;

		float aspect = (float)imgW / (float)imgH;
		float boundsAspect = bounds.Width / bounds.Height;

		float w, h;
		if (aspect < boundsAspect)
		{
			w = bounds.Width;
			h = w / aspect;
		}
		else
		{
			h = bounds.Height;
			w = h * aspect;
		}

		return .(bounds.X + (bounds.Width - w) * 0.5f, bounds.Y + (bounds.Height - h) * 0.5f, w, h);
	}
}

/// How an ImageView scales its source to fit its bounds.
public enum ScaleType
{
	/// Draw at natural size, top-left aligned. No scaling.
	None,
	/// Scale to fit within bounds, centered, maintain aspect ratio.
	FitCenter,
	/// Stretch to fill bounds exactly. Does not maintain aspect ratio.
	FillBounds,
	/// Scale to fill bounds, crop overflow, centered. Maintains aspect ratio.
	CenterCrop
}
