using Sedulous.RHI;
using Sedulous.AppFramework;
using Sedulous.Framework.Core;
using Sedulous.Framework.Scenes;
using Sedulous.Framework.Render;
using Sedulous.Render;
using Tools.Common;
using System.Collections;
using Sedulous.GUI;
using System;
using System.IO;
using Sedulous.Mathematics;
using Sedulous.Shell;
using Sedulous.Framework.Animation;
namespace SceneEditor;

/// Scene Editor Application
class SceneEditorApp : Application
{
	// Framework
	private Context mContext ~ delete _;
	private SceneSubsystem mSceneSubsystem;
	private RenderSubsystem mRenderSubsystem;

	// Render system (NOT owned by RenderSubsystem — we manage it ourselves)
	private RenderSystem mRenderSystem;
	private RenderView mView;

	// Render features
	private DepthPrepassFeature mDepthFeature;
	private GPUSkinningFeature mSkinningFeature;
	private ForwardOpaqueFeature mForwardFeature;
	private SkyFeature mSkyFeature;
	private OverlayRenderFeature mOverlayFeature;
	private ViewportOutputFeature mOutputFeature;

	// Gizmo
	private TranslateGizmo mGizmo ~ delete _;

	// Tabs
	private List<SceneTab> mTabs ~ DeleteContainerAndItems!(_);
	private int32 mActiveTabIndex = -1;

	// Camera interaction state
	private bool mIsDragging = false;
	private bool mIsFlying = false;
	private bool mIsPanning = false;
	private float mLastMouseX;
	private float mLastMouseY;

	// Gizmo drag state
	private Vector3 mGizmoDragStartPos;

	// UI panels
	private DockPanel mRootPanel;     // root element (we own this — GUIContext only references it)
	private SplitPanel mOuterSplit;   // left (hierarchy) | right (center+inspector)
	private SplitPanel mInnerSplit;   // center (viewport+tabs) | right (inspector)
	private HierarchyPanel mHierarchyPanel ~ delete _;
	private InspectorPanel mInspectorPanel ~ delete _;
	private Grid mViewportPanel;
	private TabControl mTabControl;
	private Grid mViewportContainer;
	private TextBlock mDropIndicator;

	/// Gets the currently active tab, or null if no tabs exist.
	private SceneTab ActiveTab => mActiveTabIndex >= 0 && mActiveTabIndex < (int32)mTabs.Count ? mTabs[mActiveTabIndex] : null;

	public this() : base(.()
		{
			Title = "Scene Editor",
			Width = 1400,
			Height = 800,
			ClearColor = .(0.12f, 0.12f, 0.15f, 1.0f)
		})
	{
		mTabs = new List<SceneTab>();
	}

	// ==================== Initialization ====================

	protected override bool OnInitialize()
	{
		Sedulous.Imaging.SDL.SDLImageLoader.Initialize();

		// Initialize render system
		let shaderPaths = scope StringView[](scope $"{AssetDirectory}/Render/Shaders");
		mRenderSystem = new RenderSystem();
		if (mRenderSystem.Initialize(Device, shaderPaths, .RGBA8Unorm, .Depth24PlusStencil8) case .Err)
		{
			Console.WriteLine("ERROR: Failed to initialize RenderSystem");
			return false;
		}

		mView = new RenderView();
		mView.FieldOfView = Math.PI_f / 4.0f;
		mView.NearPlane = 0.1f;
		mView.FarPlane = 1000.0f;
		mView.PostProcess.EnableTAA = false;
		mView.PostProcess.EnableBloom = false;
		mView.PostProcess.EnableSSAO = false;

		RegisterFeatures();

		// Initialize Framework Context
		mContext = new Context();

		mSceneSubsystem = new SceneSubsystem();
		mContext.RegisterSubsystem(mSceneSubsystem);

		// RenderSubsystem does NOT own the RenderSystem — we manage its lifetime
		mRenderSubsystem = new RenderSubsystem(mRenderSystem, false);
		mContext.RegisterSubsystem(mRenderSubsystem);

		mContext.Startup();

		return true;
	}

