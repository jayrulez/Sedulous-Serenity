namespace Sedulous.Editor.App;

using System;
using System.Collections;
using System.IO;
using Sedulous.UI;
using Sedulous.Mathematics;
using Sedulous.Editor.Core;
using Sedulous.Foundation.Core;

/// View mode for the asset browser.
public enum AssetBrowserViewMode
{
	/// Display assets in a list with details.
	List,
	/// Display assets as tiles with icons.
	Tiles
}

/// Browser panel for navigating and viewing project assets.
public class AssetBrowser : Border
{
	private AssetDatabase mAssetDatabase;
	private String mRootPath = new .() ~ delete _;
	private SplitPanel mSplitPanel;
	private TreeView mFolderTree;
	private TileView mAssetTiles;
	private ListBox mAssetList;
	private StackPanel mToolbar;
	private TextBox mSearchBox;
	private Button mViewToggleBtn;
	private AssetBrowserViewMode mViewMode = .Tiles;
	private String mCurrentFolder = new .() ~ delete _;
	private String mSearchFilter = new .() ~ delete _;

	// Events
	private EventAccessor<delegate void(AssetEntry)> mAssetSelectedEvent = new .() ~ delete _;
	private EventAccessor<delegate void(AssetEntry)> mAssetDoubleClickEvent = new .() ~ delete _;

	/// Fired when an asset is selected.
	public EventAccessor<delegate void(AssetEntry)> AssetSelected => mAssetSelectedEvent;

	/// Fired when an asset is double-clicked (open for editing).
	public EventAccessor<delegate void(AssetEntry)> AssetDoubleClick => mAssetDoubleClickEvent;

	/// Current view mode.
	public AssetBrowserViewMode ViewMode
	{
		get => mViewMode;
		set
		{
			if (mViewMode != value)
			{
				mViewMode = value;
				UpdateViewMode();
			}
		}
	}

	public this(AssetDatabase database = null, StringView rootPath = "")
	{
		mAssetDatabase = database;
		mRootPath.Set(rootPath);
		BuildUI();
	}

	/// Sets the asset database to browse.
	public void SetDatabase(AssetDatabase database, StringView rootPath)
	{
		mAssetDatabase = database;
		mRootPath.Set(rootPath);
		mCurrentFolder.Set(rootPath);
		RefreshFolderTree();
		RefreshAssetView();
	}

	/// Refreshes the folder tree.
	public void RefreshFolderTree()
	{
		// Delete String tags before clearing (folder paths are stored as String tags)
		ClearTreeItemTags(mFolderTree.RootItems);
		mFolderTree.ClearItems();

		if (mRootPath.IsEmpty)
			return;

		// Create root node
		let rootItem = mFolderTree.AddItem("Assets");
		rootItem.Tag = new String(mRootPath);
		rootItem.IsExpanded = true;

		// Scan for folders
		BuildFolderTreeRecursive(mRootPath, rootItem);

		// Select root by default
		mFolderTree.SelectedItem = rootItem;
	}

	/// Refreshes the asset view with current folder contents.
	public void RefreshAssetView()
	{
		if (mViewMode == .Tiles)
		{
			// Delete String tags before clearing (folder paths are stored as String tags)
			ClearTileItemTags(mAssetTiles.Items);
			mAssetTiles.ClearItems();
		}
		else
		{
			mAssetList.ClearItems();
		}

		if (mAssetDatabase == null)
			return;

		// Get assets in current folder
		let entries = scope List<AssetEntry>();
		mAssetDatabase.GetEntriesInFolder(mCurrentFolder, entries, false);

		for (let entry in entries)
		{
			// Apply search filter
			if (mSearchFilter.Length > 0)
			{
				if (!entry.Name.Contains(mSearchFilter, true))
					continue;
			}

			// Add to view
			if (mViewMode == .Tiles)
			{
				let item = mAssetTiles.AddItem(entry.Name);
				item.Tag = entry;
			}
			else
			{
				let item = mAssetList.AddItem(entry.Name);
				item.Tag = entry;
			}
		}

		// Also show subfolders as tiles
		if (mViewMode == .Tiles && !mCurrentFolder.IsEmpty)
		{
			let folders = scope List<String>();
			GetSubfolders(mCurrentFolder, folders);

			for (let folder in folders)
			{
				let folderName = Path.GetFileName(folder, .. scope .());
				let item = mAssetTiles.AddItem(folderName);
				item.Tag = new String(folder); // Mark as folder by using String tag
			}

			for (let folder in folders)
				delete folder;
		}
	}

