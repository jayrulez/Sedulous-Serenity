namespace Sedulous.Editor.Scenes;

using System;
using System.Collections;
using Sedulous.Editor.Core;
using Sedulous.UI;
using Sedulous.Mathematics;

/// Document for editing scene assets.
class SceneAssetDocument : IAssetDocument
{
	private SceneAsset mAsset;
	private Guid mDocumentId;
	private CommandHistory mHistory = new .() ~ delete _;

	// Selection state
	private List<Guid> mSelectedEntities = new .() ~ delete _;

	// UI components
	private SceneHierarchyPanel mHierarchyPanel;
	private SceneEditorView mEditorView;
	private UIElement mContentRoot;

	// IAssetDocument implementation
	public IAsset Asset => mAsset;
	public Guid DocumentId => mDocumentId;
	public bool IsDirty => mAsset.IsDirty;
	public bool CanUndo => mHistory.CanUndo;
	public bool CanRedo => mHistory.CanRedo;

	/// Currently selected entities.
	public Span<Guid> SelectedEntities => mSelectedEntities;

	public this(SceneAsset asset)
	{
		mAsset = asset;
		mDocumentId = Guid.Create();
	}

	public void Dispose()
	{
		// Content root is owned by the UI system when attached
		// Don't delete mAsset - it's owned by the DocumentManager/AssetDatabase
	}

	public void GetTitle(String outTitle)
	{
		outTitle.Set(mAsset.Name);
		if (mAsset.IsDirty)
			outTitle.Append("*");
	}

	public UIElement CreateContent()
	{
		// Create split panel: hierarchy tree | viewport
		let splitPanel = new SplitPanel();
		splitPanel.Orientation = .Horizontal;
		splitPanel.SplitterPosition = 200;
		splitPanel.Width = .Fill;
		splitPanel.Height = .Fill;

		// Left: Scene hierarchy
		mHierarchyPanel = new SceneHierarchyPanel(this);
		mHierarchyPanel.Width = .Fill;
		mHierarchyPanel.Height = .Fill;
		splitPanel.Panel1 = mHierarchyPanel;

		// Right: Scene editor viewport
		mEditorView = new SceneEditorView(this);
		mEditorView.Width = .Fill;
		mEditorView.Height = .Fill;
		splitPanel.Panel2 = mEditorView;

		mContentRoot = splitPanel;
		return splitPanel;
	}

	/// Gets the scene editor view.
	public SceneEditorView EditorView => mEditorView;

	public void OnActivate()
	{
		// Refresh hierarchy when document becomes active
		mHierarchyPanel?.Refresh();
	}

	public void OnDeactivate()
	{
	}

	public bool OnClosing()
	{
		// Could prompt for save if dirty
		// For now, allow closing
		return true;
	}

	public Result<void> Save()
	{
		return mAsset.Save();
	}

	public Result<void> SaveAs(StringView path)
	{
		return mAsset.Save(path);
	}

	public void Undo()
	{
		mHistory.Undo();
		mHierarchyPanel?.Refresh();
	}

	public void Redo()
	{
		mHistory.Redo();
		mHierarchyPanel?.Refresh();
	}

	// ===== Selection =====

	/// Select an entity.
	public void Select(Guid entityId, bool addToSelection = false)
	{
		if (!addToSelection)
			mSelectedEntities.Clear();

		if (!mSelectedEntities.Contains(entityId))
			mSelectedEntities.Add(entityId);

		mHierarchyPanel?.RefreshSelection();
	}

	/// Clear selection.
	public void ClearSelection()
	{
		mSelectedEntities.Clear();
		mHierarchyPanel?.RefreshSelection();
	}

	/// Check if an entity is selected.
	public bool IsSelected(Guid entityId)
	{
		return mSelectedEntities.Contains(entityId);
	}

	// ===== Entity Operations =====

	/// Create a new entity.
	public Guid CreateEntity(StringView name, Guid parentId = default)
	{
		let entity = mAsset.AddEntity(name, parentId);
		mHierarchyPanel?.Refresh();
		return entity.EntityId;
	}

	/// Delete selected entities.
	public void DeleteSelected()
	{
		for (let entityId in mSelectedEntities)
			mAsset.RemoveEntity(entityId);

		mSelectedEntities.Clear();
		mHierarchyPanel?.Refresh();
	}

	/// Duplicate selected entities.
	public void DuplicateSelected()
	{
		let newSelection = scope List<Guid>();

		for (let entityId in mSelectedEntities)
		{
			if (let clone = mAsset.DuplicateEntity(entityId))
				newSelection.Add(clone.EntityId);
		}

		mSelectedEntities.Clear();
		for (let id in newSelection)
			mSelectedEntities.Add(id);

		mHierarchyPanel?.Refresh();
	}

	/// Get the scene asset.
	public SceneAsset SceneAsset => mAsset;

	/// Execute a command with undo support.
	public void ExecuteCommand(ICommand command)
	{
		mHistory.Execute(command);
	}
}