	private void RegisterFeatures()
	{
		mSkinningFeature = new GPUSkinningFeature();
		mRenderSystem.RegisterFeature(mSkinningFeature);

		mDepthFeature = new DepthPrepassFeature();
		mRenderSystem.RegisterFeature(mDepthFeature);

		mForwardFeature = new ForwardOpaqueFeature();
		mRenderSystem.RegisterFeature(mForwardFeature);

		mSkyFeature = new SkyFeature();
		mRenderSystem.RegisterFeature(mSkyFeature);

		mOverlayFeature = new OverlayRenderFeature();
		mRenderSystem.RegisterFeature(mOverlayFeature);

		mOutputFeature = new ViewportOutputFeature();
		mRenderSystem.RegisterFeature(mOutputFeature);

		mGizmo = new TranslateGizmo();
		mGizmo.Size = 1.0f;
	}

	// ==================== UI Setup ====================

	protected override void OnUISetup(GUIContext context)
	{
		// Root layout: DockPanel with menu bar at top, split panels below
		mRootPanel = new DockPanel();

		// Menu bar at top (spans full width)
		let menuBar = CreateMenuBar();
		DockPanelProperties.SetDock(menuBar, .Top);
		mRootPanel.AddChild(menuBar);

		// Outer split: hierarchy | (viewport + inspector)
		mOuterSplit = new SplitPanel();
		mOuterSplit.Orientation = .Horizontal;
		mOuterSplit.SplitRatio = 0.18f;
		mOuterSplit.MinFirstSize = 150;
		mOuterSplit.MinSecondSize = 400;
		mOuterSplit.SplitterSize = 6;
		mRootPanel.AddChild(mOuterSplit);

		// Left: Hierarchy panel
		mHierarchyPanel = new HierarchyPanel();
		mHierarchyPanel.OnSelectionChanged = new => OnHierarchySelectionChanged;
		mHierarchyPanel.OnStructureChanged = new => OnHierarchyStructureChanged;
		mOuterSplit.AddChild(mHierarchyPanel.Root);

		// Inner split: viewport+tabs | inspector
		mInnerSplit = new SplitPanel();
		mInnerSplit.Orientation = .Horizontal;
		mInnerSplit.SplitRatio = 0.75f;
		mInnerSplit.MinFirstSize = 300;
		mInnerSplit.MinSecondSize = 200;
		mInnerSplit.SplitterSize = 6;
		mOuterSplit.AddChild(mInnerSplit);

		// Center: Grid with tabs + viewport
		mViewportPanel = new Grid();
		mViewportPanel.RowDefinitions.Add(new .() { Height = .Auto });  // tab strip
		mViewportPanel.RowDefinitions.Add(new .() { Height = .Star });  // viewport content
		mViewportPanel.ColumnDefinitions.Add(new .() { Width = .Star });
		mInnerSplit.AddChild(mViewportPanel);

		// Tab control
		mTabControl = new TabControl();
		mTabControl.TabStripPlacement = .Top;
		mTabControl.Height = 30;
		mTabControl.Visibility = .Collapsed;
		GridProperties.SetRow(mTabControl, 0);
		mTabControl.SelectionChanged.Subscribe(new (tc) =>
			{
				if (tc.SelectedIndex >= 0 && tc.SelectedIndex != mActiveTabIndex)
					SwitchToTab((int32)tc.SelectedIndex);
			});
		mViewportPanel.AddChild(mTabControl);

		// Container for per-tab content panels
		mViewportContainer = new Grid();
		mViewportContainer.RowDefinitions.Add(new .() { Height = .Star });
		mViewportContainer.ColumnDefinitions.Add(new .() { Width = .Star });
		GridProperties.SetRow(mViewportContainer, 1);
		mViewportPanel.AddChild(mViewportContainer);

		// Drop indicator / empty state
		mDropIndicator = new TextBlock("File > New Scene\nto get started");
		mDropIndicator.FontSize = 18;
		mDropIndicator.Foreground = Color(120, 120, 140, 255);
		mDropIndicator.TextWrapping = .Wrap;
		mDropIndicator.TextAlignment = .Center;
		mDropIndicator.HorizontalAlignment = .Center;
		mDropIndicator.VerticalAlignment = .Center;
		mViewportContainer.AddChild(mDropIndicator);

		// Right: Inspector panel
		mInspectorPanel = new InspectorPanel();
		mInspectorPanel.OnPropertyChanged = new => OnInspectorPropertyChanged;
		mInnerSplit.AddChild(mInspectorPanel.Root);

		context.RootElement = mRootPanel;
		UpdateEmptyState();
	}

