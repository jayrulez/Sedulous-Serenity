using System;
using Sedulous.Mathematics;
using Sedulous.Drawing;
using Sedulous.Foundation.Core;

namespace Sedulous.UI;

/// Base class for modal dialogs.
public class Dialog : Popup
{
	private String mTitle ~ delete _;
	private UIElement mContent ~ delete _;
	private DialogButtons mButtons = .OK;
	private DialogResult mResult = .None;
	private StackPanel mButtonPanel ~ delete _; // Owned as child
	protected float mTitleBarHeight = 28;
	private bool mDeleteOnClose = false;

	// Events
	private EventAccessor<delegate void(Dialog, DialogResult)> mClosedWithResultEvent = new .() ~ delete _;

	/// If true, the dialog will delete itself when closed.
	/// Use this for dialogs created with `new` that have no other owner.
	public bool DeleteOnClose
	{
		get => mDeleteOnClose;
		set => mDeleteOnClose = value;
	}

	/// The dialog title.
	public StringView Title
	{
		get => mTitle ?? "";
		set
		{
			if (mTitle == null)
				mTitle = new String();
			mTitle.Set(value);
			InvalidateVisual();
		}
	}

	/// The dialog content.
	public UIElement DialogContent
	{
		get => mContent;
		set
		{
			if (mContent != value)
			{
				if (mContent != null)
					mContent.[Friend]mParent = null;

				mContent = value;

				if (mContent != null)
					mContent.[Friend]mParent = this;

				InvalidateMeasure();
			}
		}
	}

	/// Which buttons to show.
	public DialogButtons Buttons
	{
		get => mButtons;
		set
		{
			if (mButtons != value)
			{
				mButtons = value;
				RebuildButtons();
			}
		}
	}

	/// The result when the dialog was closed.
	public DialogResult Result => mResult;

	/// Fired when the dialog closes with a result.
	public EventAccessor<delegate void(Dialog, DialogResult)> ClosedWithResult => mClosedWithResultEvent;

	public this()
	{
		Behavior = .Modal | .DimBackground | .CloseOnEscape;
		Focusable = true;
		MinWidth = 200;
		MinHeight = 100;
		Padding = Thickness(12, 8, 12, 12); // Left, top, right, bottom padding

		// Create button panel
		mButtonPanel = new StackPanel();
		mButtonPanel.Orientation = .Horizontal;
		mButtonPanel.Spacing = 8;
		mButtonPanel.HorizontalAlignment = .Right;
		mButtonPanel.Margin = Thickness(0, 8, 0, 0);
		mButtonPanel.[Friend]mParent = this;

		RebuildButtons();
	}

	private void RebuildButtons()
	{
		mButtonPanel.ClearChildren();

		if (mButtons.HasFlag(.Yes))
			AddDialogButton("Yes", .Yes);

		if (mButtons.HasFlag(.No))
			AddDialogButton("No", .No);

		if (mButtons.HasFlag(.OK))
			AddDialogButton("OK", .OK);

		if (mButtons.HasFlag(.Cancel))
			AddDialogButton("Cancel", .Cancel);

		InvalidateMeasure();
	}

	private void AddDialogButton(StringView text, DialogResult result)
	{
		let button = new Button(text);
		button.Width = .Fixed(80);
		button.Height = .Fixed(28);
		button.Click.Subscribe(new [=](btn) =>
		{
			CloseWithResult(result);
		});
		mButtonPanel.AddChild(button);
	}

	/// Closes the dialog with the specified result.
	public void CloseWithResult(DialogResult result)
	{
		mResult = result;
		let context = Context; // Capture before Close() clears it
		Close();
		mClosedWithResultEvent.[Friend]Invoke(this, result);

		// Queue for deferred deletion if configured
		// We can't delete immediately because we're still in the call stack
		// (e.g., button click handler that triggered the close)
		if (mDeleteOnClose && context != null)
			context.DeferDelete(this);
	}

	/// Shows the dialog centered in the viewport.
	public void ShowDialog(UIContext context)
	{
		if (context == null)
			return;

		// Set context directly - dialogs are not part of the normal layout tree
		this.[Friend]mContext = context;

		// Open centered (popup system will handle positioning)
		Placement = .Center;
		Open();
		context.SetFocus(this);
	}

	protected override DesiredSize MeasureContent(SizeConstraints constraints)
	{
		var contentWidth = 0f;
		var contentHeight = mTitleBarHeight;

		// Measure content
		if (mContent != null)
		{
			let contentConstraints = SizeConstraints.FromMaximum(
				constraints.MaxWidth - Padding.TotalHorizontal,
				constraints.MaxHeight - mTitleBarHeight - 50 - Padding.TotalVertical);
			mContent.Measure(contentConstraints);
			contentWidth = Math.Max(contentWidth, mContent.DesiredSize.Width);
			contentHeight += mContent.DesiredSize.Height + 8;
		}

		// Measure button panel
		mButtonPanel.Measure(SizeConstraints.FromMaximum(constraints.MaxWidth - Padding.TotalHorizontal, 40));
		contentWidth = Math.Max(contentWidth, mButtonPanel.DesiredSize.Width);
		contentHeight += mButtonPanel.DesiredSize.Height + Padding.TotalVertical;

		return .(Math.Max(MinWidth, contentWidth + Padding.TotalHorizontal),
				 Math.Max(MinHeight, contentHeight));
	}

