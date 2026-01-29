namespace Sedulous.Editor.Scenes;

using System;
using System.Collections;
using Sedulous.UI;
using Sedulous.Mathematics;

/// Panel displaying scene entity hierarchy as a tree.
class SceneHierarchyPanel : Border
{
	private SceneAssetDocument mDocument;
	private TreeView mTreeView;
	private StackPanel mToolbar;
	private Button mAddEntityBtn;

	// Map entity IDs to tree items for quick lookup
	private Dictionary<Guid, TreeViewItem> mEntityToItem = new .() ~ delete _;

	public this(SceneAssetDocument document)
	{
		mDocument = document;
		BuildUI();
	}

	private void BuildUI()
	{
		Background = Color(37, 37, 38);

		let mainPanel = new DockPanel();
		mainPanel.Width = .Fill;
		mainPanel.Height = .Fill;
		mainPanel.LastChildFill = true;

		// Toolbar at top
		mToolbar = new StackPanel();
		mToolbar.Orientation = .Horizontal;
		mToolbar.Height = .Fixed(28);
		mToolbar.Padding = .(4, 2);
		mToolbar.Spacing = 4;
		mToolbar.Background = Color(45, 45, 48);

		mAddEntityBtn = new Button();
		mAddEntityBtn.ContentText = "+ Entity";
		mAddEntityBtn.Width = .Fixed(70);
		mAddEntityBtn.Height = .Fixed(22);
		mAddEntityBtn.Click.Subscribe(new (sender) => OnAddEntity());
		mToolbar.AddChild(mAddEntityBtn);

		mainPanel.AddChild(mToolbar);
		mainPanel.SetDock(mToolbar, .Top);

		// Tree view for hierarchy
		mTreeView = new TreeView();
		mTreeView.Width = .Fill;
		mTreeView.Height = .Fill;
		mTreeView.SelectionChanged.Subscribe(new (tree, item) => OnSelectionChanged(item));
		mTreeView.ItemDoubleClick.Subscribe(new (tree, item) => OnItemDoubleClick(item));

		mainPanel.AddChild(mTreeView);

		Child = mainPanel;

		// Initial refresh
		Refresh();
	}

	/// Refresh the hierarchy tree from the scene asset.
	public void Refresh()
	{
		// Clear existing items (TreeViewItem Tags are just Guids, not owned strings)
		mTreeView.ClearItems();
		mEntityToItem.Clear();

		let asset = mDocument.SceneAsset;

		// Build tree from entities
		// First pass: create all items
		for (let entity in asset.Entities)
		{
			let item = new TreeViewItem(entity.Name);
			item.Tag = entity; // Store EntityData reference
			mEntityToItem[entity.EntityId] = item;
		}

		// Second pass: build hierarchy
		for (let entity in asset.Entities)
		{
			if (let item = mEntityToItem.GetValueOrDefault(entity.EntityId))
			{
				if (entity.ParentId == default)
				{
					// Root entity
					mTreeView.AddItem(item);
				}
				else
				{
					// Child entity - add to parent
					if (let parentItem = mEntityToItem.GetValueOrDefault(entity.ParentId))
					{
						parentItem.AddChild(item);
					}
					else
					{
						// Parent not found, add as root
						mTreeView.AddItem(item);
					}
				}
			}
		}

		// Expand all by default
		mTreeView.ExpandAll();

		// Restore selection
		RefreshSelection();
	}

	/// Refresh selection highlighting in tree.
	public void RefreshSelection()
	{
		// Clear existing selection
		mTreeView.SelectedItem = null;

		// Select first selected entity in tree
		if (mDocument.SelectedEntities.Length > 0)
		{
			let firstSelected = mDocument.SelectedEntities[0];
			if (let item = mEntityToItem.GetValueOrDefault(firstSelected))
			{
				mTreeView.SelectedItem = item;
			}
		}
	}

	private void OnSelectionChanged(TreeViewItem item)
	{
		if (item == null)
		{
			mDocument.ClearSelection();
			return;
		}

		if (let entity = item.Tag as EntityData)
		{
			mDocument.Select(entity.EntityId);
		}
	}

	private void OnItemDoubleClick(TreeViewItem item)
	{
		// Could focus camera on entity in viewport
		// For now, just toggle expansion
	}

	private void OnAddEntity()
	{
		// Add entity as child of selected, or as root if nothing selected
		Guid parentId = default;
		if (mDocument.SelectedEntities.Length > 0)
			parentId = mDocument.SelectedEntities[0];

		let newId = mDocument.CreateEntity("New Entity", parentId);
		mDocument.Select(newId);
	}
}