	private Menu CreateMenuBar()
	{
		let menuBar = new Menu();
		menuBar.Padding = .(4, 2, 4, 2);

		// File menu
		let fileMenu = menuBar.AddItem("&File");

		let newItem = fileMenu.AddDropdownItem("&New Scene");
		newItem.ShortcutText = "Ctrl+N";
		newItem.Click.Subscribe(new (item) => { NewScene(); });

		let openItem = fileMenu.AddDropdownItem("&Open...");
		openItem.ShortcutText = "Ctrl+O";
		openItem.Click.Subscribe(new (item) => { ShowOpenDialog(); });

		fileMenu.AddDropdownSeparator();

		let saveItem = fileMenu.AddDropdownItem("&Save");
		saveItem.ShortcutText = "Ctrl+S";
		saveItem.Click.Subscribe(new (item) => { SaveScene(); });

		let saveAsItem = fileMenu.AddDropdownItem("Save &As...");
		saveAsItem.ShortcutText = "Ctrl+Shift+S";
		saveAsItem.Click.Subscribe(new (item) => { SaveSceneAs(); });

		fileMenu.AddDropdownSeparator();

		let closeItem = fileMenu.AddDropdownItem("&Close Tab");
		closeItem.Click.Subscribe(new (item) =>
			{
				if (mActiveTabIndex >= 0)
					CloseTab(mActiveTabIndex, true);
			});

		fileMenu.AddDropdownSeparator();

		let exitItem = fileMenu.AddDropdownItem("E&xit");
		exitItem.ShortcutText = "Alt+F4";
		exitItem.Click.Subscribe(new (item) => { Exit(); });

		return menuBar;
	}

	// ==================== Scene / Tab Management ====================

	private static StringView[?] sSceneFilter = .("Scene Files|scene");

	/// Registers all known component types on a SceneResource for serialization.
	private void RegisterComponentTypes(SceneResource resource)
	{
		resource.RegisterComponentType<LightComponent>();
		resource.RegisterComponentType<CameraComponent>();
		resource.RegisterComponentType<MeshRendererComponent>();
		resource.RegisterComponentType<SkinnedMeshRendererComponent>();
		resource.RegisterComponentType<SkeletalAnimationComponent>();
		resource.RegisterComponentType<SpriteComponent>();
		resource.RegisterComponentType<ParticleEmitterComponent>();
	}

	private void NewScene()
	{
		// Generate a unique name
		let name = scope String();
		name.AppendF("Scene {}", mTabs.Count + 1);

		let tab = new SceneTab(name);

		// Create scene via SceneSubsystem (fires ISceneAware → RenderSubsystem creates RenderWorld)
		tab.Scene = mSceneSubsystem.CreateScene(name);

		// Add a default directional light entity with LightComponent
		let lightEntity = tab.Scene.CreateEntity();
		tab.Scene.SetName(lightEntity, "Directional Light");
		tab.Scene.SetPosition(lightEntity, .(0, 10, 0));
		tab.Scene.SetRotation(lightEntity, Quaternion.CreateFromYawPitchRoll(0.5f, -1.0f, 0));

		var light = LightComponent.Default;
		light.Type = .Directional;
		light.Intensity = 2.5f;
		light.CastsShadows = true;
		tab.Scene.SetComponent<LightComponent>(lightEntity, light);

		// Set up default environment on the RenderWorld
		let world = mRenderSubsystem.GetWorld(tab.Scene);
		if (world != null)
		{
			world.AmbientColor = .(0.15f, 0.15f, 0.2f);
			world.AmbientIntensity = 0.5f;
			world.Exposure = 1.0f;
		}

		// Add tab to list and UI
		tab.MarkDirty();
		mTabs.Add(tab);
		AddTabToUI(tab);
		SwitchToTab((int32)mTabs.Count - 1);
	}

	/// Shows a native Open File dialog for .scene files.
	private void ShowOpenDialog()
	{
		Shell.Dialogs.ShowOpenFileDialog(new (paths) =>
			{
				for (let path in paths)
					OpenScene(path);
			}, sSceneFilter, default, false, Window);
	}

	/// Opens a scene from a file path.
	private void OpenScene(StringView path)
	{
		// Check if already open
		for (let tab in mTabs)
		{
			if (tab.FilePath != null && StringView(tab.FilePath) == path)
			{
				SwitchToTab((int32)@tab.Index);
				return;
			}
		}

		let resource = new SceneResource();
		RegisterComponentTypes(resource);

		if (resource.Load(path) case .Err)
		{
			Console.WriteLine(scope $"ERROR: Failed to load scene from '{path}'");
			delete resource;
			return;
		}

		let resourceId = resource.Id;
		let scene = resource.TakeScene();
		delete resource;

		// Register scene with SceneSubsystem (fires ISceneAware → RenderSubsystem creates RenderWorld)
		mSceneSubsystem.AddScene(scene);

		// Create tab
		let name = Path.GetFileNameWithoutExtension(path, .. scope .());
		let tab = new SceneTab(name);
		tab.ResourceId = resourceId;
		tab.Scene = scene;
		tab.SetFilePath(path);

		mTabs.Add(tab);
		AddTabToUI(tab);
		SwitchToTab((int32)mTabs.Count - 1);
	}