	protected override void ArrangeContent(RectangleF contentBounds)
	{
		var y = contentBounds.Y + mTitleBarHeight;

		// Arrange content
		if (mContent != null)
		{
			let contentHeight = contentBounds.Height - mTitleBarHeight - mButtonPanel.DesiredSize.Height - 16;
			mContent.Arrange(RectangleF(contentBounds.X, y, contentBounds.Width, contentHeight));
			y += contentHeight + 8;
		}

		// Arrange button panel at bottom right
		let buttonPanelY = contentBounds.Bottom - mButtonPanel.DesiredSize.Height;
		let buttonPanelWidth = mButtonPanel.DesiredSize.Width;
		let buttonPanelX = contentBounds.Right - buttonPanelWidth;
		mButtonPanel.Arrange(RectangleF(buttonPanelX, buttonPanelY, buttonPanelWidth, mButtonPanel.DesiredSize.Height));
	}

	protected override void OnRender(DrawContext drawContext)
	{
		let theme = GetTheme();
		let bounds = Bounds;

		// Shadow
		let shadowOffset = 6f;
		let shadowBounds = RectangleF(bounds.X + shadowOffset, bounds.Y + shadowOffset, bounds.Width, bounds.Height);
		drawContext.FillRect(shadowBounds, Color(0, 0, 0, 80));

		// Background
		let bg = Background ?? theme?.GetColor("Surface") ?? Color(250, 250, 250);
		drawContext.FillRect(bounds, bg);

		// Title bar
		let titleBarBounds = RectangleF(bounds.X, bounds.Y, bounds.Width, mTitleBarHeight);
		let titleBarBg = theme?.GetColor("DialogTitleBar") ?? theme?.GetColor("Primary") ?? Color(0, 120, 215);
		drawContext.FillRect(titleBarBounds, titleBarBg);

		// Title text
		if (mTitle != null && mTitle.Length > 0)
		{
			let titleColor = theme?.GetColor("DialogTitleText") ?? Color.White;
			let fontService = GetFontService();
			let cachedFont = fontService?.GetFont(FontFamily, FontSize);

			if (fontService != null && cachedFont != null)
			{
				let font = cachedFont.Font;
				let atlas = cachedFont.Atlas;
				let atlasTexture = fontService.GetAtlasTexture(cachedFont);

				if (atlas != null && atlasTexture != null)
				{
					let textBounds = RectangleF(titleBarBounds.X + 8, titleBarBounds.Y, titleBarBounds.Width - 16, titleBarBounds.Height);
					drawContext.DrawText(mTitle, font, atlas, atlasTexture, textBounds, .Left, .Middle, titleColor);
				}
			}
		}

		// Border
		let border = BorderBrush ?? theme?.GetColor("Border") ?? Color(180, 180, 180);
		drawContext.DrawRect(bounds, border, 1);

		// Render content and buttons
		RenderContent(drawContext);
	}

	protected override void OnKeyDownRouted(KeyEventArgs args)
	{
		if (args.Key == .Escape && Behavior.HasFlag(.CloseOnEscape))
		{
			CloseWithResult(.Cancel);
			args.Handled = true;
			return;
		}

		if (args.Key == .Return)
		{
			// Default to OK if available
			if (mButtons.HasFlag(.OK))
			{
				CloseWithResult(.OK);
				args.Handled = true;
				return;
			}
			else if (mButtons.HasFlag(.Yes))
			{
				CloseWithResult(.Yes);
				args.Handled = true;
				return;
			}
		}

		base.OnKeyDownRouted(args);
	}

	/// Gets the font service from the context.
	private IFontService GetFontService()
	{
		let context = Context;
		if (context != null)
		{
			if (context.GetService<IFontService>() case .Ok(let service))
				return service;
		}
		return null;
	}

	protected override void RenderContent(DrawContext drawContext)
	{
		// Render dialog content
		if (mContent != null)
			mContent.Render(drawContext);

		// Render button panel
		mButtonPanel.Render(drawContext);
	}

	/// Override HitTest to check both content and button panel.
	public override UIElement HitTest(float x, float y)
	{
		if (Visibility != .Visible)
			return null;

		if (!Bounds.Contains(x, y))
			return null;

		// Check button panel first (it's typically in front)
		var result = mButtonPanel.HitTest(x, y);
		if (result != null)
			return result;

		// Check content
		if (mContent != null)
		{
			result = mContent.HitTest(x, y);
			if (result != null)
				return result;
		}

		return this;
	}

	/// Override FindElementById to search both content and button panel.
	public override UIElement FindElementById(UIElementId id)
	{
		if (Id == id)
			return this;

		var result = mButtonPanel.FindElementById(id);
		if (result != null)
			return result;

		if (mContent != null)
		{
			result = mContent.FindElementById(id);
			if (result != null)
				return result;
		}

		return null;
	}
}
