using System;
using Sedulous.Drawing;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// Base class for themed controls with visual state support.
public class Control : UIElement
{
	public this()
	{
		// Controls are focusable by default
		Focusable = true;
	}

	private Color? mBackground;
	private Color? mForeground;
	private Color? mBorderBrush;
	private Thickness mBorderThickness;
	private String mFontFamily ~ delete _;
	private float? mFontSize;
	private Style mStyle;
	private ControlState mControlState = .Normal;

	/// The background color of the control.
	public Color? Background
	{
		get => mBackground ?? GetThemedColor("Background");
		set { mBackground = value; InvalidateVisual(); }
	}

	/// The foreground (text) color of the control.
	public Color? Foreground
	{
		get => mForeground ?? GetThemedColor("Foreground");
		set { mForeground = value; InvalidateVisual(); }
	}

	/// The border color of the control.
	public Color? BorderBrush
	{
		get => mBorderBrush ?? GetThemedColor("Border");
		set { mBorderBrush = value; InvalidateVisual(); }
	}

	/// The border thickness of the control.
	public Thickness BorderThickness
	{
		get => mBorderThickness;
		set { mBorderThickness = value; InvalidateMeasure(); }
	}

	/// The font family name.
	public StringView FontFamily
	{
		get
		{
			if (mFontFamily != null)
				return mFontFamily;
			let theme = GetTheme();
			if (theme != null)
				return theme.DefaultFontFamily;
			return "Segoe UI";
		}
		set
		{
			if (mFontFamily == null)
				mFontFamily = new String();
			mFontFamily.Set(value);
			InvalidateMeasure();
		}
	}

	/// The font size.
	public float FontSize
	{
		get
		{
			if (mFontSize.HasValue)
				return mFontSize.Value;
			let theme = GetTheme();
			if (theme != null)
				return theme.DefaultFontSize;
			return 14.0f;
		}
		set { mFontSize = value; InvalidateMeasure(); }
	}

	/// The explicit style for this control (overrides theme style).
	public Style Style
	{
		get => mStyle;
		set { mStyle = value; InvalidateVisual(); }
	}

	/// The current visual state of the control.
	public ControlState ControlState
	{
		get => mControlState;
		protected set
		{
			if (mControlState != value)
			{
				mControlState = value;
				OnControlStateChanged();
				InvalidateVisual();
			}
		}
	}

	/// Gets the effective style for this control.
	public Style GetEffectiveStyle()
	{
		if (mStyle != null)
			return mStyle;

		let theme = GetTheme();
		if (theme != null)
			return theme.GetStyle(GetType());

		return null;
	}

	/// Gets the theme from context or parent.
	public ITheme GetTheme()
	{
		// Try to get from context
		let context = Context;
		if (context != null)
		{
			if (context.GetService<ITheme>() case .Ok(let theme))
				return theme;
		}

		// Could also inherit from parent Control if needed
		return null;
	}

	/// Gets a themed color value, considering control state.
	protected Color? GetThemedColor(StringView propertyName)
	{
		let style = GetEffectiveStyle();
		if (style != null)
		{
			if (style.TryGetColor(propertyName, mControlState, let color))
				return color;
		}
		return null;
	}

	/// Gets a themed float value, considering control state.
	protected float? GetThemedFloat(StringView propertyName)
	{
		let style = GetEffectiveStyle();
		if (style != null)
		{
			if (style.TryGetFloat(propertyName, mControlState, let f))
				return f;
		}
		return null;
	}

	/// Called when the control state changes.
	protected virtual void OnControlStateChanged()
	{
	}

	/// Updates the control state based on current conditions.
	protected void UpdateControlState()
	{
		var state = Sedulous.UI.ControlState.Normal;

		if (!IsEnabled)
			state = (Sedulous.UI.ControlState)((int)state | (int)Sedulous.UI.ControlState.Disabled);
		if (IsFocused)
			state = (Sedulous.UI.ControlState)((int)state | (int)Sedulous.UI.ControlState.Focused);
		if (IsMouseOver)
			state = (Sedulous.UI.ControlState)((int)state | (int)Sedulous.UI.ControlState.Hovered);

		ControlState = state;
	}

	protected override DesiredSize MeasureOverride(SizeConstraints constraints)
	{
		// Account for border in measurement
		let borderWidth = mBorderThickness.TotalHorizontal;
		let borderHeight = mBorderThickness.TotalVertical;

		let innerConstraints = constraints.Deflate(mBorderThickness);
		let innerSize = MeasureContent(innerConstraints);

		return .(innerSize.Width + borderWidth, innerSize.Height + borderHeight);
	}

	/// Measures the content inside the border. Override in derived classes.
	protected virtual DesiredSize MeasureContent(SizeConstraints constraints)
	{
		return .(0, 0);
	}

	protected override void ArrangeOverride(RectangleF contentBounds)
	{
		// Render bounds is the full content bounds
		// Content inside border gets reduced bounds
		let innerBounds = RectangleF(
			contentBounds.X + mBorderThickness.Left,
			contentBounds.Y + mBorderThickness.Top,
			Math.Max(0, contentBounds.Width - mBorderThickness.TotalHorizontal),
			Math.Max(0, contentBounds.Height - mBorderThickness.TotalVertical)
		);

		ArrangeContent(innerBounds);
	}

	/// Arranges the content inside the border. Override in derived classes.
	protected virtual void ArrangeContent(RectangleF contentBounds)
	{
	}

	protected override void OnRender(DrawContext drawContext)
	{
		let bounds = Bounds;

		// Draw background
		if (Background.HasValue)
		{
			drawContext.FillRect(bounds, Background.Value);
		}

		// Draw border
		if (mBorderThickness.TotalHorizontal > 0 || mBorderThickness.TotalVertical > 0)
		{
			if (BorderBrush.HasValue)
			{
				// Top border
				if (mBorderThickness.Top > 0)
					drawContext.FillRect(.(bounds.X, bounds.Y, bounds.Width, mBorderThickness.Top), BorderBrush.Value);
				// Bottom border
				if (mBorderThickness.Bottom > 0)
					drawContext.FillRect(.(bounds.X, bounds.Bottom - mBorderThickness.Bottom, bounds.Width, mBorderThickness.Bottom), BorderBrush.Value);
				// Left border
				if (mBorderThickness.Left > 0)
					drawContext.FillRect(.(bounds.X, bounds.Y + mBorderThickness.Top, mBorderThickness.Left, bounds.Height - mBorderThickness.TotalVertical), BorderBrush.Value);
				// Right border
				if (mBorderThickness.Right > 0)
					drawContext.FillRect(.(bounds.Right - mBorderThickness.Right, bounds.Y + mBorderThickness.Top, mBorderThickness.Right, bounds.Height - mBorderThickness.TotalVertical), BorderBrush.Value);
			}
		}

		// Render content
		RenderContent(drawContext);
	}

	/// Renders the control's content. Override in derived classes.
	protected virtual void RenderContent(DrawContext drawContext)
	{
	}

	protected override void OnMouseEnter()
	{
		base.OnMouseEnter();
		UpdateControlState();
	}

	protected override void OnMouseLeave()
	{
		base.OnMouseLeave();
		UpdateControlState();
	}

	protected override void OnGotFocus()
	{
		base.OnGotFocus();
		UpdateControlState();
	}

	protected override void OnLostFocus()
	{
		base.OnLostFocus();
		UpdateControlState();
	}
}