	/// Saves the active scene. If it has no file path, falls through to SaveAs.
	private void SaveScene()
	{
		let tab = ActiveTab;
		if (tab == null)
			return;

		if (tab.FilePath != null)
			SaveSceneToFile(tab, tab.FilePath);
		else
			SaveSceneAs();
	}

	/// Shows a native Save File dialog, then saves.
	/// If the scene already has a file path (re-saving to new location), assigns a new resource ID.
	private void SaveSceneAs()
	{
		let tab = ActiveTab;
		if (tab == null)
			return;

		Shell.Dialogs.ShowSaveFileDialog(new (paths) =>
			{
				if (paths.Length > 0 && paths[0].Length > 0)
				{
					let savePath = scope String(paths[0]);

					// Ensure .scene extension
					if (!savePath.EndsWith(".scene", .OrdinalIgnoreCase))
						savePath.Append(".scene");

					// New resource ID if saving an existing scene to a different location
					if (tab.FilePath != null)
						tab.ResourceId = Guid.Create();

					SaveSceneToFile(tab, savePath);
				}
			}, sSceneFilter, default, Window);
	}

	/// Writes the scene to disk and updates tab state.
	private void SaveSceneToFile(SceneTab tab, StringView path)
	{
		let resource = new SceneResource(tab.Scene, false);
		resource.Id = tab.ResourceId;
		RegisterComponentTypes(resource);

		if (resource.SaveToFile(path) case .Err)
		{
			Console.WriteLine(scope $"ERROR: Failed to save scene to '{path}'");
			delete resource;
			return;
		}

		delete resource;

		tab.SetFilePath(path);
		tab.ClearDirty();

		// Update tab name and title
		let name = Path.GetFileNameWithoutExtension(path, .. scope .());
		if (tab.Name != null)
			tab.Name.Set(name);

		// Find tab index and update title in TabControl
		let tabIndex = (int32)mTabs.IndexOf(tab);
		UpdateTabTitle(tabIndex);

		Console.WriteLine(scope $"Scene saved to '{path}'");
	}

	/// Handles file drop events (opens .scene files).
	protected override void OnFileDrop(StringView path)
	{
		let ext = Path.GetExtension(path, .. scope .());
		if (ext.Equals(".scene", .OrdinalIgnoreCase))
			OpenScene(path);
	}

	private void AddTabToUI(SceneTab tab)
	{
		if (mTabControl == null || mViewportContainer == null)
			return;

		let title = GetTabTitle(tab, .. scope .());
		let tabItem = mTabControl.AddTab(title);
		tabItem.IsCloseable = true;
		tabItem.CloseRequested.Subscribe(new (item) =>
			{
				let index = (int32)item.Index;
				if (index >= 0 && index < (int32)mTabs.Count)
					CloseTab(index, false);
			});

		// Create per-tab content panel
		tab.ContentPanel = new Grid();
		tab.ContentPanel.RowDefinitions.Add(new .() { Height = .Star });
		tab.ContentPanel.ColumnDefinitions.Add(new .() { Width = .Star });
		tab.ContentPanel.Visibility = .Collapsed;
		mViewportContainer.AddChild(tab.ContentPanel);

		// Create per-tab viewport
		tab.Viewport = new ViewportControl();
		tab.Viewport.Initialize(Device, mDrawingRenderer);
		tab.Viewport.Background = Color(40, 40, 50, 255);
		tab.Viewport.HorizontalAlignment = .Stretch;
		tab.Viewport.VerticalAlignment = .Stretch;
		GridProperties.SetRow(tab.Viewport, 0);
		tab.ContentPanel.AddChild(tab.Viewport);

		UpdateEmptyState();
	}

