namespace SceneEditor;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.GUI;
using Sedulous.Framework.Scenes;
using Sedulous.Framework.Render;

/// Encapsulates the entity hierarchy tree view with toolbar for add/delete operations.
class HierarchyPanel
{
	// UI elements
	private Grid mRoot;
	private TreeView mTreeView;
	private ContextMenu mAddMenu ~ delete _;

	// Mapping from tree items to entities
	private Dictionary<TreeViewItem, EntityId> mItemToEntity = new .() ~ delete _;

	// Current state
	private SceneTab mCurrentTab;

	// Callbacks
	public delegate void(List<EntityId> entities) OnSelectionChanged ~ delete _;
	public delegate void() OnStructureChanged ~ delete _;

	/// The root UI element to add to the layout.
	public Grid Root => mRoot;

	public this()
	{
		BuildUI();
		BuildAddMenu();
		BuildItemContextMenu();
	}

	// ==================== UI Construction ====================

	private void BuildUI()
	{
		mRoot = new Grid();
		mRoot.RowDefinitions.Add(new .() { Height = .Auto });  // toolbar
		mRoot.RowDefinitions.Add(new .() { Height = .Star });  // tree
		mRoot.ColumnDefinitions.Add(new .() { Width = .Star });
		mRoot.Background = Color(30, 30, 38, 255);

		// Toolbar (Grid so .Star column fills remaining space)
		let toolbar = new Grid();
		toolbar.ColumnDefinitions.Add(new .() { Width = .Star });  // title (fills)
		toolbar.ColumnDefinitions.Add(new .() { Width = .Auto });  // + button
		toolbar.ColumnDefinitions.Add(new .() { Width = .Auto });  // X button
		toolbar.Padding = .(6, 4, 6, 4);
		GridProperties.SetRow(toolbar, 0);
		mRoot.AddChild(toolbar);

		let titleLabel = new Label("Hierarchy");
		titleLabel.FontSize = 13;
		titleLabel.Foreground = Color(180, 180, 200, 255);
		titleLabel.VerticalAlignment = .Center;
		GridProperties.SetColumn(titleLabel, 0);
		toolbar.AddChild(titleLabel);

		// Add button
		let addButton = new Button();
		addButton.Content = new TextBlock("+");
		addButton.Width = .Fixed(28);
		addButton.Height = .Fixed(22);
		addButton.Margin = .(2, 0, 2, 0);
		addButton.Click.Subscribe(new (btn) => ShowAddMenu(btn));
		GridProperties.SetColumn(addButton, 1);
		toolbar.AddChild(addButton);

		// Delete button
		let deleteButton = new Button();
		deleteButton.Content = new TextBlock("X");
		deleteButton.Width = .Fixed(28);
		deleteButton.Height = .Fixed(22);
		deleteButton.Click.Subscribe(new (btn) => DeleteSelectedEntity());
		GridProperties.SetColumn(deleteButton, 2);
		toolbar.AddChild(deleteButton);

		// Tree view
		mTreeView = new TreeView();
		mTreeView.Padding = .(2, 2, 2, 2);
		mTreeView.IsEditable = true;
		GridProperties.SetRow(mTreeView, 1);
		mTreeView.SelectionChanged.Subscribe(new (tv) => OnTreeSelectionChanged());
		mTreeView.ItemRenamed.Subscribe(new (tv, item, newText) => OnItemRenamed(item, newText));
		mRoot.AddChild(mTreeView);
	}

	private void BuildAddMenu()
	{
		mAddMenu = new ContextMenu();

		let emptyItem = mAddMenu.AddItem("Empty Entity");
		emptyItem.Click.Subscribe(new (mi) => AddEntity(.Empty));

		mAddMenu.AddSeparator();

		let dirLightItem = mAddMenu.AddItem("Directional Light");
		dirLightItem.Click.Subscribe(new (mi) => AddEntity(.DirectionalLight));

		let pointLightItem = mAddMenu.AddItem("Point Light");
		pointLightItem.Click.Subscribe(new (mi) => AddEntity(.PointLight));

		let spotLightItem = mAddMenu.AddItem("Spot Light");
		spotLightItem.Click.Subscribe(new (mi) => AddEntity(.SpotLight));

		mAddMenu.AddSeparator();

		let cameraItem = mAddMenu.AddItem("Camera");
		cameraItem.Click.Subscribe(new (mi) => AddEntity(.Camera));
	}

	private void BuildItemContextMenu()
	{
		// Assign to TreeView's ContextMenu property — framework handles right-click automatically.
		// TreeView takes ownership, so we don't delete it ourselves.
		let menu = new ContextMenu();

		let addChildItem = menu.AddItem("Add Child Entity");
		addChildItem.Click.Subscribe(new (mi) => AddChildToSelected());

		menu.AddSeparator();

		let duplicateItem = menu.AddItem("Duplicate");
		duplicateItem.Click.Subscribe(new (mi) => DuplicateSelectedEntity());

		let renameItem = menu.AddItem("Rename");
		renameItem.Click.Subscribe(new (mi) => RenameSelectedEntity());

		menu.AddSeparator();

		let deleteItem = menu.AddItem("Delete");
		deleteItem.Click.Subscribe(new (mi) => DeleteSelectedEntity());

		mTreeView.ContextMenu = menu;
	}