	/// Navigates to a folder.
	public void NavigateToFolder(StringView path)
	{
		mCurrentFolder.Set(path);
		RefreshAssetView();

		// Select folder in tree
		SelectFolderInTree(path);
	}

	private void BuildUI()
	{
		Background = Color(37, 37, 38);
		Padding = .(0);

		let mainPanel = new DockPanel();
		mainPanel.Width = .Fill;
		mainPanel.Height = .Fill;
		mainPanel.LastChildFill = true;

		// Toolbar (docked to top)
		mToolbar = new StackPanel();
		mToolbar.Orientation = .Horizontal;
		mToolbar.Height = .Fixed(28);
		mToolbar.Padding = .(4, 2);
		mToolbar.Spacing = 4;
		mToolbar.Background = Color(45, 45, 48);

		// Search box
		mSearchBox = new TextBox();
		mSearchBox.Placeholder = "Search...";
		mSearchBox.Width = .Fixed(150);
		mSearchBox.Height = .Fixed(22);
		mSearchBox.TextChanged.Subscribe(new (sender, text) => OnSearchChanged());
		mToolbar.AddChild(mSearchBox);

		// Spacer
		let spacer = new Border();
		spacer.Width = .Fill;
		mToolbar.AddChild(spacer);

		// View toggle button
		mViewToggleBtn = new Button();
		mViewToggleBtn.ContentText = "Tiles";
		mViewToggleBtn.Width = .Fixed(50);
		mViewToggleBtn.Height = .Fixed(22);
		mViewToggleBtn.Click.Subscribe(new (sender) => ToggleViewMode());
		mToolbar.AddChild(mViewToggleBtn);

		mainPanel.AddChild(mToolbar);
		mainPanel.SetDock(mToolbar, .Top);

		// Split panel: folder tree | asset view
		mSplitPanel = new SplitPanel();
		mSplitPanel.Width = .Fill;
		mSplitPanel.Height = .Fill;
		mSplitPanel.Orientation = .Horizontal;
		mSplitPanel.SplitterPosition = 180;

		// Folder tree
		mFolderTree = new TreeView();
		mFolderTree.Width = .Fill;
		mFolderTree.Height = .Fill;
		mFolderTree.SelectionChanged.Subscribe(new (tree, item) => OnFolderSelected(item));
		mSplitPanel.Panel1 = mFolderTree;

		// Asset view panel (switches between tiles and list)
		let assetViewPanel = new Grid();
		assetViewPanel.Width = .Fill;
		assetViewPanel.Height = .Fill;

		// Tile view
		mAssetTiles = new TileView();
		mAssetTiles.Width = .Fill;
		mAssetTiles.Height = .Fill;
		mAssetTiles.TileWidth = 80;
		mAssetTiles.TileHeight = 90;
		mAssetTiles.SelectionChanged.Subscribe(new (view, item) => OnAssetSelected(item));
		mAssetTiles.ItemDoubleClick.Subscribe(new (view, item) => OnAssetDoubleClick(item));
		assetViewPanel.AddChild(mAssetTiles);

		// List view (hidden initially)
		mAssetList = new ListBox();
		mAssetList.Width = .Fill;
		mAssetList.Height = .Fill;
		mAssetList.Visibility = .Collapsed;
		mAssetList.SelectionChanged.Subscribe(new (list, oldIdx, newIdx) => OnListAssetSelected());
		assetViewPanel.AddChild(mAssetList);

		mSplitPanel.Panel2 = assetViewPanel;

		mainPanel.AddChild(mSplitPanel);

		Child = mainPanel;
	}

