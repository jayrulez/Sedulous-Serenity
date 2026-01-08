using System;
using System.IO;
using System.Collections;
using Sedulous.UI;
using Sedulous.Mathematics;

namespace Sedulous.Tooling;

/// View mode for the asset browser.
enum AssetViewMode
{
	/// List view with details.
	List,
	/// Grid view with thumbnails.
	Grid,
	/// Detailed list with columns.
	Details
}

/// Represents an asset item in the browser.
class AssetItem
{
	private String mName ~ delete _;
	private String mPath ~ delete _;
	private String mExtension ~ delete _;
	private bool mIsDirectory = false;
	private TextureHandle mIcon;
	private int64 mSize = 0;
	private DateTime mModifiedTime;

	/// Gets the asset name.
	public StringView Name => mName ?? "";

	/// Gets the full path.
	public StringView Path => mPath ?? "";

	/// Gets the file extension.
	public StringView Extension => mExtension ?? "";

	/// Gets whether this is a directory.
	public bool IsDirectory => mIsDirectory;

	/// Gets or sets the icon.
	public TextureHandle Icon
	{
		get => mIcon;
		set => mIcon = value;
	}

	/// Gets the file size in bytes.
	public int64 Size => mSize;

	/// Gets the last modified time.
	public DateTime ModifiedTime => mModifiedTime;

	/// Creates an asset item.
	public this(StringView path, bool isDirectory)
	{
		mPath = new String(path);
		mIsDirectory = isDirectory;

		// Extract name from path
		let lastSep = path.LastIndexOf('/');
		let lastSep2 = path.LastIndexOf('\\');
		let sep = Math.Max(lastSep, lastSep2);
		if (sep >= 0)
			mName = new String(path.Substring(sep + 1));
		else
			mName = new String(path);

		// Extract extension
		if (!isDirectory)
		{
			let dotIndex = mName.LastIndexOf('.');
			if (dotIndex >= 0)
				mExtension = new String(mName.Substring(dotIndex));
		}
	}

	/// Sets the file info.
	public void SetFileInfo(int64 size, DateTime modifiedTime)
	{
		mSize = size;
		mModifiedTime = modifiedTime;
	}
}

/// A panel for browsing and managing assets.
class AssetBrowser : ToolPanel
{
	private String mRootPath ~ delete _;
	private String mCurrentPath ~ delete _;
	private List<AssetItem> mItems = new .() ~ DeleteContainerAndItems!(_);
	private List<String> mSelectedAssets = new .() ~ DeleteContainerAndItems!(_);
	private AssetViewMode mViewMode = .Grid;
	private String mFilter ~ delete _;
	private int32 mHoveredIndex = -1;
	private int32 mSelectedIndex = -1;
	private float mScrollOffset = 0;

	// Visual properties
	private Color mBackgroundColor = Color(35, 35, 35, 255);
	private Color mPathBarBackground = Color(45, 45, 45, 255);
	private Color mItemBackground = Color(50, 50, 50, 255);
	private Color mItemHoverBackground = Color(60, 60, 60, 255);
	private Color mItemSelectedBackground = Color(70, 100, 150, 255);
	private Color mTextColor = Color(200, 200, 200, 255);
	private Color mSecondaryTextColor = Color(140, 140, 140, 255);
	private Color mFolderColor = Color(220, 200, 100, 255);
	private float mGridItemSize = 80;
	private float mGridSpacing = 8;
	private float mListItemHeight = 24;
	private float mPathBarHeight = 28;

	/// Event raised when an asset is selected.
	public Event<delegate void(StringView path)> OnAssetSelected ~ _.Dispose();

	/// Event raised when an asset is double-clicked/opened.
	public Event<delegate void(StringView path)> OnAssetOpened ~ _.Dispose();

	/// Event raised when an asset is renamed.
	public Event<delegate void(StringView oldPath, StringView newPath)> OnAssetRenamed ~ _.Dispose();

	/// Event raised when an asset is deleted.
	public Event<delegate void(StringView path)> OnAssetDeleted ~ _.Dispose();

	/// Gets or sets the root path.
	public StringView RootPath
	{
		get => mRootPath ?? "";
		set
		{
			String.NewOrSet!(mRootPath, value);
			NavigateTo(value);
		}
	}

