namespace Sedulous.UI;

using System;
using System.Collections;
using Sedulous.Drawing;
using Sedulous.Core.Mathematics;
using Sedulous.Core;

/// A modal dialog with title, content, and button row.
public class Dialog : Panel
{
	/// Dialog result values.
	public enum DialogResult
	{
		None,
		OK,
		Cancel,
		Yes,
		No,
		Custom
	}

	private LinearLayout mLayout;
	private Label mTitleLabel;
	private View mContentView;
	private LinearLayout mButtonRow;
	private EventAccessor<delegate void(Dialog, DialogResult)> mOnResult = new .() ~ delete _;

	/// Subscribe to dialog result events.
	public EventAccessor<delegate void(Dialog, DialogResult)> OnResult => mOnResult;

	/// Set the dialog title.
	public StringView Title
	{
		set { mTitleLabel.Text = value; }
	}

	public this()
	{
		// Dialog style
		MinWidth = 200;
		MaxWidth = 400;
		Padding = .(16, 16, 16, 16);
		CornerRadius = 8;

		// Main vertical layout
		mLayout = new LinearLayout();
		mLayout.Orientation = .Vertical;
		mLayout.Spacing = 12;
		AddView(mLayout, new Sedulous.UI.LayoutParams(
			Sedulous.UI.LayoutParams.MatchParent,
			Sedulous.UI.LayoutParams.WrapContent
		));

		// Title label
		mTitleLabel = new Label();
		mTitleLabel.FontSize = 18;
		mLayout.AddView(mTitleLabel, new Sedulous.UI.LayoutParams(
			Sedulous.UI.LayoutParams.MatchParent,
			Sedulous.UI.LayoutParams.WrapContent
		));

		// Button row (right-aligned)
		mButtonRow = new LinearLayout();
		mButtonRow.Orientation = .Horizontal;
		mButtonRow.Spacing = 8;
		mButtonRow.Gravity = .Right;
	}

	/// Set the content view (the body of the dialog between title and buttons).
	public void SetContent(View content)
	{
		if (mContentView != null)
		{
			mLayout.RemoveView(mContentView);
			mContentView = null;
		}

		mContentView = content;

		if (content != null)
		{
			if (mButtonRow.Parent == mLayout)
			{
				// Remove button row, add content, re-add button row
				mLayout.DetachView(mButtonRow);
				mLayout.AddView(content, new Sedulous.UI.LayoutParams(
					Sedulous.UI.LayoutParams.MatchParent,
					Sedulous.UI.LayoutParams.WrapContent
				));
				mLayout.AddView(mButtonRow, new Sedulous.UI.LayoutParams(
					Sedulous.UI.LayoutParams.MatchParent,
					Sedulous.UI.LayoutParams.WrapContent
				));
			}
			else
			{
				mLayout.AddView(content, new Sedulous.UI.LayoutParams(
					Sedulous.UI.LayoutParams.MatchParent,
					Sedulous.UI.LayoutParams.WrapContent
				));
			}
		}
	}

	/// Add a button to the dialog's button row.
	public void AddButton(StringView text, DialogResult result)
	{
		let btn = new Button();
		btn.Text = text;
		btn.Focusable = true;
		DialogResult capturedResult = result;
		btn.OnClick.Subscribe(new (b) => {
			Close(capturedResult);
		});

		// Ensure button row is in the layout
		if (mButtonRow.Parent != mLayout)
		{
			mLayout.AddView(mButtonRow, new Sedulous.UI.LayoutParams(
				Sedulous.UI.LayoutParams.MatchParent,
				Sedulous.UI.LayoutParams.WrapContent
			));
		}

		mButtonRow.AddView(btn, new Sedulous.UI.LayoutParams(
			Sedulous.UI.LayoutParams.WrapContent,
			Sedulous.UI.LayoutParams.WrapContent
		));
	}

	/// Close the dialog with the given result.
	public void Close(DialogResult result)
	{
		mOnResult.[Friend]Invoke(this, result);
		// Defer closing to avoid use-after-free (ClosePopup deletes this)
		let ctx = Context;
		let self = this;
		ctx?.MutationQueue.QueueAction(new () => {
			ctx.ClosePopup(self);
		});
	}

