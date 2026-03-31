namespace Sedulous.UI;

using System;
using Sedulous.Drawing;
using Sedulous.Core.Mathematics;

/// Progress indicator (0..1).
public class ProgressBar : View
{
	private float mProgress = 0;
	private Color mTrackColor = .(0.2f, 0.2f, 0.25f, 1.0f);
	private Color mFillColor = .(0.3f, 0.5f, 0.9f, 1.0f);

	public float Progress
	{
		get => mProgress;
		set
		{
			let clamped = Math.Clamp(value, 0, 1);
			if (mProgress != clamped)
			{
				mProgress = clamped;
				Invalidate();
			}
		}
	}

	public Color TrackColor
	{
		get => mTrackColor;
		set { mTrackColor = value; Invalidate(); }
	}

	public Color FillColor
	{
		get => mFillColor;
		set { mFillColor = value; Invalidate(); }
	}

	protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		let theme = Context?.Theme;
		float desiredH = theme?.GetDimension("ProgressBar", "height") ?? 16;
		SetMeasuredDimension(
			widthSpec.Resolve(0, MinWidth, MaxWidth),
			heightSpec.Resolve(desiredH, MinHeight, MaxHeight)
		);
	}

	protected override void OnDraw(DrawContext ctx)
	{
		let theme = Context?.Theme;
		let palette = theme?.Palette ?? Palette.Dark;

		// Track
		let trackDrawable = theme?.GetDrawable("ProgressBar", "track");
		if (trackDrawable != null)
		{
			trackDrawable.Draw(ctx, .(0, 0, Width, Height));
		}
		else
		{
			let trackColor = (mTrackColor.A > 0) ? mTrackColor : (theme?.GetColor("ProgressBar", "track") ?? .(0.2f, 0.2f, 0.25f, 1.0f));
			let radius = Height * 0.5f;
			ctx.FillRoundedRect(.(0, 0, Width, Height), radius, trackColor);
		}

		// Fill — clip a full-width shape so the left edge always matches the track
		float fillW = Width * mProgress;
		if (fillW > 0)
		{
			ctx.PushClipRect(.(0, 0, fillW, Height));
			let fillDrawable = theme?.GetDrawable("ProgressBar", "fill");
			if (fillDrawable != null)
			{
				fillDrawable.Draw(ctx, .(0, 0, Width, Height));
			}
			else
			{
				let fillColor = (mFillColor.A > 0) ? mFillColor : (theme?.GetColor("ProgressBar", "fill") ?? palette.Accent);
				let radius = Height * 0.5f;
				ctx.FillRoundedRect(.(0, 0, Width, Height), radius, fillColor);
			}
			ctx.PopClip();
		}
	}
}
