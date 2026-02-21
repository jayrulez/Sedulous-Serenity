using Sedulous.RHI;
using Sedulous.AppFramework;
using Sedulous.Framework.Core;
using Sedulous.Framework.Scenes;
using Sedulous.Framework.Render;
using Sedulous.Framework.Animation;
using Sedulous.Render;
using Sedulous.Resources;
using Sedulous.Geometry.Resources;
using Tools.Common;
using System.Collections;
using Sedulous.GUI;
using System;
using System.IO;
using Sedulous.Mathematics;
using Sedulous.Shell;
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
	private enum GizmoMode { Translate, Rotate, Scale }
	private GizmoMode mGizmoMode = .Translate;
	private TranslateGizmo mGizmo ~ delete _;
	private RotateGizmo mRotateGizmo ~ delete _;
	private ScaleGizmo mScaleGizmo ~ delete _;

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
	private Transform mGizmoDragOldTransform;

	// Project / Resources
	private String mProjectDirectory ~ delete _;
	private List<ResourceRegistry> mRegistries = new .() ~ DeleteContainerAndItems!(_);

	// UI panels
	private DockPanel mRootPanel;     // root element (we own this — GUIContext only references it)
	private SplitPanel mOuterSplit;   // left (hierarchy) | right (center+inspector)
	private SplitPanel mInnerSplit;   // center (viewport+tabs) | right (inspector)
	private HierarchyPanel mHierarchyPanel ~ delete _;
	private InspectorPanel mInspectorPanel ~ delete _;
	private AssetBrowserPanel mAssetBrowserPanel ~ delete _;
	private Grid mViewportPanel;
	private TabControl mTabControl;
	private Grid mViewportContainer;
	private TextBlock mDropIndicator;

	// Status bar
	private StatusBar mStatusBar;
	private StatusBarItem mEntityCountItem;
	private StatusBarItem mSelectionItem;
	private StatusBarItem mGizmoModeItem;
	private StatusBarItem mDirtyItem;

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
		if (mRenderSystem.Initialize(Device, shaderPaths, null, .RGBA8Unorm, .Depth24PlusStencil8) case .Err)
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

		// Animation subsystem (registers skeleton/animation resource managers, adds AnimationSceneModule to scenes)
		let animSubsystem = new AnimationSubsystem();
		mContext.RegisterSubsystem(animSubsystem);

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
		mRotateGizmo = new RotateGizmo();
		mRotateGizmo.Size = 1.0f;
		mScaleGizmo = new ScaleGizmo();
		mScaleGizmo.Size = 1.0f;
	}

	// ==================== Project Directory ====================

	/// Shows a native folder dialog to select a project directory.
	private void ShowProjectDialog()
	{
		let defaultPath = scope String();
		if (mProjectDirectory != null)
			defaultPath.Set(mProjectDirectory);

		Shell.Dialogs.ShowFolderDialog(new (paths) =>
			{
				if (paths.Length > 0 && paths[0].Length > 0)
					SetProjectDirectory(paths[0]);
			}, defaultPath, Window);
	}

	/// Sets the project directory, loads registries, and refreshes the asset browser.
	private void SetProjectDirectory(StringView path)
	{
		// Store path
		if (mProjectDirectory != null)
			delete mProjectDirectory;
		mProjectDirectory = new String(path);

		// Unload previous registries
		for (let registry in mRegistries)
		{
			mContext.Resources.RemoveRegistry(registry);
			delete registry;
		}
		mRegistries.Clear();

		// Scan for registry.txt files and load them
		FindAndLoadRegistries(path);

		// Notify panels
		mAssetBrowserPanel?.SetProjectDirectory(path);
		mInspectorPanel?.SetProjectDirectory(path);

		Console.WriteLine(scope $"Project directory set: {path}");
		UpdateStatusBar();
	}

	/// Recursively finds and loads registry.txt files from a directory.
	private void FindAndLoadRegistries(StringView directory)
	{
		// Check for registry.txt in this directory
		let registryPath = scope String();
		Path.InternalCombine(registryPath, directory, "registry.txt");

		if (File.Exists(registryPath))
		{
			let registry = new ResourceRegistry();
			if (registry.LoadFromFile(registryPath) case .Ok)
			{
				mContext.Resources.AddRegistry(registry);
				mRegistries.Add(registry);
				Console.WriteLine(scope $"  Loaded registry: {registryPath} ({registry.Count} entries)");
			}
			else
			{
				Console.WriteLine(scope $"  WARNING: Failed to load registry: {registryPath}");
				delete registry;
			}
		}

		// Recurse into subdirectories
		for (let entry in Directory.EnumerateDirectories(directory))
		{
			let subDir = entry.GetFilePath(.. scope .());
			FindAndLoadRegistries(subDir);
		}
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

		// Status bar at bottom
		mStatusBar = new StatusBar();
		mStatusBar.Padding = .(6, 2, 6, 2);
		mEntityCountItem = mStatusBar.AddFixedItem("Entities: 0", 120);
		mSelectionItem = mStatusBar.AddFlexibleItem("");
		mGizmoModeItem = mStatusBar.AddFixedItem("Translate (W)", 120);
		mDirtyItem = mStatusBar.AddFixedItem("", 100);
		DockPanelProperties.SetDock(mStatusBar, .Bottom);
		mRootPanel.AddChild(mStatusBar);

		// Outer split: hierarchy | (viewport + inspector)
		mOuterSplit = new SplitPanel();
		mOuterSplit.Orientation = .Horizontal;
		mOuterSplit.SplitRatio = 0.18f;
		mOuterSplit.MinFirstSize = 150;
		mOuterSplit.MinSecondSize = 400;
		mOuterSplit.SplitterSize = 6;
		mRootPanel.AddChild(mOuterSplit);

		// Left: Hierarchy + Asset Browser in vertical split
		let leftSplit = new SplitPanel();
		leftSplit.Orientation = .Vertical;
		leftSplit.SplitRatio = 0.55f;
		leftSplit.MinFirstSize = 100;
		leftSplit.MinSecondSize = 100;
		leftSplit.SplitterSize = 6;

		mHierarchyPanel = new HierarchyPanel();
		mHierarchyPanel.OnSelectionChanged = new => OnHierarchySelectionChanged;
		mHierarchyPanel.OnStructureChanged = new => OnHierarchyStructureChanged;
		leftSplit.AddChild(mHierarchyPanel.Root);

		mAssetBrowserPanel = new AssetBrowserPanel();
		mAssetBrowserPanel.OnFileSelected = new => OnAssetSelected;
		leftSplit.AddChild(mAssetBrowserPanel.Root);

		mOuterSplit.AddChild(leftSplit);

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
		mInspectorPanel = new InspectorPanel(mRenderSubsystem, mRegistries, Shell.Dialogs, Window);
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

		let openProjectItem = fileMenu.AddDropdownItem("Open &Project...");
		openProjectItem.Click.Subscribe(new (item) => { ShowProjectDialog(); });

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

		// Edit menu
		let editMenu = menuBar.AddItem("&Edit");

		let undoItem = editMenu.AddDropdownItem("&Undo");
		undoItem.ShortcutText = "Ctrl+Z";
		undoItem.Click.Subscribe(new (item) => { UndoAction(); });

		let redoItem = editMenu.AddDropdownItem("&Redo");
		redoItem.ShortcutText = "Ctrl+Y";
		redoItem.Click.Subscribe(new (item) => { RedoAction(); });

		editMenu.AddDropdownSeparator();

		let dupItem = editMenu.AddDropdownItem("&Duplicate");
		dupItem.ShortcutText = "Ctrl+D";
		dupItem.Click.Subscribe(new (item) => { mHierarchyPanel.DuplicateSelected(); });

		let deleteItem = editMenu.AddDropdownItem("De&lete");
		deleteItem.ShortcutText = "Delete";
		deleteItem.Click.Subscribe(new (item) => { mHierarchyPanel.DeleteSelectedEntity(); });

		return menuBar;
	}

	// ==================== Scene / Tab Management ====================

	private static StringView[?] sSceneFilter = .("Scene Files|scene");

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

		// Default environment comes from RenderModuleSettings defaults,
		// applied by RenderSceneModule.OnSceneCreate during CreateScene above.

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

		if (resource.Load(path) case .Err)
		{
			Console.WriteLine(scope $"ERROR: Failed to load scene from '{path}'");
			delete resource;
			return;
		}

		let resourceId = resource.Id;
		let scene = resource.TakeScene();
		delete resource;

		// Register scene with SceneSubsystem (fires ISceneAware → RenderSubsystem creates RenderWorld).
		// Module settings were already populated during deserialization above.
		// Modules read from settings in OnSceneCreate when they are added here.
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
		UpdateStatusBar();
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

		// Switch active scene and render world
		mSceneSubsystem.SetActiveScene(tab.Scene);
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
		UpdateStatusBar();
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

	// ==================== Asset Browser Callbacks ====================

	private void OnAssetSelected(StringView path)
	{
		let filename = Path.GetFileName(path, .. scope .());
		mSelectionItem.Text = scope $"Asset: {filename}";
	}

	// ==================== Hierarchy Callbacks ====================

	private void OnHierarchySelectionChanged(List<EntityId> entities)
	{
		let tab = ActiveTab;
		if (tab != null)
			mInspectorPanel.RefreshForSelection(tab);
		else
			mInspectorPanel.Clear();
		UpdateStatusBar();
	}

	private void OnHierarchyStructureChanged()
	{
		let tab = ActiveTab;
		if (tab == null)
			return;

		tab.MarkDirty();
		let tabIndex = (int32)mTabs.IndexOf(tab);
		UpdateTabTitle(tabIndex);
		UpdateStatusBar();
	}

	private void OnInspectorPropertyChanged()
	{
		let tab = ActiveTab;
		if (tab == null)
			return;

		let tabIndex = (int32)mTabs.IndexOf(tab);
		UpdateTabTitle(tabIndex);
		UpdateStatusBar();

		// Update entity name in hierarchy (lightweight, no rebuild)
		if (tab.SelectedEntities.Count > 0)
			mHierarchyPanel.RefreshEntityName(tab.SelectedEntities[0]);
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

		case .Z:
			if (ctrlHeld) UndoAction();
		case .Y:
			if (ctrlHeld) RedoAction();
		case .D:
			if (ctrlHeld) mHierarchyPanel.DuplicateSelected();

		// Gizmo mode switching (only when not flying — W/S used for movement)
		case .W:
			if (!ctrlHeld && !mIsFlying) SetGizmoMode(.Translate);
		case .E:
			if (!ctrlHeld && !mIsFlying) SetGizmoMode(.Rotate);
		case .R:
			if (!ctrlHeld && !mIsFlying) SetGizmoMode(.Scale);

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
		var transform = tab.Scene.GetTransform(entity);
		let pos = transform.Position;
		tab.Camera.FocusOn(pos);
	}

	// ==================== Gizmo Mode ====================

	private void SetGizmoMode(GizmoMode mode)
	{
		mGizmoMode = mode;
		UpdateStatusBar();
	}

	// ==================== Status Bar ====================

	private void UpdateStatusBar()
	{
		let tab = ActiveTab;

		if (tab == null || tab.Scene == null)
		{
			mEntityCountItem.Text = "Entities: 0";
			mSelectionItem.Text = "";
			mDirtyItem.Text = "";
			return;
		}

		// Entity count
		int32 entityCount = 0;
		tab.Scene.ForEachEntity(scope [&](e) => { entityCount++; });
		mEntityCountItem.Text = scope $"Entities: {entityCount}";

		// Selection info
		if (tab.SelectedEntities.Count == 0)
			mSelectionItem.Text = "";
		else if (tab.SelectedEntities.Count == 1)
		{
			let name = tab.Scene.GetName(tab.SelectedEntities[0]);
			mSelectionItem.Text = scope $"Selected: {name}";
		}
		else
			mSelectionItem.Text = scope $"Selected: {tab.SelectedEntities.Count} entities";

		// Gizmo mode
		switch (mGizmoMode)
		{
		case .Translate: mGizmoModeItem.Text = "Translate (W)";
		case .Rotate: mGizmoModeItem.Text = "Rotate (E)";
		case .Scale: mGizmoModeItem.Text = "Scale (R)";
		}

		// Dirty indicator
		mDirtyItem.Text = tab.IsDirty ? "*Modified" : "";
	}

	// ==================== Undo/Redo ====================

	private void UndoAction()
	{
		let tab = ActiveTab;
		if (tab == null || !tab.History.CanUndo) return;
		tab.History.Undo();
		tab.MarkDirty();
		RefreshAfterUndoRedo(tab);
	}

	private void RedoAction()
	{
		let tab = ActiveTab;
		if (tab == null || !tab.History.CanRedo) return;
		tab.History.Redo();
		tab.MarkDirty();
		RefreshAfterUndoRedo(tab);
	}

	private void RefreshAfterUndoRedo(SceneTab tab)
	{
		// Clear selection since entity IDs may have changed
		tab.SelectedEntities.Clear();
		mHierarchyPanel.SelectEntity(.Invalid);
		mHierarchyPanel.RebuildHierarchy();
		mInspectorPanel.RefreshForSelection(tab);
		let tabIndex = (int32)mTabs.IndexOf(tab);
		UpdateTabTitle(tabIndex);
		UpdateStatusBar();
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
		bool anyGizmoDragging = mGizmo.IsDragging || mRotateGizmo.IsDragging || mScaleGizmo.IsDragging;
		GizmoAxis activeHoveredAxis = .None;

		if (hasSelection && !anyGizmoDragging)
		{
			// Position all gizmos at selected entity
			let entity = tab.SelectedEntities[0];
			if (tab.Scene.IsValid(entity))
			{
				let entityPos = tab.Scene.GetTransform(entity).Position;
				mGizmo.Position = entityPos;
				mRotateGizmo.Position = entityPos;
				mScaleGizmo.Position = entityPos;

				// Update hover on the active gizmo only
				switch (mGizmoMode)
				{
				case .Translate:
					mGizmo.UpdateHover(pickRay, mGizmo.Size * 0.15f);
					activeHoveredAxis = mGizmo.HoveredAxis;
				case .Rotate:
					mRotateGizmo.UpdateHover(pickRay, mRotateGizmo.Size * 0.15f);
					activeHoveredAxis = mRotateGizmo.HoveredAxis;
				case .Scale:
					mScaleGizmo.UpdateHover(pickRay, mScaleGizmo.Size * 0.15f);
					activeHoveredAxis = mScaleGizmo.HoveredAxis;
				}
			}
		}

		// Begin gizmo drag (LMB on hovered axis, without Ctrl)
		if (mouse.IsButtonPressed(.Left) && mouseInViewport && !uiCaptured && !ctrlHeld
			&& hasSelection && activeHoveredAxis != .None)
		{
			switch (mGizmoMode)
			{
			case .Translate: mGizmo.BeginDrag(pickRay);
			case .Rotate: mRotateGizmo.BeginDrag(pickRay);
			case .Scale: mScaleGizmo.BeginDrag(pickRay);
			}
			mIsDragging = false;  // Prevent camera orbit during gizmo drag
			mGizmoDragOldTransform = tab.Scene.GetTransform(tab.SelectedEntities[0]);
		}

		// Update gizmo drag
		anyGizmoDragging = mGizmo.IsDragging || mRotateGizmo.IsDragging || mScaleGizmo.IsDragging;
		if (anyGizmoDragging)
		{
			let entity = tab.SelectedEntities[0];

			switch (mGizmoMode)
			{
			case .Translate:
				let delta = mGizmo.UpdateDrag(pickRay);
				let newPos = mGizmoDragOldTransform.Position + delta;
				tab.Scene.SetPosition(entity, newPos);
				mGizmo.Position = newPos;
			case .Rotate:
				let deltaRot = mRotateGizmo.UpdateDrag(pickRay);
				let newRot = deltaRot * mGizmoDragOldTransform.Rotation;
				tab.Scene.SetRotation(entity, newRot);
			case .Scale:
				let scaleFactor = mScaleGizmo.UpdateDrag(pickRay);
				let newScale = mGizmoDragOldTransform.Scale * scaleFactor;
				tab.Scene.SetScale(entity, newScale);
			}

			tab.MarkDirty();
			mInspectorPanel.RefreshForSelection(tab);
		}

		// End gizmo drag
		if (mouse.IsButtonReleased(.Left) && anyGizmoDragging)
		{
			switch (mGizmoMode)
			{
			case .Translate: mGizmo.EndDrag();
			case .Rotate: mRotateGizmo.EndDrag();
			case .Scale: mScaleGizmo.EndDrag();
			}

			// Push undo command for the completed drag
			let entity = tab.SelectedEntities[0];
			let newTransform = tab.Scene.GetTransform(entity);
			let cmd = new SetTransformCommand(tab.Scene, entity, mGizmoDragOldTransform, newTransform);
			tab.History.Push(cmd);

			let tabIndex = (int32)mTabs.IndexOf(tab);
			UpdateTabTitle(tabIndex);
		}

		// === Entity picking (LMB click without Ctrl, not on gizmo) ===
		if (mouse.IsButtonPressed(.Left) && mouseInViewport && !uiCaptured && !ctrlHeld
			&& !anyGizmoDragging && activeHoveredAxis == .None)
		{
			let pickedEntity = PickEntity(tab, pickRay);
			tab.SelectedEntities.Clear();
			if (pickedEntity.IsValid)
				tab.SelectedEntities.Add(pickedEntity);

			mHierarchyPanel.SelectEntity(pickedEntity);
			mInspectorPanel.RefreshForSelection(tab);
			UpdateStatusBar();
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
		bool gizmoActive = mGizmo.IsDragging || mRotateGizmo.IsDragging || mScaleGizmo.IsDragging;
		if (mIsDragging && !mIsFlying && !gizmoActive)
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

					// Draw selection highlight (OBB using actual mesh bounds)
					if (tab.SelectedEntities.Count > 0 && tab.Scene.IsValid(tab.SelectedEntities[0]))
					{
						let entity = tab.SelectedEntities[0];
						let transform = tab.Scene.GetTransform(entity);
						let worldMatrix = transform.ToMatrix();

						// Get mesh local bounds, or default 1x1x1 for non-mesh entities
						BoundingBox localBounds = .(Vector3(-0.5f, -0.5f, -0.5f), Vector3(0.5f, 0.5f, 0.5f));
						if (let meshComp = tab.Scene.GetComponent<MeshRendererComponent>(entity))
						{
							if (meshComp.Mesh.IsValid)
								if (let resource = meshComp.Mesh.Resource)
									if (resource.Mesh != null)
										localBounds = resource.Mesh.GetBounds();
						}
						else if (let skinnedComp = tab.Scene.GetComponent<SkinnedMeshRendererComponent>(entity))
						{
							if (skinnedComp.Mesh.IsValid)
								if (let resource = skinnedComp.Mesh.Resource)
									if (resource.Mesh != null)
										localBounds = resource.Mesh.Bounds;
						}

						mOverlayFeature.AddTransformedBox(localBounds, worldMatrix, Color(255, 200, 50, 255), .Overlay);
					}

					// Draw active gizmo
					if (tab.SelectedEntities.Count > 0)
					{
						switch (mGizmoMode)
						{
						case .Translate: mGizmo.Draw(mOverlayFeature);
						case .Rotate: mRotateGizmo.Draw(mOverlayFeature);
						case .Scale: mScaleGizmo.Draw(mOverlayFeature);
						}
					}
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

		// Unregister resource registries before context shutdown
		for (let registry in mRegistries)
			mContext.Resources.RemoveRegistry(registry);

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
