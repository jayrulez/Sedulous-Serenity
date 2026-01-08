using System;
using Sedulous.UI;
using Sedulous.Mathematics;

namespace Sedulous.Tooling;

/// Dock position for panel docking.
enum DockPosition
{
	/// Dock to the left side.
	Left,
	/// Dock to the right side.
	Right,
	/// Dock to the top.
	Top,
	/// Dock to the bottom.
	Bottom,
	/// Dock as a tab in an existing panel group.
	Center,
	/// Float as a separate window.
	Float
}

/// Base class for dockable tool panels.
abstract class ToolPanel : StackPanel
{
	private String mTitle ~ delete _;
	private TextureHandle mIcon;
	private bool mCanClose = true;
	private bool mCanFloat = true;
	private bool mIsActive = false;
	private Object mTag;

	// Visual properties
	private Color mHeaderBackground = Color(45, 45, 45, 255);
	private Color mHeaderActiveBackground = Color(60, 80, 120, 255);
	private Color mHeaderTextColor = Color(200, 200, 200, 255);
	private Color mContentBackground = Color(35, 35, 35, 255);
	private float mHeaderHeight = 24;
	private FontHandle mFont;
	private float mFontSize = 12;

	/// Event raised when the panel is closed.
	public Event<delegate void()> OnClosed ~ _.Dispose();

	/// Event raised when the panel is activated.
	public Event<delegate void()> OnActivated ~ _.Dispose();

	/// Event raised when the panel is deactivated.
	public Event<delegate void()> OnDeactivated ~ _.Dispose();

	/// Gets or sets the panel title.
	public StringView Title
	{
		get => mTitle ?? "";
		set => String.NewOrSet!(mTitle, value);
	}

	/// Gets or sets the panel icon.
	public TextureHandle Icon
	{
		get => mIcon;
		set => mIcon = value;
	}

	/// Gets or sets whether the panel can be closed.
	public bool CanClose
	{
		get => mCanClose;
		set => mCanClose = value;
	}

	/// Gets or sets whether the panel can be floated.
	public bool CanFloat
	{
		get => mCanFloat;
		set => mCanFloat = value;
	}

	/// Gets whether this panel is currently active/focused.
	public bool IsActive
	{
		get => mIsActive;
		internal set
		{
			if (mIsActive != value)
			{
				mIsActive = value;
				if (value)
				{
					OnPanelActivated();
					OnActivated();
				}
				else
				{
					OnPanelDeactivated();
					OnDeactivated();
				}
				InvalidateVisual();
			}
		}
	}

	/// Gets or sets a custom tag object.
	public Object Tag
	{
		get => mTag;
		set => mTag = value;
	}

	/// Gets or sets the font.
	public FontHandle Font
	{
		get => mFont;
		set => mFont = value;
	}

	/// Gets or sets the font size.
	public float FontSize
	{
		get => mFontSize;
		set => mFontSize = value;
	}

	/// Gets or sets the header height.
	public float HeaderHeight
	{
		get => mHeaderHeight;
		set { mHeaderHeight = value; InvalidateMeasure(); }
	}

	/// Creates a tool panel with a title.
	public this(StringView title)
	{
		mTitle = new String(title);
		Orientation = .Vertical;
	}

	/// Called when the panel should build its UI content.
	protected abstract void OnBuildUI();

	/// Called when the panel becomes active.
	protected virtual void OnPanelActivated() { }

	/// Called when the panel becomes inactive.
	protected virtual void OnPanelDeactivated() { }

	/// Rebuilds the panel's UI content.
	public void RebuildUI()
	{
		// Clear existing children
		while (Children.Count > 0)
		{
			let child = Children[0];
			Children.Remove(child);
			delete child;
		}
		OnBuildUI();
		InvalidateMeasure();
	}

	/// Requests the panel to close.
	public void Close()
	{
		if (mCanClose)
		{
			OnClosed();
		}
	}

	protected override void OnRender(DrawContext dc)
	{
		let contentBounds = ContentBounds;

		// Header background
		let headerRect = RectangleF(contentBounds.X, contentBounds.Y, contentBounds.Width, mHeaderHeight);
		let headerBg = mIsActive ? mHeaderActiveBackground : mHeaderBackground;
		dc.FillRect(headerRect, headerBg);

		// Icon
		float textX = headerRect.X + 6;
		if (mIcon.Value != 0)
		{
			let iconSize = mHeaderHeight - 6;
			let iconY = headerRect.Y + (mHeaderHeight - iconSize) / 2;
			dc.DrawImage(mIcon, RectangleF(textX, iconY, iconSize, iconSize), Color.White);
			textX += iconSize + 4;
		}

		// Title
		let titleRect = RectangleF(textX, headerRect.Y, headerRect.Width - (textX - headerRect.X) - 24, mHeaderHeight);
		dc.DrawText(Title, mFont, mFontSize, titleRect, mHeaderTextColor, .Start, .Center, false);

		// Close button (if closable)
		if (mCanClose)
		{
			let closeSize = 12f;
			let closeX = headerRect.Right - closeSize - 6;
			let closeY = headerRect.Y + (mHeaderHeight - closeSize) / 2;

			// X symbol
			dc.DrawLine(Vector2(closeX, closeY), Vector2(closeX + closeSize, closeY + closeSize), mHeaderTextColor, 1.5f);
			dc.DrawLine(Vector2(closeX + closeSize, closeY), Vector2(closeX, closeY + closeSize), mHeaderTextColor, 1.5f);
		}

		// Content background
		let contentRect = RectangleF(contentBounds.X, contentBounds.Y + mHeaderHeight, contentBounds.Width, contentBounds.Height - mHeaderHeight);
		dc.FillRect(contentRect, mContentBackground);

		// Render children
		base.OnRender(dc);
	}

	protected override Vector2 MeasureOverride(Vector2 availableSize)
	{
		var size = base.MeasureOverride(availableSize);
		size.Y += mHeaderHeight;
		return size;
	}

	protected override void ArrangeOverride(RectangleF finalRect)
	{
		// Offset children below header
		let contentRect = RectangleF(
			finalRect.X + Padding.Left,
			finalRect.Y + mHeaderHeight + Padding.Top,
			finalRect.Width - Padding.HorizontalThickness,
			finalRect.Height - mHeaderHeight - Padding.VerticalThickness
		);

		float offset = 0;
		for (let child in Children)
		{
			if (child.Visibility == .Collapsed)
				continue;

			let childHeight = child.DesiredSize.Y;
			child.Arrange(RectangleF(contentRect.X, contentRect.Y + offset, contentRect.Width, childHeight));
			offset += childHeight + Spacing;
		}
	}

	protected override bool OnMouseDown(MouseButtonEventArgs e)
	{
		if (e.Button != .Left)
			return false;

		let contentBounds = ContentBounds;
		let headerRect = RectangleF(contentBounds.X, contentBounds.Y, contentBounds.Width, mHeaderHeight);

		if (headerRect.Contains(e.Position))
		{
			// Check close button
			if (mCanClose)
			{
				let closeSize = 12f;
				let closeX = headerRect.Right - closeSize - 6;
				let closeY = headerRect.Y + (mHeaderHeight - closeSize) / 2;
				let closeRect = RectangleF(closeX - 2, closeY - 2, closeSize + 4, closeSize + 4);

				if (closeRect.Contains(e.Position))
				{
					Close();
					return true;
				}
			}

			// Activate panel
			this.[Friend]IsActive = true;
			return true;
		}

		return base.OnMouseDown(e);
	}
}
