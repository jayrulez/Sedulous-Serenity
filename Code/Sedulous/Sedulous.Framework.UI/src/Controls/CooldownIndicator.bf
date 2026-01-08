using System;
using Sedulous.Mathematics;
using Sedulous.UI;

namespace Sedulous.Framework.UI;

/// Radial cooldown indicator for abilities/skills.
/// Shows a sweeping effect over an icon.
class CooldownIndicator : Widget
{
	private float mCooldownRemaining = 0;
	private bool mShowTimer = true;
	private TextureHandle mIcon;
	private Color mReadyColor = Color(255, 255, 255, 255);
	private Color mCooldownColor = Color(64, 64, 64, 200);
	private bool mClockwiseFill = true;
	private float mTotalCooldown = 0;

	/// Gets or sets the cooldown remaining (0 = ready, 1 = full cooldown).
	public float CooldownRemaining
	{
		get => mCooldownRemaining;
		set
		{
			mCooldownRemaining = Math.Clamp(value, 0, 1);
			InvalidateVisual();
		}
	}

	/// Gets whether the ability is ready (no cooldown).
	public bool IsReady => mCooldownRemaining <= 0;

	/// Gets or sets whether to show the timer text.
	public bool ShowTimer
	{
		get => mShowTimer;
		set => mShowTimer = value;
	}

	/// Gets or sets the total cooldown time in seconds (for display).
	public float TotalCooldown
	{
		get => mTotalCooldown;
		set => mTotalCooldown = value;
	}

	/// Gets or sets the icon texture.
	public TextureHandle Icon
	{
		get => mIcon;
		set
		{
			mIcon = value;
			InvalidateVisual();
		}
	}

	/// Gets or sets the color when ready.
	public Color ReadyColor
	{
		get => mReadyColor;
		set => mReadyColor = value;
	}

	/// Gets or sets the color when on cooldown.
	public Color CooldownColor
	{
		get => mCooldownColor;
		set => mCooldownColor = value;
	}

	/// Gets or sets whether the fill sweeps clockwise.
	public bool ClockwiseFill
	{
		get => mClockwiseFill;
		set => mClockwiseFill = value;
	}

	/// Starts a cooldown.
	public void StartCooldown(float duration)
	{
		mTotalCooldown = duration;
		mCooldownRemaining = 1.0f;
	}

	/// Updates cooldown by time delta.
	public void UpdateCooldown(float deltaTime)
	{
		if (mCooldownRemaining > 0 && mTotalCooldown > 0)
		{
			mCooldownRemaining -= deltaTime / mTotalCooldown;
			if (mCooldownRemaining < 0)
				mCooldownRemaining = 0;
			InvalidateVisual();
		}
	}

	protected override void OnRender(DrawContext dc)
	{
		let bounds = ContentBounds;
		let center = Vector2(bounds.X + bounds.Width / 2, bounds.Y + bounds.Height / 2);
		let radius = Math.Min(bounds.Width, bounds.Height) / 2;

		// Draw icon (if available)
		if (mIcon.IsValid)
		{
			let iconTint = mCooldownRemaining > 0 ? Color(128, 128, 128, 255) : mReadyColor;
			dc.DrawImage(mIcon, bounds, iconTint);
		}
		else
		{
			// Draw a simple circle as placeholder
			dc.FillCircle(center, radius, Color(80, 80, 80, 255));
		}

		// Draw cooldown overlay
		if (mCooldownRemaining > 0)
		{
			DrawCooldownOverlay(dc, center, radius);
		}

		// Draw border
		dc.DrawCircle(center, radius, Color(40, 40, 40, 255), 2);
	}

	private void DrawCooldownOverlay(DrawContext dc, Vector2 center, float radius)
	{
		// Draw a semi-transparent overlay for the cooldown portion
		// We approximate the pie slice with triangles

		let segments = 32;
		let angleStart = -Math.PI_f / 2; // Start from top
		let angleSpan = mCooldownRemaining * Math.PI_f * 2;

		// Build polygon points for the pie slice
		let points = scope Vector2[segments + 2];
		points[0] = center;

		for (int i = 0; i <= segments; i++)
		{
			let t = (float)i / (float)segments;
			float angle;
			if (mClockwiseFill)
				angle = angleStart + t * angleSpan;
			else
				angle = angleStart - t * angleSpan;

			points[i + 1] = Vector2(
				center.X + Math.Cos(angle) * radius,
				center.Y + Math.Sin(angle) * radius
			);
		}

		// Draw as filled polygon
		dc.FillPath(Span<Vector2>(points.Ptr, segments + 2), mCooldownColor);
	}

	protected override Vector2 MeasureOverride(Vector2 availableSize)
	{
		// Default square size for cooldown indicators
		return Vector2(48, 48);
	}
}
