using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.Drawing;
using Sedulous.Foundation.Core;

namespace Sedulous.GUI;

/// A selectable item in a menu or context menu.
/// Can have text, icon, shortcut text, command, and submenu items.
public class MenuItem : Control
{
	// Text content
	private String mText ~ delete _;
	private String mShortcutText ~ delete _;

	// Text blocks for rendering
	private TextBlock mTextBlock ~ delete _;
	private TextBlock mShortcutBlock ~ delete _;

	// Command binding
	private ICommand mCommand;
	private Object mCommandParameter;

	// Checkable state
	private bool mIsCheckable = false;
	private bool mIsChecked = false;

	// Submenu items
	private List<UIElement> mSubItems ~ DeleteContainerAndItems!(_);
	private bool mIsSubmenuOpen = false;

	// Internal state
	private bool mIsHighlighted = false;

	// Parent menu reference for submenu notifications
	private ContextMenu mParentMenu;

	// Events
	private EventAccessor<delegate void(MenuItem)> mClick = new .() ~ delete _;

	// Appearance
	private float mHeight = 24;
	private float mCheckWidth = 20;
	private float mArrowWidth = 16;
	private float mShortcutGap = 24;

	/// Creates a new MenuItem.
	public this()
	{
		IsFocusable = false;  // Menu navigation handles focus
		IsTabStop = false;
		Background = Color(0, 0, 0, 0);  // Transparent by default
		Foreground = Color(220, 220, 220, 255);
		Padding = .(8, 4, 8, 4);
		mSubItems = new .();

		// Create text block for main text
		mTextBlock = new TextBlock("");
		mTextBlock.Foreground = Foreground;
	}

	/// Creates a new MenuItem with text.
	public this(StringView text) : this()
	{
		Text = text;
	}

	/// The control type name for theming.
	protected override StringView ControlTypeName => "MenuItem";

	/// The menu item text.
	public StringView Text
	{
		get => mText ?? "";
		set
		{
			if (mText == null)
				mText = new String(value);
			else
				mText.Set(value);
			mTextBlock.Text = value;
		}
	}

	/// Shortcut key text displayed on the right side (e.g., "Ctrl+S").
	public StringView ShortcutText
	{
		get => mShortcutText ?? "";
		set
		{
			if (mShortcutText == null)
				mShortcutText = new String(value);
			else
				mShortcutText.Set(value);

			// Create or update shortcut text block
			if (mShortcutBlock == null)
			{
				mShortcutBlock = new TextBlock(value);
				mShortcutBlock.Foreground = Color(150, 150, 150, 255);
			}
			else
			{
				mShortcutBlock.Text = value;
			}
		}
	}

	/// The command to execute when clicked.
	public ICommand Command
	{
		get => mCommand;
		set => mCommand = value;
	}

	/// Parameter passed to the command.
	public Object CommandParameter
	{
		get => mCommandParameter;
		set => mCommandParameter = value;
	}

	/// Whether this item can be checked/unchecked.
	public bool IsCheckable
	{
		get => mIsCheckable;
		set => mIsCheckable = value;
	}

	/// Whether this item is checked (only relevant if IsCheckable is true).
	public bool IsChecked
	{
		get => mIsChecked;
		set => mIsChecked = value;
	}

	/// Whether this item has sub-items (submenu).
	public bool HasSubItems => mSubItems.Count > 0;

	/// Number of sub-items.
	public int SubItemCount => mSubItems.Count;

	/// Whether the submenu is currently open.
	public bool IsSubmenuOpen => mIsSubmenuOpen;

	/// Whether this item is currently highlighted.
	public bool IsHighlighted => mIsHighlighted;

	/// Sets the parent context menu (used internally for submenu notifications).
	public ContextMenu ParentMenu
	{
		get => mParentMenu;
		set => mParentMenu = value;
	}

	/// Event fired when the item is clicked.
	public EventAccessor<delegate void(MenuItem)> Click => mClick;

	/// Adds a sub-item to this menu item.
	public MenuItem AddItem(StringView text)
	{
		let item = new MenuItem(text);
		mSubItems.Add(item);
		return item;
	}

	/// Adds an existing sub-item.
	public void AddItem(MenuItem item)
	{
		mSubItems.Add(item);
	}

	/// Adds a separator to the submenu.
	public void AddSeparator()
	{
		mSubItems.Add(new MenuSeparator());
	}

	/// Gets a sub-item by index.
	public UIElement GetSubItem(int index)
	{
		if (index < 0 || index >= mSubItems.Count)
			return null;
		return mSubItems[index];
	}

	/// Sets the highlighted state (used by parent menus for keyboard navigation).
	public void SetHighlighted(bool highlighted)
	{
		mIsHighlighted = highlighted;
	}

	/// Activates this menu item (executes command or fires click event).
	public void Activate()
	{
		if (IsCheckable)
			mIsChecked = !mIsChecked;

		mClick.[Friend]Invoke(this);

		if (mCommand != null && mCommand.CanExecute(mCommandParameter))
			mCommand.Execute(mCommandParameter);
	}

	// === Layout ===

