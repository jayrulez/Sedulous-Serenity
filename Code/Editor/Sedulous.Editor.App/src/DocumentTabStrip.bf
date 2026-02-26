namespace Sedulous.Editor.App;

using System;
using System.Collections;
using Sedulous.GUI;
using Sedulous.Foundation.Mathematics;
using Sedulous.Editor.Core;
using Sedulous.Foundation.Core;
using Sedulous.Drawing;

/// A tab item for the DocumentTabStrip.
public class DocumentTab : Control
{
	private DocumentTabStrip mOwner;
	private IAssetDocument mDocument;
	private String mTitle = new .() ~ delete _;
	private bool mIsSelected;
	private bool mIsCloseHovered;
	private RectangleF mCloseButtonBounds;

	private const float cTabHeight = 28;
	private const float cTabMinWidth = 100;
	private const float cTabMaxWidth = 200;
	private const float cCloseButtonSize = 16;
	private const float cPadding = 8;

	/// The document this tab represents.
	public IAssetDocument Document => mDocument;

	/// Whether this tab is selected.
	public bool IsSelected
	{
		get => mIsSelected;
		set
		{
			if (mIsSelected != value)
			{
				mIsSelected = value;
				// Visual update happens automatically on next render
			}
		}
	}

	public this(DocumentTabStrip owner, IAssetDocument document)
	{
		mOwner = owner;
		mDocument = document;
		Height = .Fixed(cTabHeight);
		RefreshTitle();
	}

	/// Refresh the tab title from the document.
	public void RefreshTitle()
	{
		mTitle.Clear();
		mDocument.GetTitle(mTitle);
		InvalidateLayout();
	}

	protected override DesiredSize MeasureOverride(SizeConstraints constraints)
	{
		let fontService = GetFontService();
		float textWidth = cTabMinWidth;
		let fontSize = Context?.Theme?.DefaultFontSize ?? 14f;

		if (fontService != null)
		{
			let cachedFont = fontService.GetFont(fontSize);
			if (cachedFont != null)
			{
				textWidth = cachedFont.Font.MeasureString(mTitle);
			}
		}

		// Text + padding + close button
		let width = Math.Clamp(textWidth + cPadding * 3 + cCloseButtonSize, cTabMinWidth, cTabMaxWidth);
		return .(width, cTabHeight);
	}

	protected override void RenderOverride(DrawContext drawContext)
	{
		let theme = Context?.Theme;
		let bounds = ArrangedBounds;
		let fontSize = theme?.DefaultFontSize ?? 14f;

		// Tab colors (hardcoded dark theme colors)
		let tabSelected = Color(45, 45, 48);
		let tabHover = Color(62, 62, 64);
		let tabBackground = Color(37, 37, 38);
		let borderCol = Color(60, 60, 60);
		let textColor = Color(220, 220, 220);
		let closeNormal = Color(150, 150, 150);
		let closeHover = Color(255, 100, 100);

		// Background
		Color bgColor;
		if (mIsSelected)
			bgColor = tabSelected;
		else if (IsHovered)
			bgColor = tabHover;
		else
			bgColor = tabBackground;

		drawContext.FillRect(bounds, bgColor);

		// Bottom border (selected tabs connect to content)
		if (!mIsSelected)
		{
			drawContext.FillRect(.(bounds.X, bounds.Bottom - 1, bounds.Width, 1), borderCol);
		}

		// Separator between tabs
		drawContext.FillRect(.(bounds.Right - 1, bounds.Y + 4, 1, bounds.Height - 8), borderCol);

		// Close button bounds (right side)
		mCloseButtonBounds = RectangleF(
			bounds.Right - cPadding - cCloseButtonSize,
			bounds.Y + (bounds.Height - cCloseButtonSize) / 2,
			cCloseButtonSize,
			cCloseButtonSize
		);

		// Draw text
		let foreground = Foreground.A > 0 ? Foreground : textColor;
		let textBounds = RectangleF(bounds.X + cPadding, bounds.Y, bounds.Width - cPadding * 2 - cCloseButtonSize - 4, bounds.Height);

		let fontService = GetFontService();
		if (fontService != null)
		{
			let cachedFont = fontService.GetFont(fontSize);
			if (cachedFont != null)
			{
				let font = cachedFont.Font;
				let atlas = cachedFont.Atlas;
				let atlasTexture = fontService.GetAtlasTexture(cachedFont);

				if (atlas != null && atlasTexture != null)
				{
					// Truncate if needed
					let maxWidth = textBounds.Width;
					let measuredWidth = font.MeasureString(mTitle);

					if (measuredWidth > maxWidth)
					{
						let truncated = scope:: String();
						let ellipsis = "...";
						let ellipsisWidth = font.MeasureString(ellipsis);
						let availableWidth = maxWidth - ellipsisWidth;

						for (let c in mTitle.DecodedChars)
						{
							truncated.Append(c);
							if (font.MeasureString(truncated) > availableWidth)
							{
								truncated.RemoveFromEnd(1);
								break;
							}
						}
						truncated.Append(ellipsis);
						drawContext.DrawText(truncated, font, atlas, atlasTexture, textBounds, .Left, .Middle, foreground);
					}
					else
					{
						drawContext.DrawText(mTitle, font, atlas, atlasTexture, textBounds, .Left, .Middle, foreground);
					}
				}
			}
		}

		// Close button
		if (IsHovered || mIsSelected)
		{
			let closeColor = mIsCloseHovered ? closeHover : closeNormal;

			// Draw X
			let cx = mCloseButtonBounds.X + mCloseButtonBounds.Width / 2;
			let cy = mCloseButtonBounds.Y + mCloseButtonBounds.Height / 2;
			let half = 4f;

			drawContext.DrawLine(.(cx - half, cy - half), .(cx + half, cy + half), closeColor, 1.5f);
			drawContext.DrawLine(.(cx + half, cy - half), .(cx - half, cy + half), closeColor, 1.5f);
		}
	}