	private void SwitchToTab(int32 index)
	{
		if (index < 0 || index >= (int32)mTabs.Count)
			return;

		Device.WaitIdle();

		// Hide current tab
		let oldTab = ActiveTab;
		if (oldTab != null && oldTab.ContentPanel != null)
			oldTab.ContentPanel.Visibility = .Collapsed;

		mActiveTabIndex = index;
		let tab = mTabs[index];

		// Switch render world
		let world = mRenderSubsystem.GetWorld(tab.Scene);
		mRenderSystem.SetActiveWorld(world);

		// Show new tab
		if (tab.ContentPanel != null)
			tab.ContentPanel.Visibility = .Visible;

		if (mTabControl != null)
			mTabControl.SelectedIndex = index;

		// Refresh hierarchy and inspector for the new tab
		mHierarchyPanel.SetTab(tab);
		mInspectorPanel.RefreshForSelection(tab);
	}

	private void CloseTab(int32 index, bool removeFromTabControl)
	{
		if (index < 0 || index >= (int32)mTabs.Count)
			return;

		Device.WaitIdle();

		let tab = mTabs[index];

		// Remove per-tab UI from container
		if (tab.ContentPanel != null && mViewportContainer != null)
			mViewportContainer.RemoveChild(tab.ContentPanel, false);

		// Unload scene from SceneSubsystem
		if (tab.Scene != null)
			mSceneSubsystem.UnloadScene(tab.Scene);

		tab.DestroyUI();
		delete tab;
		mTabs.RemoveAt(index);

		if (removeFromTabControl)
			mTabControl.RemoveTabAt(index);

		// Adjust active index
		if (mTabs.Count == 0)
		{
			mActiveTabIndex = -1;
			mRenderSystem.SetActiveWorld(null);
			mHierarchyPanel.Clear();
			mInspectorPanel.Clear();
		}
		else if (mActiveTabIndex >= (int32)mTabs.Count)
		{
			mActiveTabIndex = (int32)mTabs.Count - 1;
			SwitchToTab(mActiveTabIndex);
		}
		else if (mActiveTabIndex == index)
		{
			SwitchToTab(mActiveTabIndex);
		}

		UpdateEmptyState();
	}

	private void UpdateEmptyState()
	{
		let hasScenes = mTabs.Count > 0;

		if (mDropIndicator != null)
			mDropIndicator.Visibility = hasScenes ? .Collapsed : .Visible;

		if (mTabControl != null)
			mTabControl.Visibility = hasScenes ? .Visible : .Collapsed;
	}

	/// Builds a tab title string with dirty indicator.
	private void GetTabTitle(SceneTab tab, String outTitle)
	{
		if (tab.IsDirty)
			outTitle.Append("*");
		outTitle.Append(tab.Name);
	}

	/// Updates the TabControl title for a specific tab index.
	private void UpdateTabTitle(int32 index)
	{
		if (mTabControl == null || index < 0 || index >= (int32)mTabs.Count)
			return;

		let tab = mTabs[index];
		let title = GetTabTitle(tab, .. scope .());
		let tabItem = mTabControl.GetTab(index);
		if (tabItem != null)
			tabItem.Header = new TextBlock(title);
	}

	// ==================== Hierarchy Callbacks ====================

	private void OnHierarchySelectionChanged(List<EntityId> entities)
	{
		let tab = ActiveTab;
		if (tab != null)
			mInspectorPanel.RefreshForSelection(tab);
		else
			mInspectorPanel.Clear();
	}

	private void OnHierarchyStructureChanged()
	{
		let tab = ActiveTab;
		if (tab == null)
			return;

		tab.MarkDirty();
		let tabIndex = (int32)mTabs.IndexOf(tab);
		UpdateTabTitle(tabIndex);
	}

	private void OnInspectorPropertyChanged()
	{
		let tab = ActiveTab;
		if (tab == null)
			return;

		let tabIndex = (int32)mTabs.IndexOf(tab);
		UpdateTabTitle(tabIndex);

		// Rebuild hierarchy in case entity name changed
		mHierarchyPanel.RebuildHierarchy();
	}

	// ==================== Keyboard Shortcuts ====================

	protected override void OnKeyDown(ShellKeyCode key)
	{
		let keyboard = Shell.InputManager.Keyboard;
		bool ctrlHeld = keyboard.IsKeyDown(.LeftCtrl) || keyboard.IsKeyDown(.RightCtrl);
		bool shiftHeld = keyboard.IsKeyDown(.LeftShift) || keyboard.IsKeyDown(.RightShift);

		switch (key)
		{
		case .Delete:
			mHierarchyPanel.DeleteSelectedEntity();
		case .F2:
			mHierarchyPanel.BeginRename();

		case .F:
			if (!ctrlHeld) FocusOnSelected();
		case .N:
			if (ctrlHeld) NewScene();
		case .O:
			if (ctrlHeld) ShowOpenDialog();
		case .S:
			if (ctrlHeld && shiftHeld)
				SaveSceneAs();
			else if (ctrlHeld)
				SaveScene();

		default:
		}
	}