	private void BuildFolderTreeRecursive(StringView folderPath, TreeViewItem parentItem)
	{
		// Get subdirectories
		if (!Directory.Exists(folderPath))
			return;

		for (let entry in Directory.EnumerateDirectories(folderPath))
		{
			let dirName = entry.GetFileName(.. scope .());
			if (dirName.StartsWith('.'))
				continue; // Skip hidden folders

			let fullPath = scope String();
			entry.GetFilePath(fullPath);

			let item = parentItem.AddChild(dirName);
			item.Tag = new String(fullPath);

			// Recursively add subfolders
			BuildFolderTreeRecursive(fullPath, item);
		}
	}

	private void GetSubfolders(StringView folderPath, List<String> outFolders)
	{
		if (!Directory.Exists(folderPath))
			return;

		for (let entry in Directory.EnumerateDirectories(folderPath))
		{
			let dirName = entry.GetFileName(.. scope .());
			if (dirName.StartsWith('.'))
				continue;

			let fullPath = scope String();
			entry.GetFilePath(fullPath);
			outFolders.Add(new String(fullPath));
		}
	}

	private void SelectFolderInTree(StringView path)
	{
		// Find and select the folder item in the tree
		for (let item in mFolderTree.RootItems)
		{
			if (SelectFolderInTreeRecursive(item, path))
				break;
		}
	}

	private bool SelectFolderInTreeRecursive(TreeViewItem item, StringView path)
	{
		if (let folderPath = item.Tag as String)
		{
			if (folderPath.Equals(path, .OrdinalIgnoreCase))
			{
				mFolderTree.SelectAndScrollTo(item);
				return true;
			}
		}

		for (let child in item.Children)
		{
			if (SelectFolderInTreeRecursive(child, path))
				return true;
		}

		return false;
	}

	private void OnFolderSelected(TreeViewItem item)
	{
		if (item == null)
			return;

		if (let folderPath = item.Tag as String)
		{
			mCurrentFolder.Set(folderPath);
			RefreshAssetView();
		}
	}

	private void OnAssetSelected(TileViewItem item)
	{
		if (item == null)
			return;

		if (let entry = item.Tag as AssetEntry)
		{
			mAssetSelectedEvent.[Friend]Invoke(entry);
		}
	}

	private void OnAssetDoubleClick(TileViewItem item)
	{
		if (item == null)
			return;

		// Check if it's a folder
		if (let folderPath = item.Tag as String)
		{
			NavigateToFolder(folderPath);
			return;
		}

		if (let entry = item.Tag as AssetEntry)
		{
			mAssetDoubleClickEvent.[Friend]Invoke(entry);
		}
	}

	private void OnListAssetSelected()
	{
		let item = mAssetList.SelectedItem;
		if (item == null)
			return;

		if (let entry = item.Tag as AssetEntry)
		{
			mAssetSelectedEvent.[Friend]Invoke(entry);
		}
	}

	private void OnSearchChanged()
	{
		mSearchFilter.Set(mSearchBox.Text);
		RefreshAssetView();
	}

	private void ToggleViewMode()
	{
		if (mViewMode == .Tiles)
		{
			mViewMode = .List;
			mViewToggleBtn.ContentText = "List";
		}
		else
		{
			mViewMode = .Tiles;
			mViewToggleBtn.ContentText = "Tiles";
		}

		UpdateViewMode();
	}

	private void UpdateViewMode()
	{
		if (mViewMode == .Tiles)
		{
			mAssetTiles.Visibility = .Visible;
			mAssetList.Visibility = .Collapsed;
		}
		else
		{
			mAssetTiles.Visibility = .Collapsed;
			mAssetList.Visibility = .Visible;
		}

		RefreshAssetView();
	}

	/// Clears String tags from tree view items (recursive).
	private void ClearTreeItemTags(List<TreeViewItem> items)
	{
		for (let item in items)
		{
			if (let str = item.Tag as String)
				delete str;
			item.Tag = null;
			ClearTreeItemTags(item.Children);
		}
	}

	/// Clears String tags from tile view items.
	private void ClearTileItemTags(List<TileViewItem> items)
	{
		for (let item in items)
		{
			// Only delete String tags (folder paths), not AssetEntry references
			if (let str = item.Tag as String)
				delete str;
			item.Tag = null;
		}
	}
}