	// ==================== Tab / Hierarchy Management ====================

	/// Sets the current tab and rebuilds the hierarchy.
	public void SetTab(SceneTab tab)
	{
		mCurrentTab = tab;
		RebuildHierarchy();
	}

	/// Clears the hierarchy (no tab selected).
	public void Clear()
	{
		mCurrentTab = null;
		mTreeView.ClearItems();
		mItemToEntity.Clear();
	}

	/// Rebuilds the entire hierarchy tree from the current tab's scene.
	public void RebuildHierarchy()
	{
		mTreeView.ClearItems();
		mItemToEntity.Clear();

		if (mCurrentTab?.Scene == null)
			return;

		let scene = mCurrentTab.Scene;

		// Collect root entities (no parent)
		let rootEntities = scope List<EntityId>();
		scene.ForEachEntity(scope [&](entity) =>
			{
				if (!scene.GetParent(entity).IsValid)
					rootEntities.Add(entity);
			});

		for (let entity in rootEntities)
			AddEntityToTree(entity, null);
	}

	/// Updates the display name of a specific entity in the tree without rebuilding.
	public void RefreshEntityName(EntityId entity)
	{
		if (mCurrentTab?.Scene == null)
			return;

		for (let (item, itemEntity) in mItemToEntity)
		{
			if (itemEntity == entity)
			{
				let name = mCurrentTab.Scene.GetName(entity);
				let displayName = scope String();
				if (name.IsEmpty)
					displayName.AppendF("Entity_{}", entity.Index);
				else
					displayName.Set(name);
				item.Text = displayName;
				break;
			}
		}
	}

	/// Recursively adds an entity and its children to the tree.
	private void AddEntityToTree(EntityId entity, TreeViewItem parent)
	{
		let scene = mCurrentTab.Scene;
		let name = scene.GetName(entity);

		let displayName = scope String();
		if (name.IsEmpty)
			displayName.AppendF("Entity_{}", entity.Index);
		else
			displayName.Set(name);

		TreeViewItem item;
		if (parent != null)
			item = parent.AddChild(displayName);
		else
			item = mTreeView.AddItem(displayName);

		mItemToEntity[item] = entity;

		// Add children recursively
		let children = scope List<EntityId>();
		scene.GetChildren(entity, children);
		for (let child in children)
			AddEntityToTree(child, item);

		// Auto-expand items with children
		if (children.Count > 0)
			item.IsExpanded = true;
	}

	// ==================== Entity Creation ====================

	private enum EntityPreset
	{
		Empty,
		DirectionalLight,
		PointLight,
		SpotLight,
		Camera
	}

	private void AddEntity(EntityPreset preset, EntityId parent = .Invalid)
	{
		if (mCurrentTab?.Scene == null)
			return;

		let scene = mCurrentTab.Scene;
		let entity = scene.CreateEntity();

		switch (preset)
		{
		case .Empty:
			scene.SetName(entity, "Entity");

		case .DirectionalLight:
			scene.SetName(entity, "Directional Light");
			scene.SetRotation(entity, Quaternion.CreateFromYawPitchRoll(0.5f, -1.0f, 0));
			var light = LightComponent.Default;
			light.Type = .Directional;
			light.Intensity = 2.5f;
			light.CastsShadows = true;
			scene.SetComponent<LightComponent>(entity, light);

		case .PointLight:
			scene.SetName(entity, "Point Light");
			var light = LightComponent.Default;
			light.Type = .Point;
			light.Range = 10.0f;
			scene.SetComponent<LightComponent>(entity, light);

		case .SpotLight:
			scene.SetName(entity, "Spot Light");
			var light = LightComponent.Default;
			light.Type = .Spot;
			light.Range = 15.0f;
			light.InnerConeAngle = 0.3f;
			light.OuterConeAngle = 0.5f;
			scene.SetComponent<LightComponent>(entity, light);

		case .Camera:
			scene.SetName(entity, "Camera");
			scene.SetComponent<CameraComponent>(entity, CameraComponent.Default);
		}

		if (parent.IsValid)
			scene.SetParent(entity, parent);

		mCurrentTab.MarkDirty();
		RebuildHierarchy();

		// Select the new entity
		SelectEntity(entity);

		OnStructureChanged?.Invoke();
	}

	private void AddChildToSelected()
	{
		let selectedItem = mTreeView.SelectedItem;
		if (selectedItem == null)
			return;

		if (mItemToEntity.TryGetValue(selectedItem, let parentEntity))
			AddEntity(.Empty, parentEntity);
	}

	// ==================== Entity Deletion ====================