	// ==================== Focus ====================

	private void FocusOnSelected()
	{
		let tab = ActiveTab;
		if (tab == null || tab.SelectedEntities.Count == 0)
			return;

		let entity = tab.SelectedEntities[0];
		let pos = tab.Scene.GetTransform(entity).Position;
		tab.Camera.FocusOn(pos);
	}

	// ==================== Update ====================

	protected override void OnUpdate(float deltaTime)
	{
		// Update Framework Context (runs scene subsystem updates)
		mContext.BeginFrame(deltaTime);
		mContext.Update(deltaTime);
		mContext.PostUpdate(deltaTime);
		mContext.EndFrame();

		let tab = ActiveTab;
		if (tab == null || tab.Viewport == null)
			return;

		// Handle camera + gizmo + picking input
		HandleViewportInput(tab, deltaTime);
	}

	private void HandleViewportInput(SceneTab tab, float deltaTime)
	{
		let mouse = Shell.InputManager.Mouse;
		let keyboard = Shell.InputManager.Keyboard;
		let viewport = tab.Viewport;

		let uiScale = mGUIContext?.ScaleFactor ?? 1.0f;
		float scaledMouseX = mouse.X / uiScale;
		float scaledMouseY = mouse.Y / uiScale;

		let viewportBounds = viewport.ArrangedBounds;
		bool mouseInViewport = scaledMouseX >= viewportBounds.X && scaledMouseX < viewportBounds.Right &&
			scaledMouseY >= viewportBounds.Y && scaledMouseY < viewportBounds.Bottom;

		let hitElement = mGUIContext?.HitTest(mouse.X, mouse.Y);
		bool uiCaptured = hitElement != null && hitElement != viewport && hitElement != mOuterSplit;

		bool ctrlHeld = keyboard.IsKeyDown(.LeftCtrl) || keyboard.IsKeyDown(.RightCtrl);

		// === Pick ray (used by gizmo and entity picking) ===
		float localMouseX = scaledMouseX - viewportBounds.X;
		float localMouseY = scaledMouseY - viewportBounds.Y;
		uint32 vpW = (uint32)viewport.RenderWidth;
		uint32 vpH = (uint32)viewport.RenderHeight;

		// Projection without Vulkan Y-flip for picking
		float aspectRatio = vpW > 0 && vpH > 0 ? (float)vpW / (float)vpH : 1.0f;
		let projMatrix = Matrix.CreatePerspectiveFieldOfView(
			mView.FieldOfView, aspectRatio, mView.NearPlane, mView.FarPlane);
		let pickRay = TranslateGizmo.CreatePickRay(
			localMouseX, localMouseY, vpW, vpH,
			tab.Camera.ViewMatrix, projMatrix);

		// === Gizmo interaction ===
		bool hasSelection = tab.SelectedEntities.Count > 0;

		if (hasSelection && !mGizmo.IsDragging)
		{
			// Position gizmo at selected entity
			let entity = tab.SelectedEntities[0];
			mGizmo.Position = tab.Scene.GetTransform(entity).Position;
			mGizmo.UpdateHover(pickRay, mGizmo.Size * 0.15f);
		}

		// Begin gizmo drag (LMB on hovered axis, without Ctrl)
		if (mouse.IsButtonPressed(.Left) && mouseInViewport && !uiCaptured && !ctrlHeld
			&& hasSelection && mGizmo.HoveredAxis != .None)
		{
			mGizmo.BeginDrag(pickRay);
			mIsDragging = false;  // Prevent camera orbit during gizmo drag
			mGizmoDragStartPos = tab.Scene.GetTransform(tab.SelectedEntities[0]).Position;
		}

		// Update gizmo drag
		if (mGizmo.IsDragging)
		{
			let delta = mGizmo.UpdateDrag(pickRay);
			let newPos = mGizmoDragStartPos + delta;
			let entity = tab.SelectedEntities[0];
			tab.Scene.SetPosition(entity, newPos);
			mGizmo.Position = newPos;
			tab.MarkDirty();

			// Live-update inspector
			mInspectorPanel.RefreshForSelection(tab);
		}

		// End gizmo drag
		if (mouse.IsButtonReleased(.Left) && mGizmo.IsDragging)
		{
			mGizmo.EndDrag();
			let tabIndex = (int32)mTabs.IndexOf(tab);
			UpdateTabTitle(tabIndex);
		}

		// === Entity picking (LMB click without Ctrl, not on gizmo) ===
		if (mouse.IsButtonPressed(.Left) && mouseInViewport && !uiCaptured && !ctrlHeld
			&& !mGizmo.IsDragging && mGizmo.HoveredAxis == .None)
		{
			let pickedEntity = PickEntity(tab, pickRay);
			tab.SelectedEntities.Clear();
			if (pickedEntity.IsValid)
				tab.SelectedEntities.Add(pickedEntity);

			mHierarchyPanel.SelectEntity(pickedEntity);
			mInspectorPanel.RefreshForSelection(tab);
		}

		// === Camera controls ===

		// Ctrl+LMB = orbit rotate
		if (mouse.IsButtonPressed(.Left) && mouseInViewport && !uiCaptured && ctrlHeld)
		{
			mIsDragging = true;
			mLastMouseX = mouse.X;
			mLastMouseY = mouse.Y;
		}
		if (mouse.IsButtonReleased(.Left))
			mIsDragging = false;

		// RMB = fly mode
		if (mouse.IsButtonPressed(.Right) && mouseInViewport && !uiCaptured)
		{
			mIsFlying = true;
			mLastMouseX = mouse.X;
			mLastMouseY = mouse.Y;
		}
		if (mouse.IsButtonReleased(.Right))
			mIsFlying = false;

		// MMB = pan
		if (mouse.IsButtonPressed(.Middle) && mouseInViewport && !uiCaptured)
		{
			mIsPanning = true;
			mLastMouseX = mouse.X;
			mLastMouseY = mouse.Y;
		}
		if (mouse.IsButtonReleased(.Middle))
			mIsPanning = false;

		// Orbit rotate
		if (mIsDragging && !mIsFlying && !mGizmo.IsDragging)
		{
			float deltaX = mouse.X - mLastMouseX;
			tab.Camera.Rotate(-deltaX * 0.01f, 0);
			mLastMouseX = mouse.X;
			mLastMouseY = mouse.Y;
		}

		// Fly mode
		if (mIsFlying)
		{
			float deltaX = mouse.X - mLastMouseX;
			float deltaY = mouse.Y - mLastMouseY;
			tab.Camera.Rotate(-deltaX * 0.01f, -deltaY * 0.01f);
			mLastMouseX = mouse.X;
			mLastMouseY = mouse.Y;

			if (viewport.IsFocused || mouseInViewport)
			{
				float moveSpeed = tab.Camera.Distance * 2.0f * deltaTime;
				if (keyboard.IsKeyDown(.LeftShift) || keyboard.IsKeyDown(.RightShift))
					moveSpeed *= 3.0f;

				float forward = 0, right = 0, up = 0;
				if (keyboard.IsKeyDown(.W)) forward += 1;
				if (keyboard.IsKeyDown(.S)) forward -= 1;
				if (keyboard.IsKeyDown(.D)) right += 1;
				if (keyboard.IsKeyDown(.A)) right -= 1;
				if (keyboard.IsKeyDown(.E) || keyboard.IsKeyDown(.Space)) up += 1;
				if (keyboard.IsKeyDown(.Q) || keyboard.IsKeyDown(.LeftCtrl)) up -= 1;

				if (forward != 0 || right != 0 || up != 0)
					tab.Camera.Move(forward, right, up, moveSpeed);
			}
		}

		// Pan
		if (mIsPanning)
		{
			float deltaX = mouse.X - mLastMouseX;
			float deltaY = mouse.Y - mLastMouseY;
			tab.Camera.Pan(-deltaX, deltaY);
			mLastMouseX = mouse.X;
			mLastMouseY = mouse.Y;
		}

		// Scroll zoom
		if (mouse.ScrollY != 0 && mouseInViewport && !uiCaptured)
			tab.Camera.Zoom(mouse.ScrollY * tab.Camera.Distance * 0.1f);
	}