	/// Gets or sets the current path.
	public StringView CurrentPath
	{
		get => mCurrentPath ?? "";
		set => NavigateTo(value);
	}

	/// Gets or sets the view mode.
	public AssetViewMode ViewMode
	{
		get => mViewMode;
		set
		{
			mViewMode = value;
			InvalidateMeasure();
		}
	}

	/// Gets or sets the filter.
	public StringView Filter
	{
		get => mFilter ?? "";
		set
		{
			String.NewOrSet!(mFilter, value);
			RefreshItems();
		}
	}

	/// Gets the selected assets.
	public List<String> SelectedAssets => mSelectedAssets;

	/// Creates an asset browser.
	public this() : base("Assets")
	{
	}

	/// Creates an asset browser with a root path.
	public this(StringView rootPath) : base("Assets")
	{
		RootPath = rootPath;
	}

	protected override void OnBuildUI()
	{
		// AssetBrowser manages its own content
	}

	/// Navigates to the specified path.
	public void NavigateTo(StringView path)
	{
		String.NewOrSet!(mCurrentPath, path);
		RefreshItems();
	}

	/// Navigates up one directory.
	public void NavigateUp()
	{
		if (mCurrentPath == null || mCurrentPath.Length == 0)
			return;

		let lastSep = mCurrentPath.LastIndexOf('/');
		let lastSep2 = mCurrentPath.LastIndexOf('\\');
		let sep = Math.Max(lastSep, lastSep2);

		if (sep > 0)
		{
			let parentPath = scope String(mCurrentPath, 0, sep);
			NavigateTo(parentPath);
		}
	}

	/// Refreshes the items list.
	public void RefreshItems()
	{
		// Clear existing items
		for (let item in mItems)
			delete item;
		mItems.Clear();

		mSelectedIndex = -1;
		mHoveredIndex = -1;
		mScrollOffset = 0;

		if (mCurrentPath == null || mCurrentPath.Length == 0)
		{
			InvalidateMeasure();
			return;
		}

		// Add parent directory entry
		if (mRootPath == null || !mCurrentPath.Equals(mRootPath, .OrdinalIgnoreCase))
		{
			let parent = new AssetItem("..", true);
			mItems.Add(parent);
		}

		// List directory contents
		for (let entry in Directory.EnumerateDirectories(mCurrentPath))
		{
			let dirPath = scope String();
			entry.GetFilePath(dirPath);
			let item = new AssetItem(dirPath, true);
			mItems.Add(item);
		}

		for (let entry in Directory.EnumerateFiles(mCurrentPath))
		{
			let filePath = scope String();
			entry.GetFilePath(filePath);

			// Apply filter
			if (mFilter != null && mFilter.Length > 0)
			{
				let fileName = scope String();
				entry.GetFileName(fileName);
				if (!fileName.Contains(mFilter, true))
					continue;
			}

			let item = new AssetItem(filePath, false);
			mItems.Add(item);
		}

		InvalidateMeasure();
	}

	/// Selects an asset.
	public void SelectAsset(int32 index)
	{
		if (index < 0 || index >= mItems.Count)
		{
			mSelectedIndex = -1;
			for (let s in mSelectedAssets)
				delete s;
			mSelectedAssets.Clear();
			return;
		}

		mSelectedIndex = index;
		let item = mItems[index];

		for (let s in mSelectedAssets)
			delete s;
		mSelectedAssets.Clear();
		mSelectedAssets.Add(new String(item.Path));

		OnAssetSelected(item.Path);
		InvalidateVisual();
	}

	/// Opens an asset (navigates if directory, opens if file).
	public void OpenAsset(int32 index)
	{
		if (index < 0 || index >= mItems.Count)
			return;

		let item = mItems[index];

		if (item.IsDirectory)
		{
			if (item.Name == "..")
				NavigateUp();
			else
				NavigateTo(item.Path);
		}
		else
		{
			OnAssetOpened(item.Path);
		}
	}

