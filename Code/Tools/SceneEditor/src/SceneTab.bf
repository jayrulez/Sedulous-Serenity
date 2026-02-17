namespace SceneEditor;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.Render;
using Sedulous.GUI;
using Sedulous.AppFramework;
using Sedulous.Framework.Scenes;
using Tools.Common;

/// Represents a single scene editor tab with its own scene, camera, and UI state.
class SceneTab
{
	// Identity
	public String Name ~ delete _;
	public String FilePath ~ delete _;  // null = unsaved
	public Guid ResourceId;  // Stable across saves; only changes on Save As to new location

	// Scene (owned by SceneSubsystem's SceneManager)
	public Scene Scene;

	// Per-tab camera (NOT a scene entity - drives RenderView directly)
	public OrbitCamera Camera ~ delete _;

	// Per-tab UI elements
	public Grid ContentPanel;
	public ViewportControl Viewport;

	// Selection state
	public List<EntityId> SelectedEntities = new .() ~ delete _;

	// Dirty tracking
	public bool IsDirty = false;

	public this(StringView name)
	{
		Name = new String(name);
		ResourceId = Guid.Create();
		Camera = new OrbitCamera();
		Camera.Distance = 15.0f;
		Camera.Pitch = 0.5f;
	}

	/// Marks the tab as dirty (has unsaved changes).
	public void MarkDirty()
	{
		IsDirty = true;
	}

	/// Clears the dirty flag (after saving).
	public void ClearDirty()
	{
		IsDirty = false;
	}

	/// Sets the file path for this tab.
	public void SetFilePath(StringView path)
	{
		if (FilePath != null)
			delete FilePath;
		FilePath = new String(path);
	}

	/// Destroys per-tab UI elements. Scene is managed by SceneSubsystem.
	public void DestroyUI()
	{
		if (ContentPanel != null)
		{
			if (ContentPanel.Context != null)
				ContentPanel.Context.MutationQueue.QueueDelete(ContentPanel);
			else
				delete ContentPanel;
			ContentPanel = null;
			Viewport = null;
		}
	}
}