	// ==================== Entity Picking ====================

	/// Picks the closest entity under the pick ray using proxy spheres.
	private EntityId PickEntity(SceneTab tab, Ray pickRay)
	{
		let scene = tab.Scene;
		if (scene == null)
			return .Invalid;

		float closestDist = float.MaxValue;
		EntityId closestEntity = .Invalid;

		scene.ForEachEntity(scope [&](entity) =>
			{
				let transform = scene.GetTransform(entity);
				let pos = transform.Position;

				// Use a proxy sphere at the entity position for picking
				// Scale radius by entity scale for mesh entities
				float radius = 0.5f;

				// Ray-sphere intersection
				let oc = pickRay.Position - pos;
				let a = Vector3.Dot(pickRay.Direction, pickRay.Direction);
				let b = 2.0f * Vector3.Dot(oc, pickRay.Direction);
				let c = Vector3.Dot(oc, oc) - radius * radius;
				let discriminant = b * b - 4 * a * c;

				if (discriminant >= 0)
				{
					let t = (-b - Math.Sqrt(discriminant)) / (2.0f * a);
					if (t > 0 && t < closestDist)
					{
						closestDist = t;
						closestEntity = entity;
					}
				}
			});

		return closestEntity;
	}

	// ==================== Render ====================

	protected override bool OnRender(ICommandEncoder encoder, int32 frameIndex)
	{
		let tab = ActiveTab;
		let viewport = tab?.Viewport;

		if (viewport != null && viewport.IsReady)
		{
			let width = viewport.RenderWidth;
			let height = viewport.RenderHeight;

			if (tab != null)
			{
				// Update view from camera
				mView.Width = width;
				mView.Height = height;
				mView.CameraPosition = tab.Camera.Position;
				mView.CameraForward = tab.Camera.Forward;
				mView.CameraUp = .(0, 1, 0);
				mView.UpdateMatrices(Device.FlipProjectionRequired);

				// Set output target
				mOutputFeature.SetOutputTarget(viewport.ColorTexture, viewport.ColorTargetView,
					viewport.DepthTexture, viewport.DepthTargetView, width, height);

				// Render
				mRenderSystem.BeginFrame(TotalTime, DeltaTime);
				mRenderSystem.SetCamera(tab.Camera.Position, tab.Camera.Forward, .(0, 1, 0),
					mView.FieldOfView, mView.AspectRatio, mView.NearPlane, mView.FarPlane, width, height);

				// Draw grid at Y=0
				if (mOverlayFeature != null)
				{
					mOverlayFeature.AddGrid(.(0, 0, 0), 20.0f, 20, Color(80, 80, 100, 255), .DepthTest);

					// Draw selection highlight
					if (tab.SelectedEntities.Count > 0)
					{
						let entity = tab.SelectedEntities[0];
						let pos = tab.Scene.GetTransform(entity).Position;
						let halfSize = 0.5f;
						let selBounds = BoundingBox(
							pos - .(halfSize, halfSize, halfSize),
							pos + .(halfSize, halfSize, halfSize));
						mOverlayFeature.AddBox(selBounds, Color(255, 200, 50, 255), .Overlay);
					}

					// Draw gizmo
					if (tab.SelectedEntities.Count > 0)
						mGizmo.Draw(mOverlayFeature);
				}

				if (mRenderSystem.BuildRenderGraph(mView) case .Ok)
					mRenderSystem.Execute(encoder);

				mRenderSystem.EndFrame();
			}

			// Transition viewport texture for UI sampling
			encoder.TextureBarrier(viewport.ColorTexture, .ColorAttachment, .ShaderReadOnly);
		}

		// Render UI to swap chain
		let swapTextureView = SwapChain.CurrentTextureView;
		RenderPassColorAttachment[1] uiAttachments = .(.(swapTextureView)
			{
				LoadOp = .Clear,
				StoreOp = .Store,
				ClearValue = mConfig.ClearColor
			});
		RenderPassDescriptor uiPassDesc = .(uiAttachments);

		let uiPass = encoder.BeginRenderPass(&uiPassDesc);
		if (uiPass != null)
		{
			mDrawingRenderer.Render(uiPass, SwapChain.Width, SwapChain.Height, frameIndex);
			uiPass.End();
			delete uiPass;
		}

		return true;
	}

	// ==================== Cleanup ====================

	protected override void OnCleanup()
	{
		Device?.WaitIdle();

		// Close all tabs (unloads scenes from subsystem, destroys per-tab UI)
		while (mTabs.Count > 0)
			CloseTab(0, false);

		// Shutdown Framework Context (shuts down subsystems including RenderSubsystem)
		if (mContext != null)
			mContext.Shutdown();

		// Shutdown render system (after context since RenderSubsystem doesn't own it)
		mRenderSystem?.Shutdown();

		if (mView != null) { delete mView; mView = null; }
		if (mRenderSystem != null) { delete mRenderSystem; mRenderSystem = null; }

		// Delete root UI panel last — GUIContext only references it, doesn't own it
		delete mRootPanel;
	}
}