	/// Deletes the currently selected entity and its children.
	public void DeleteSelectedEntity()
	{
		if (mCurrentTab?.Scene == null)
			return;

		let selectedItem = mTreeView.SelectedItem;
		if (selectedItem == null)
			return;

		if (!mItemToEntity.TryGetValue(selectedItem, let entity))
			return;

		mCurrentTab.Scene.DestroyEntity(entity);
		mCurrentTab.MarkDirty();
		RebuildHierarchy();
		OnStructureChanged?.Invoke();
	}

	// ==================== Entity Duplication ====================

	private void DuplicateSelectedEntity()
	{
		if (mCurrentTab?.Scene == null)
			return;

		let selectedItem = mTreeView.SelectedItem;
		if (selectedItem == null)
			return;

		if (!mItemToEntity.TryGetValue(selectedItem, let srcEntity))
			return;

		let scene = mCurrentTab.Scene;

		// Duplicate the entity and all children recursively
		let parent = scene.GetParent(srcEntity);
		let newEntity = DuplicateEntityRecursive(scene, srcEntity, parent);

		mCurrentTab.MarkDirty();
		RebuildHierarchy();
		SelectEntity(newEntity);
		OnStructureChanged?.Invoke();
	}

	/// Recursively duplicates an entity and all its children. Returns the new root entity.
	private EntityId DuplicateEntityRecursive(Scene scene, EntityId src, EntityId newParent)
	{
		let newEntity = scene.CreateEntity();

		// Copy name with suffix (only on the top-level duplicate)
		let srcName = scene.GetName(src);
		let newName = scope String();
		if (srcName.IsEmpty)
			newName.AppendF("Entity_{}", newEntity.Index);
		else
			newName.Set(srcName);
		scene.SetName(newEntity, newName);

		// Copy transform
		scene.SetTransform(newEntity, scene.GetTransform(src));

		// Set parent
		if (newParent.IsValid)
			scene.SetParent(newEntity, newParent);

		// Copy known components
		CopyComponent<LightComponent>(scene, src, newEntity);
		CopyComponent<CameraComponent>(scene, src, newEntity);
		CopyComponent<MeshRendererComponent>(scene, src, newEntity);
		CopyComponent<SkinnedMeshRendererComponent>(scene, src, newEntity);
		CopyComponent<SpriteComponent>(scene, src, newEntity);
		CopyComponent<ParticleEmitterComponent>(scene, src, newEntity);

		// Recursively duplicate children
		let children = scope List<EntityId>();
		scene.GetChildren(src, children);
		for (let child in children)
			DuplicateEntityRecursive(scene, child, newEntity);

		return newEntity;
	}

	private void CopyComponent<T>(Scene scene, EntityId src, EntityId dst) where T : struct, IComponent
	{
		let comp = scene.GetComponent<T>(src);
		if (comp != null)
			scene.SetComponent<T>(dst, *comp);
	}

	// ==================== Rename ====================

	/// Starts inline rename on the selected entity.
	public void BeginRename()
	{
		mTreeView.BeginEdit();
	}

	private void RenameSelectedEntity()
	{
		mTreeView.BeginEdit();
	}

	private void OnItemRenamed(TreeViewItem item, StringView newText)
	{
		if (mCurrentTab?.Scene == null)
			return;

		if (!mItemToEntity.TryGetValue(item, let entity))
			return;

		mCurrentTab.Scene.SetName(entity, newText);
		mCurrentTab.MarkDirty();
		OnStructureChanged?.Invoke();
	}

	// ==================== Selection ====================

	private void OnTreeSelectionChanged()
	{
		if (mCurrentTab == null)
			return;

		mCurrentTab.SelectedEntities.Clear();

		let selectedItem = mTreeView.SelectedItem;
		if (selectedItem != null && mItemToEntity.TryGetValue(selectedItem, let entity))
			mCurrentTab.SelectedEntities.Add(entity);

		OnSelectionChanged?.Invoke(mCurrentTab.SelectedEntities);
	}

	/// Selects an entity in the tree by EntityId, or clears selection if Invalid.
	public void SelectEntity(EntityId entity)
	{
		if (!entity.IsValid)
		{
			mTreeView.SelectedItem = null;
			return;
		}

		for (let (item, eid) in mItemToEntity)
		{
			if (eid == entity)
			{
				mTreeView.SelectedItem = item;
				return;
			}
		}
	}

	/// Gets the currently selected entity, or EntityId.Invalid if none.
	public EntityId GetSelectedEntity()
	{
		let selectedItem = mTreeView.SelectedItem;
		if (selectedItem != null && mItemToEntity.TryGetValue(selectedItem, let entity))
			return entity;
		return .Invalid;
	}

	// ==================== Add Menu ====================

	private void ShowAddMenu(Button btn)
	{
		if (mAddMenu.Context == null)
			mAddMenu.OnAttachedToContext(btn.Context);

		let bounds = btn.ArrangedBounds;
		mAddMenu.Show(btn, .(bounds.X, bounds.Bottom));
	}
}