	protected override void OnMouseMove(MouseEventArgs e)
	{
		base.OnMouseMove(e);

		//let wasCloseHovered = mIsCloseHovered;
		mIsCloseHovered = mCloseButtonBounds.Contains(e.ScreenX, e.ScreenY);

		// Visual update happens automatically on next render
	}

	protected override void OnMouseLeave(MouseEventArgs e)
	{
		base.OnMouseLeave(e);
		if (mIsCloseHovered)
		{
			mIsCloseHovered = false;
			// Visual update happens automatically on next render
		}
	}

	protected override void OnMouseDown(MouseButtonEventArgs e)
	{
		base.OnMouseDown(e);

		if (e.Button == .Left)
		{
			// Check close button
			if (mCloseButtonBounds.Contains(e.ScreenX, e.ScreenY))
			{
				mOwner.RequestCloseTab(this);
				e.Handled = true;
				return;
			}

			// Select tab
			mOwner.SelectTab(this);
			e.Handled = true;
		}
		else if (e.Button == .Middle)
		{
			// Middle-click to close
			mOwner.RequestCloseTab(this);
			e.Handled = true;
		}
	}

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
}

/// Tab strip control for managing open documents.
public class DocumentTabStrip : Border
{
	private DocumentManager mDocumentManager;
	private StackPanel mTabsPanel;
	private ScrollViewer mTabsScroller;
	private Grid mContentArea;
	private Dictionary<Guid, DocumentTab> mTabMap = new .() ~ delete _;
	private Dictionary<Guid, UIElement> mContentMap = new .() ~ DeleteDictionaryAndValues!(_);
	private DocumentTab mSelectedTab;
	private UIElement mCurrentContent;
	private Label mEmptyLabel;

	// Events
	private EventAccessor<delegate void(DocumentTab)> mTabSelected = new .() ~ delete _;
	private EventAccessor<delegate void(DocumentTab)> mTabClosed = new .() ~ delete _;

	/// Event fired when a tab is selected.
	public EventAccessor<delegate void(DocumentTab)> TabSelected => mTabSelected;

	/// Event fired when a tab is closed.
	public EventAccessor<delegate void(DocumentTab)> TabClosed => mTabClosed;

	/// Currently selected tab.
	public DocumentTab SelectedTab => mSelectedTab;

	public this(DocumentManager documentManager)
	{
		mDocumentManager = documentManager;

		BuildUI();
		SubscribeToEvents();

		// Add tabs for any existing documents
		for (let doc in mDocumentManager.OpenDocuments)
			AddTab(doc);

		// Select active document if any
		if (mDocumentManager.ActiveDocument != null)
		{
			if (mTabMap.TryGetValue(mDocumentManager.ActiveDocument.DocumentId, let tab))
				SelectTab(tab);
		}
	}