	protected override DesiredSize MeasureOverride(SizeConstraints constraints)
	{
		// Measure text block
		let textConstraints = SizeConstraints.Unconstrained;
		mTextBlock.Measure(textConstraints);
		float textWidth = mTextBlock.DesiredSize.Width;
		float textHeight = mTextBlock.DesiredSize.Height;

		// Measure shortcut if present
		float shortcutWidth = 0;
		if (mShortcutBlock != null)
		{
			mShortcutBlock.Measure(textConstraints);
			shortcutWidth = mShortcutBlock.DesiredSize.Width + mShortcutGap;
		}

		// Calculate total width
		float width = Padding.Left + mCheckWidth + textWidth + shortcutWidth;
		if (HasSubItems)
			width += mArrowWidth;
		width += Padding.Right;

		float height = Math.Max(mHeight, textHeight + Padding.Top + Padding.Bottom);

		return .(width, height);
	}

	protected override void ArrangeOverride(RectangleF contentBounds)
	{
		// Arrange text block
		float x = contentBounds.X + Padding.Left + mCheckWidth;
		float centerY = contentBounds.Y + contentBounds.Height / 2;
		float textHeight = mTextBlock.DesiredSize.Height;

		let textBounds = RectangleF(x, centerY - textHeight / 2, mTextBlock.DesiredSize.Width, textHeight);
		mTextBlock.Arrange(textBounds);

		// Arrange shortcut block if present
		if (mShortcutBlock != null)
		{
			let shortcutHeight = mShortcutBlock.DesiredSize.Height;
			let shortcutWidth = mShortcutBlock.DesiredSize.Width;
			let shortcutX = contentBounds.Right - Padding.Right - (HasSubItems ? mArrowWidth : 0) - shortcutWidth;
			let shortcutBounds = RectangleF(shortcutX, centerY - shortcutHeight / 2, shortcutWidth, shortcutHeight);
			mShortcutBlock.Arrange(shortcutBounds);
		}
	}

	// === Rendering ===

	protected override void RenderOverride(DrawContext ctx)
	{
		let bounds = ArrangedBounds;
		float centerY = bounds.Y + bounds.Height / 2;

		// Draw highlight background if highlighted or pressed
		if (mIsHighlighted || IsPressed)
		{
			let highlightColor = Color(60, 120, 200, 255);
			ctx.FillRect(bounds, highlightColor);
		}

		// Draw checkmark if checkable and checked
		if (mIsCheckable && mIsChecked)
		{
			let checkColor = Foreground;
			let checkX = bounds.X + Padding.Left + mCheckWidth / 2 - 4;
			let checkY = centerY;
			// Simple checkmark using lines
			ctx.DrawLine(.(checkX, checkY), .(checkX + 3, checkY + 3), checkColor, 2);
			ctx.DrawLine(.(checkX + 3, checkY + 3), .(checkX + 8, checkY - 3), checkColor, 2);
		}

		// Render text block
		mTextBlock.Foreground = mIsHighlighted ? Color(255, 255, 255, 255) : Foreground;
		mTextBlock.Render(ctx);

		// Render shortcut text
		if (mShortcutBlock != null)
		{
			mShortcutBlock.Render(ctx);
		}

		// Draw submenu arrow if has sub-items
		if (HasSubItems)
		{
			let arrowX = bounds.Right - Padding.Right - mArrowWidth / 2;
			let arrowColor = mIsHighlighted ? Color(255, 255, 255, 255) : Color(180, 180, 180, 255);
			// Draw a simple ">" arrow
			ctx.DrawLine(.(arrowX - 3, centerY - 4), .(arrowX + 2, centerY), arrowColor, 1.5f);
			ctx.DrawLine(.(arrowX + 2, centerY), .(arrowX - 3, centerY + 4), arrowColor, 1.5f);
		}
	}

	// === Visual child management ===

	public override int VisualChildCount
	{
		get
		{
			int count = 1;  // mTextBlock
			if (mShortcutBlock != null)
				count++;
			return count;
		}
	}

	public override UIElement GetVisualChild(int index)
	{
		if (index == 0)
			return mTextBlock;
		if (index == 1 && mShortcutBlock != null)
			return mShortcutBlock;
		return null;
	}

	// === Input ===

	protected override void OnMouseEnter(MouseEventArgs e)
	{
		mIsHighlighted = true;
		base.OnMouseEnter(e);

		// Notify parent menu that this item is being hovered
		mParentMenu?.OnItemHovered(this);
	}

	protected override void OnMouseLeave(MouseEventArgs e)
	{
		mIsHighlighted = false;
		base.OnMouseLeave(e);
	}

	protected override void OnMouseUp(MouseButtonEventArgs e)
	{
		if (e.Button == .Left && !HasSubItems)
		{
			Activate();
			e.Handled = true;
		}
		base.OnMouseUp(e);
	}

	// === Lifecycle ===

	public override void OnAttachedToContext(GUIContext context)
	{
		base.OnAttachedToContext(context);
		mTextBlock.OnAttachedToContext(context);
		mShortcutBlock?.OnAttachedToContext(context);
	}

	public override void OnDetachedFromContext()
	{
		mTextBlock.OnDetachedFromContext();
		mShortcutBlock?.OnDetachedFromContext();
		base.OnDetachedFromContext();
	}
}
