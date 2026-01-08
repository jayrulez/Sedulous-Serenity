using System;
using Sedulous.Drawing;
using Sedulous.Mathematics;
using Sedulous.Fonts;

namespace Sedulous.UI;

/// A label control that displays text and can be associated with another control.
/// Similar to TextBlock but designed for labeling form elements.
public class Label : ContentControl
{
	private UIElement mTarget;

	/// The target control that this label is associated with.
	/// Clicking the label will focus the target.
	public UIElement Target
	{
		get => mTarget;
		set => mTarget = value;
	}

	public this()
	{
		// Labels are not focusable by default
		Focusable = false;
	}

	public this(StringView text) : this()
	{
		ContentText = text;
	}

	public this(StringView text, UIElement target) : this(text)
	{
		mTarget = target;
	}

	protected override void OnMouseDownRouted(MouseButtonEventArgs args)
	{
		base.OnMouseDownRouted(args);

		// Clicking label focuses the target control
		if (args.Button == .Left && mTarget != null && mTarget.Focusable)
		{
			Context?.SetFocus(mTarget);
			args.Handled = true;
		}
	}
}