	protected override void OnRender(DrawContext dc)
	{
		base.OnRender(dc);

		let contentBounds = ContentBounds;
		let browserBounds = RectangleF(
			contentBounds.X,
			contentBounds.Y + HeaderHeight,
			contentBounds.Width,
			contentBounds.Height - HeaderHeight
		);

		// Path bar
		let pathBarRect = RectangleF(browserBounds.X, browserBounds.Y, browserBounds.Width, mPathBarHeight);
		dc.FillRect(pathBarRect, mPathBarBackground);

		// Back button
		let backRect = RectangleF(pathBarRect.X + 4, pathBarRect.Y + 4, 20, mPathBarHeight - 8);
		dc.DrawText("<", Font, FontSize, backRect, mTextColor, .Center, .Center, false);

		// Current path
		let pathTextRect = RectangleF(pathBarRect.X + 28, pathBarRect.Y, pathBarRect.Width - 32, mPathBarHeight);
		dc.DrawText(CurrentPath, Font, FontSize - 1, pathTextRect, mTextColor, .Start, .Center, false);

		// Content area
		let contentRect = RectangleF(
			browserBounds.X,
			browserBounds.Y + mPathBarHeight,
			browserBounds.Width,
			browserBounds.Height - mPathBarHeight
		);
		dc.FillRect(contentRect, mBackgroundColor);

		// Render items based on view mode
		switch (mViewMode)
		{
		case .Grid:
			RenderGridView(dc, contentRect);
		case .List, .Details:
			RenderListView(dc, contentRect);
		}
	}

	private void RenderGridView(DrawContext dc, RectangleF contentRect)
	{
		let itemsPerRow = (int32)((contentRect.Width - mGridSpacing) / (mGridItemSize + mGridSpacing));
		if (itemsPerRow <= 0)
			return;

		var x = contentRect.X + mGridSpacing;
		var y = contentRect.Y + mGridSpacing - mScrollOffset;
		int32 col = 0;

		for (int32 i = 0; i < mItems.Count; i++)
		{
			let item = mItems[i];
			let itemRect = RectangleF(x, y, mGridItemSize, mGridItemSize + 20);

			if (itemRect.Bottom > contentRect.Y && itemRect.Y < contentRect.Bottom)
			{
				// Background
				Color bgColor;
				if (i == mSelectedIndex)
					bgColor = mItemSelectedBackground;
				else if (i == mHoveredIndex)
					bgColor = mItemHoverBackground;
				else
					bgColor = mItemBackground;

				dc.FillRoundedRect(itemRect, CornerRadius.Uniform(4), bgColor);

				// Icon area
				let iconRect = RectangleF(x + 8, y + 8, mGridItemSize - 16, mGridItemSize - 24);
				if (item.Icon.Value != 0)
				{
					dc.DrawImage(item.Icon, iconRect, Color.White);
				}
				else
				{
					// Default icon (folder or file indicator)
					let iconColor = item.IsDirectory ? mFolderColor : mSecondaryTextColor;
					let iconText = item.IsDirectory ? "D" : "F";
					dc.DrawText(iconText, Font, 24, iconRect, iconColor, .Center, .Center, false);
				}

				// Name
				let nameRect = RectangleF(x + 2, y + mGridItemSize - 16, mGridItemSize - 4, 16);
				dc.DrawText(item.Name, Font, FontSize - 2, nameRect, mTextColor, .Center, .Center, false);
			}

			x += mGridItemSize + mGridSpacing;
			col++;
			if (col >= itemsPerRow)
			{
				col = 0;
				x = contentRect.X + mGridSpacing;
				y += mGridItemSize + 20 + mGridSpacing;
			}
		}
	}

