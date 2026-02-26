namespace SceneEditor;

using System;
using System.IO;
using System.Collections;
using Sedulous.GUI;
using Sedulous.Foundation.Mathematics;

/// File browser panel for the project directory, showing available resources.
class AssetBrowserPanel
{
	private Grid mRoot;
	private TreeView mTreeView;
	private String mProjectDirectory ~ delete _;
	private Dictionary<TreeViewItem, String> mItemPaths = new .() ~ DeleteDictionaryAndValues!(_);

	// Callbacks
	public delegate void(StringView path) OnFileSelected ~ delete _;

	/// The root UI element to add to the layout.
	public Grid Root => mRoot;

	public this()
	{
		BuildUI();
	}

	private void BuildUI()
	{
		mRoot = new Grid();
		mRoot.RowDefinitions.Add(new .() { Height = .Auto });   // toolbar
		mRoot.RowDefinitions.Add(new .() { Height = .Star });   // tree
		mRoot.ColumnDefinitions.Add(new .() { Width = .Star });
		mRoot.Background = Color(30, 30, 38, 255);

		// Toolbar
		let toolbar = new Grid();
		toolbar.ColumnDefinitions.Add(new .() { Width = .Star });  // title
		toolbar.ColumnDefinitions.Add(new .() { Width = .Auto });  // refresh button
		toolbar.Padding = .(6, 4, 6, 4);
		GridProperties.SetRow(toolbar, 0);
		mRoot.AddChild(toolbar);

		let titleLabel = new Label("Assets");
		titleLabel.FontSize = 13;
		titleLabel.Foreground = Color(180, 180, 200, 255);
		titleLabel.VerticalAlignment = .Center;
		GridProperties.SetColumn(titleLabel, 0);
		toolbar.AddChild(titleLabel);

		let refreshBtn = new Button();
		refreshBtn.Content = new TextBlock("R");
		refreshBtn.Width = .Fixed(28);
		refreshBtn.Height = .Fixed(22);
		refreshBtn.Click.Subscribe(new (btn) => RefreshTree());
		GridProperties.SetColumn(refreshBtn, 1);
		toolbar.AddChild(refreshBtn);

		// Tree view
		mTreeView = new TreeView();
		mTreeView.Padding = .(2, 2, 2, 2);
		GridProperties.SetRow(mTreeView, 1);
		mTreeView.SelectionChanged.Subscribe(new (tv) => OnTreeSelectionChanged());
		mRoot.AddChild(mTreeView);
	}

	/// Sets the project directory and refreshes the tree.
	public void SetProjectDirectory(StringView path)
	{
		if (mProjectDirectory != null)
			delete mProjectDirectory;

		if (path.Length > 0)
			mProjectDirectory = new String(path);
		else
			mProjectDirectory = null;

		RefreshTree();
	}

	/// Refreshes the tree from the current project directory.
	public void RefreshTree()
	{
		mTreeView.ClearItems();
		for (let kv in mItemPaths)
			delete kv.value;
		mItemPaths.Clear();

		if (mProjectDirectory == null || mProjectDirectory.IsEmpty)
			return;

		if (!Directory.Exists(mProjectDirectory))
			return;

		PopulateDirectory(mProjectDirectory, null);
	}

	private void PopulateDirectory(StringView dirPath, TreeViewItem parent)
	{
		// Add subdirectories first
		for (let entry in Directory.EnumerateDirectories(dirPath))
		{
			let subName = entry.GetFileName(.. scope .());
			let subPath = entry.GetFilePath(.. scope .());

			TreeViewItem dirItem;
			if (parent != null)
				dirItem = parent.AddChild(subName);
			else
				dirItem = mTreeView.AddItem(subName);

			mItemPaths[dirItem] = new String(subPath);
			PopulateDirectory(subPath, dirItem);
		}

		// Add resource files
		for (let entry in Directory.EnumerateFiles(dirPath))
		{
			let fileName = entry.GetFileName(.. scope .());
			let ext = Path.GetExtension(fileName, .. scope .());

			if (IsResourceExtension(ext))
			{
				TreeViewItem fileItem;
				if (parent != null)
					fileItem = parent.AddChild(fileName);
				else
					fileItem = mTreeView.AddItem(fileName);

				let filePath = entry.GetFilePath(.. new .());
				mItemPaths[fileItem] = filePath;
			}
		}
	}

	private static bool IsResourceExtension(StringView ext)
	{
		let lower = scope String(ext);
		lower.ToLower();
		return lower == ".mesh" || lower == ".skinnedmesh" || lower == ".material" ||
			lower == ".texture" || lower == ".skeleton" || lower == ".animation" || lower == ".scene";
	}

	private void OnTreeSelectionChanged()
	{
		let item = mTreeView.SelectedItem;
		if (item != null && mItemPaths.TryGetValue(item, let path))
			OnFileSelected?.Invoke(path);
	}
}