	/// Get the dialog background drawable, preferring "Dialog" theme key over "Panel".
	private Drawable GetDialogDrawable()
	{
		let theme = Context?.Theme;
		if (theme == null) return null;

		// Only use drawable if no explicit fill/border colors are set
		if (FillColor.A == 0 && BorderColor.A == 0)
			return theme.GetDrawable("Dialog", "background") ?? theme.GetDrawable("Panel", "background");
		return null;
	}

	/// Get effective padding accounting for drawable nine-slice insets.
	private Thickness GetDialogEffectivePadding()
	{
		let bgDrawable = GetDialogDrawable();
		if (bgDrawable != null)
		{
			let dp = bgDrawable.DrawablePadding;
			return .(
				Math.Max(Padding.Left, dp.Left),
				Math.Max(Padding.Top, dp.Top),
				Math.Max(Padding.Right, dp.Right),
				Math.Max(Padding.Bottom, dp.Bottom)
			);
		}
		return Padding;
	}

	protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
	{
		let effective = GetDialogEffectivePadding();
		if (effective != Padding)
		{
			var saved = this.[Friend]mPadding;
			this.[Friend]mPadding = effective;
			base.OnMeasure(widthSpec, heightSpec);
			this.[Friend]mPadding = saved;
		}
		else
		{
			base.OnMeasure(widthSpec, heightSpec);
		}
	}

	protected override void OnLayout(float width, float height)
	{
		let effective = GetDialogEffectivePadding();
		if (effective != Padding)
		{
			var saved = this.[Friend]mPadding;
			this.[Friend]mPadding = effective;
			base.OnLayout(width, height);
			this.[Friend]mPadding = saved;
		}
		else
		{
			base.OnLayout(width, height);
		}
	}

	protected override void OnDraw(DrawContext ctx)
	{
		let theme = Context?.Theme;

		// Try drawable first ("Dialog" key, then "Panel" fallback)
		let bgDrawable = GetDialogDrawable();
		if (bgDrawable != null)
		{
			bgDrawable.Draw(ctx, .(0, 0, Width, Height));
			// Draw children (skip Panel's OnDraw which would draw "Panel" drawable)
			for (int i = 0; i < ChildCount; i++)
			{
				let child = GetChildAt(i);
				child.Draw(ctx);
			}
			return;
		}

		// Color fallback — query "Dialog" keys first, then "Panel" fallback
		float cr = theme?.GetDimension("Dialog", "cornerRadius") ?? CornerRadius;
		Color fillColor = FillColor;
		if (fillColor.A == 0 && theme != null)
			fillColor = theme.GetColor("Dialog", "background") ?? theme.GetColor("Panel", "background") ?? Color(0);
		if (fillColor.A > 0)
		{
			if (cr > 0)
				ctx.FillRoundedRect(.(0, 0, Width, Height), cr, fillColor);
			else
				ctx.FillRect(.(0, 0, Width, Height), fillColor);
		}

		Color borderColor = BorderColor;
		if (borderColor.A == 0)
			borderColor = theme?.GetColor("Dialog", "border") ?? theme?.GetColor("Panel", "border") ?? GetStateBorderColor();
		if (BorderWidth > 0)
		{
			if (cr > 0)
				ctx.DrawBorderRoundedRect(.(0, 0, Width, Height), cr, borderColor, BorderWidth);
			else
				ctx.DrawBorderRect(.(0, 0, Width, Height), borderColor, BorderWidth);
		}

		// Draw children
		for (int i = 0; i < ChildCount; i++)
		{
			let child = GetChildAt(i);
			child.Draw(ctx);
		}
	}

	/// Create a simple alert dialog with an OK button.
	public static Dialog Alert(StringView title, StringView message)
	{
		let dialog = new Dialog();
		dialog.Title = title;

		let msgLabel = new Label();
		msgLabel.Text = message;
		msgLabel.WordWrap = true;
		dialog.SetContent(msgLabel);

		dialog.AddButton("OK", .OK);
		return dialog;
	}

	/// Create a confirm dialog with Yes/No buttons.
	public static Dialog Confirm(StringView title, StringView message)
	{
		let dialog = new Dialog();
		dialog.Title = title;

		let msgLabel = new Label();
		msgLabel.Text = message;
		msgLabel.WordWrap = true;
		dialog.SetContent(msgLabel);

		dialog.AddButton("Yes", .Yes);
		dialog.AddButton("No", .No);
		return dialog;
	}
}