	private void RenderListView(DrawContext dc, RectangleF contentRect)
	{
		var y = contentRect.Y - mScrollOffset;

		for (int32 i = 0; i < mItems.Count; i++)
		{
			let item = mItems[i];
			let itemRect = RectangleF(contentRect.X, y, contentRect.Width, mListItemHeight);

			if (itemRect.Bottom > contentRect.Y && itemRect.Y < contentRect.Bottom)
			{
				// Background
				Color bgColor;
				if (i == mSelectedIndex)
					bgColor = mItemSelectedBackground;
				else if (i == mHoveredIndex)
					bgColor = mItemHoverBackground;
				else if (i % 2 == 0)
					bgColor = mItemBackground;
				else
					bgColor = Color(45, 45, 45, 255);

				dc.FillRect(itemRect, bgColor);

				// Icon
				let iconSize = mListItemHeight - 4;
				if (item.Icon.Value != 0)
				{
					dc.DrawImage(item.Icon, RectangleF(itemRect.X + 4, itemRect.Y + 2, iconSize, iconSize), Color.White);
				}
				else
				{
					let iconColor = item.IsDirectory ? mFolderColor : mSecondaryTextColor;
					let iconText = item.IsDirectory ? "D" : "F";
					let iconRect = RectangleF(itemRect.X + 4, itemRect.Y + 2, iconSize, iconSize);
					dc.DrawText(iconText, Font, FontSize - 2, iconRect, iconColor, .Center, .Center, false);
				}

				// Name
				let nameRect = RectangleF(itemRect.X + iconSize + 8, itemRect.Y, itemRect.Width - iconSize - 12, itemRect.Height);
				dc.DrawText(item.Name, Font, FontSize, nameRect, mTextColor, .Start, .Center, false);
			}

			y += mListItemHeight;
		}
	}

	protected override bool OnMouseMove(MouseMoveEventArgs e)
	{
		let contentBounds = ContentBounds;
		let contentRect = RectangleF(
			contentBounds.X,
			contentBounds.Y + HeaderHeight + mPathBarHeight,
			contentBounds.Width,
			contentBounds.Height - HeaderHeight - mPathBarHeight
		);

		int32 newHovered = -1;

		if (contentRect.Contains(e.Position))
		{
			if (mViewMode == .Grid)
			{
				let itemsPerRow = (int32)((contentRect.Width - mGridSpacing) / (mGridItemSize + mGridSpacing));
				if (itemsPerRow > 0)
				{
					let relX = e.Position.X - contentRect.X - mGridSpacing;
					let relY = e.Position.Y - contentRect.Y - mGridSpacing + mScrollOffset;

					let col = (int32)(relX / (mGridItemSize + mGridSpacing));
					let row = (int32)(relY / (mGridItemSize + 20 + mGridSpacing));

					if (col >= 0 && col < itemsPerRow)
					{
						let index = row * itemsPerRow + col;
						if (index >= 0 && index < mItems.Count)
							newHovered = index;
					}
				}
			}
			else
			{
				let relY = e.Position.Y - contentRect.Y + mScrollOffset;
				let index = (int32)(relY / mListItemHeight);
				if (index >= 0 && index < mItems.Count)
					newHovered = index;
			}
		}

		if (mHoveredIndex != newHovered)
		{
			mHoveredIndex = newHovered;
			InvalidateVisual();
		}

		return base.OnMouseMove(e);
	}

	protected override bool OnMouseDown(MouseButtonEventArgs e)
	{
		if (e.Button != .Left)
			return base.OnMouseDown(e);

		let contentBounds = ContentBounds;
		let pathBarRect = RectangleF(
			contentBounds.X,
			contentBounds.Y + HeaderHeight,
			contentBounds.Width,
			mPathBarHeight
		);

		// Check back button
		let backRect = RectangleF(pathBarRect.X + 4, pathBarRect.Y + 4, 20, mPathBarHeight - 8);
		if (backRect.Contains(e.Position))
		{
			NavigateUp();
			return true;
		}

		// Select item
		if (mHoveredIndex >= 0)
		{
			SelectAsset(mHoveredIndex);

			// Double-click detection would go here
			// For now, just select on single click
			return true;
		}

		return base.OnMouseDown(e);
	}

	protected override bool OnMouseWheel(MouseWheelEventArgs e)
	{
		mScrollOffset = Math.Max(0, mScrollOffset - e.DeltaY * 30);
		InvalidateVisual();
		return true;
	}

	protected override bool OnKeyDown(KeyEventArgs e)
	{
		switch (e.Key)
		{
		case .Enter:
			if (mSelectedIndex >= 0)
			{
				OpenAsset(mSelectedIndex);
				return true;
			}
		case .Backspace:
			NavigateUp();
			return true;
		case .Up:
			if (mSelectedIndex > 0)
			{
				SelectAsset(mSelectedIndex - 1);
				return true;
			}
		case .Down:
			if (mSelectedIndex < mItems.Count - 1)
			{
				SelectAsset(mSelectedIndex + 1);
				return true;
			}
		default:
		}

		return base.OnKeyDown(e);
	}
}