	private void BuildUI()
	{
		Background = Color(30, 30, 30);
		Padding = .(0);

		let mainPanel = new DockPanel();
		mainPanel.Width = .Fill;
		mainPanel.Height = .Fill;
		mainPanel.LastChildFill = true;

		// Tab bar area (docked to top)
		let tabBar = new Border();
		tabBar.Height = .Fixed(28);
		tabBar.Background = Color(37, 37, 38);

		mTabsScroller = new ScrollViewer();
		mTabsScroller.HorizontalScrollBarVisibility = .Auto;
		mTabsScroller.VerticalScrollBarVisibility = .Disabled;
		mTabsScroller.Height = .Fixed(28);

		mTabsPanel = new StackPanel();
		mTabsPanel.Orientation = .Horizontal;
		mTabsPanel.Height = .Fixed(28);
		mTabsPanel.Spacing = 0;

		mTabsScroller.Content = mTabsPanel;
		tabBar.Child = mTabsScroller;
		mainPanel.AddChild(tabBar);
		DockPanelProperties.SetDock(tabBar, .Top);

		// Content area (fills remaining space)
		mContentArea = new Grid();
		mContentArea.Width = .Fill;
		mContentArea.Height = .Fill;
		mContentArea.Background = Color(30, 30, 30);

		// Empty state label
		mEmptyLabel = new Label("No documents open");
		mEmptyLabel.HorizontalAlignment = .Center;
		mEmptyLabel.VerticalAlignment = .Center;
		mEmptyLabel.Foreground = Color(128, 128, 128);
		mContentArea.AddChild(mEmptyLabel);

		mainPanel.AddChild(mContentArea);

		Child = mainPanel;
	}

	private void SubscribeToEvents()
	{
		mDocumentManager.DocumentOpened.Subscribe(new (doc) => {
			AddTab(doc);
		});

		mDocumentManager.DocumentClosed.Subscribe(new (doc) => {
			RemoveTab(doc);
		});

		mDocumentManager.ActiveDocumentChanged.Subscribe(new (doc) => {
			if (doc != null && mTabMap.TryGetValue(doc.DocumentId, let tab))
			{
				if (mSelectedTab != tab)
					SelectTab(tab);
			}
		});

		mDocumentManager.DocumentDirtyChanged.Subscribe(new (doc) => {
			if (mTabMap.TryGetValue(doc.DocumentId, let tab))
				tab.RefreshTitle();
		});
	}

	private void AddTab(IAssetDocument document)
	{
		if (mTabMap.ContainsKey(document.DocumentId))
			return;

		let tab = new DocumentTab(this, document);
		mTabMap[document.DocumentId] = tab;
		mTabsPanel.AddChild(tab);

		// Hide empty label
		mEmptyLabel.Visibility = .Collapsed;

		InvalidateLayout();
	}

	private void RemoveTab(IAssetDocument document)
	{
		if (!mTabMap.TryGetValue(document.DocumentId, let tab))
			return;

		// Remove content if shown
		if (mContentMap.TryGetValue(document.DocumentId, let content))
		{
			if (mCurrentContent == content)
			{
				mContentArea.RemoveChild(content);
				mCurrentContent = null;
			}
			mContentMap.Remove(document.DocumentId);
			// Note: content is deleted by mContentMap destructor
		}

		// Remove tab
		mTabsPanel.RemoveChild(tab);
		mTabMap.Remove(document.DocumentId);

		if (mSelectedTab == tab)
			mSelectedTab = null;

		delete tab;

		// Show empty label if no tabs
		if (mTabMap.Count == 0)
			mEmptyLabel.Visibility = .Visible;

		mTabClosed.[Friend]Invoke(null);
		InvalidateLayout();
	}

	/// Select a tab.
	public void SelectTab(DocumentTab tab)
	{
		if (mSelectedTab == tab)
			return;

		// Deselect previous
		if (mSelectedTab != null)
			mSelectedTab.IsSelected = false;

		mSelectedTab = tab;

		if (mSelectedTab != null)
		{
			mSelectedTab.IsSelected = true;

			// Show content
			ShowContent(mSelectedTab.Document);

			// Update document manager
			mDocumentManager.SetActive(mSelectedTab.Document);

			mTabSelected.[Friend]Invoke(mSelectedTab);
		}
	}

	private void ShowContent(IAssetDocument document)
	{
		// Hide current content
		if (mCurrentContent != null)
		{
			mCurrentContent.Visibility = .Collapsed;
		}

		// Get or create content
		UIElement content;
		if (!mContentMap.TryGetValue(document.DocumentId, out content))
		{
			content = document.CreateContent();
			if (content != null)
			{
				content.Width = .Fill;
				content.Height = .Fill;
				mContentMap[document.DocumentId] = content;
				mContentArea.AddChild(content);
			}
		}

		if (content != null)
		{
			content.Visibility = .Visible;
			mCurrentContent = content;
		}
	}

	/// Request to close a tab.
	public void RequestCloseTab(DocumentTab tab)
	{
		if (tab == null)
			return;

		// Let document manager handle closing (may prompt for save)
		mDocumentManager.Close(tab.Document);
	}

	/// Refresh all tab titles.
	public void RefreshTitles()
	{
		for (let tab in mTabMap.Values)
			tab.RefreshTitle();
	}
}
