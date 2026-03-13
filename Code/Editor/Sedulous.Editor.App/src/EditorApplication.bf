namespace Sedulous.Editor.App;

using System;
using System.Collections;
using System.IO;
using Sedulous.Tools.AppFramework;
using Sedulous.Editor.Core;
using Sedulous.GUI;
using Sedulous.Core.Core;
using Sedulous.Core.Logging.Abstractions;
using Sedulous.Core.Mathematics;

/// Editor application configuration.
public struct EditorConfig
{
	public ApplicationConfig AppConfig = .()
	{
		Title = "Sedulous Editor",
		Width = 1600,
		Height = 900,
		Resizable = true
	};

	/// Directory to store editor settings (recent projects, preferences).
	public String SettingsDirectory = null;
}

/// Main editor application.
public class EditorApplication : Application
{
	private EditorConfig mEditorConfig;

	// Logging
	private ILogger mEditorLogger ~ delete _;

	// Settings
	private RecentProjectsManager mRecentProjects ~ delete _;
	private String mSettingsDirectory = new .() ~ delete _;

	// Core systems
	private AssetRegistry mAssetRegistry;
	private DocumentManager mDocumentManager;
	private EditorProject mProject;

	// Editor modules (registered by entry point)
	private List<IEditorModule> mModules = new .() ~ DeleteContainerAndItems!(_);

	// UI state
	private bool mShowingProjectManager = true;
	private ProjectManagerView mProjectManagerView;
	private NewProjectDialog mNewProjectDialog;
	private DockPanel mEditorRoot;         // Layout root: Menu + DockManager + StatusBar
	private DockManager mDockManager;
	private Menu mMenuBar;
	private StatusBar mStatusBar;
	private StatusBarItem mProjectStatusItem;
	private StatusBarItem mAssetCountStatusItem;
	private DockablePanel mProjectPanel;
	private DockablePanel mPropertiesPanel;
	private DockablePanel mConsolePanel;
	private DockablePanel mCenterPanel;
	private AssetBrowser mAssetBrowser;
	private DocumentTabStrip mDocumentTabs;
	private ScrollViewer mConsoleScroller;
	private StackPanel mConsoleLogStack;
	private MenuItem mRecentProjectsMenuItem;
	private List<String> mRecentMenuPaths = new .() ~ DeleteContainerAndItems!(_);

	// Pending actions (deferred to avoid modifying UI tree during event processing)
	private String mPendingProjectName ~ delete _;
	private String mPendingProjectFolder ~ delete _;
	private bool mPendingDialogHide = false;

	// Events
	private EventAccessor<delegate void(EditorProject)> mProjectOpened = new .() ~ delete _;
	private EventAccessor<delegate void()> mProjectClosed = new .() ~ delete _;

	/// Event fired when a project is opened.
	public EventAccessor<delegate void(EditorProject)> ProjectOpened => mProjectOpened;

	/// Event fired when a project is closed.
	public EventAccessor<delegate void()> ProjectClosed => mProjectClosed;

	/// Current project (may be null).
	public EditorProject Project => mProject;

	/// Asset registry.
	public AssetRegistry AssetRegistry => mAssetRegistry;

	/// Document manager.
	public DocumentManager DocumentManager => mDocumentManager;

	/// Editor logger (stores messages for console display).
	public ILogger Logger => mEditorLogger;

	/// Recent projects manager.
	public RecentProjectsManager RecentProjects => mRecentProjects;

	/// Registers an editor module.
	/// Call this before Run() to add plugin functionality.
	public void RegisterModule(IEditorModule module)
	{
		mModules.Add(module);
	}

	public this() : this(.())
	{
	}

	public this(EditorConfig config) : base(config.AppConfig)
	{
		mEditorConfig = config;
	}

	public ~this()
	{
		// Shutdown modules before they're deleted
		for (let module in mModules)
			module.Shutdown();
	}

	/// Set an external logger to forward messages to.
	public void SetInnerLogger(ILogger innerLogger)
	{
		if (mEditorLogger != null)
			return; // Already created

		mEditorLogger = new EditorLogger(innerLogger, "Editor");
	}

	protected override bool OnInitialize()
	{
		// Create editor logger if not already set
		if (mEditorLogger == null)
			mEditorLogger = new EditorLogger(null, "Editor");

		mEditorLogger.LogInformation("Initializing editor...");

		// Determine settings directory
		if (mEditorConfig.SettingsDirectory != null)
		{
			mSettingsDirectory.Set(mEditorConfig.SettingsDirectory);
		}
		else
		{
			// Default to .sedulous folder in current directory
			mSettingsDirectory.Set(".sedulous");
		}

		// Create recent projects manager
		mRecentProjects = new RecentProjectsManager(mSettingsDirectory);

		// Create core systems
		mAssetRegistry = new AssetRegistry();
		mDocumentManager = new DocumentManager(mAssetRegistry);

		// Register built-in asset handlers
		RegisterBuiltinHandlers();

		// Subscribe to logger for console display
		if (let editorLogger = mEditorLogger as EditorLogger)
		{
			editorLogger.EntryAdded.Subscribe(new (entry) => {
				AppendLogEntry(entry);
			});
		}

		mEditorLogger.LogInformation("Editor initialized successfully");
		return true;
	}

	protected override void OnUISetup(GUIContext context)
	{
		mEditorLogger.LogDebug("Setting up editor UI...");

		// Set dark theme as default
		context.RegisterService<ITheme>(new DarkTheme());

		// Create project manager view (initial view)
		mProjectManagerView = new ProjectManagerView(mRecentProjects);
		mProjectManagerView.Width = .Fill;
		mProjectManagerView.Height = .Fill;

		// Subscribe to project manager events
		mProjectManagerView.ProjectSelected.Subscribe(new (project) => {
			OpenProject(project.Path).IgnoreError();
		});

		mProjectManagerView.NewProjectRequested.Subscribe(new () => {
			ShowNewProjectDialog();
		});

		mProjectManagerView.OpenProjectRequested.Subscribe(new () => {
			// TODO: Show file open dialog
			mEditorLogger.LogDebug("Open project dialog requested");
		});

		// Create dock manager (editor view, hidden initially)
		CreateEditorLayout();

		// Start with project manager
		context.RootElement = mProjectManagerView;
		mShowingProjectManager = true;

		mEditorLogger.LogDebug("Editor UI setup complete");
	}

	protected override void OnUpdate(float deltaTime)
	{
		// Process pending dialog hide (deferred from event handlers)
		if (mPendingDialogHide)
		{
			mPendingDialogHide = false;
			HideNewProjectDialog();
		}

		// Process pending project creation (deferred from event handlers)
		if (mPendingProjectName != null)
		{
			let name = mPendingProjectName;
			let folder = mPendingProjectFolder;
			mPendingProjectName = null;
			mPendingProjectFolder = null;

			NewProject(folder, name);

			delete name;
			delete folder;
		}
	}

	protected override void OnCleanup()
	{
		mEditorLogger?.LogInformation("Shutting down editor...");

		// Close project
		CloseProject();

		// Clean up UI - must happen before UIContext is deleted
		// Clear root first to avoid stale references
		if (mGUIContext != null)
			mGUIContext.RootElement = null;

		// Delete UI elements
		if (mProjectManagerView != null)
		{
			delete mProjectManagerView;
			mProjectManagerView = null;
		}

		if (mNewProjectDialog != null)
		{
			delete mNewProjectDialog;
			mNewProjectDialog = null;
		}

		if (mEditorRoot != null)
		{
			// Remove DockManager from the root before deleting root,
			// because DockManager owns the panels and needs explicit cleanup
			mEditorRoot.RemoveChild(mDockManager, deleteAfterRemove: false);
			delete mDockManager;
			mDockManager = null;

			delete mEditorRoot;
			mEditorRoot = null;
		}
		else if (mDockManager != null)
		{
			delete mDockManager;
			mDockManager = null;
		}

		// Delete panels (DockTabGroup does NOT own panels — creator is responsible)
		delete mProjectPanel;
		mProjectPanel = null;
		delete mPropertiesPanel;
		mPropertiesPanel = null;
		delete mConsolePanel;
		mConsolePanel = null;
		delete mCenterPanel;
		mCenterPanel = null;

		// Clear references (owned by deleted parents above)
		mMenuBar = null;
		mStatusBar = null;
		mProjectStatusItem = null;
		mAssetCountStatusItem = null;
		mConsoleScroller = null;
		mConsoleLogStack = null;
		mRecentProjectsMenuItem = null;
		mAssetBrowser = null;
		mDocumentTabs = null;

		// Clean up theme (UIContext doesn't delete services in destructor)
		if (mGUIContext.GetService<ITheme>() case .Ok(let theme))
			delete theme;

		// Clean up core systems
		if (mDocumentManager != null)
		{
			delete mDocumentManager;
			mDocumentManager = null;
		}

		if (mAssetRegistry != null)
		{
			delete mAssetRegistry;
			mAssetRegistry = null;
		}

		mEditorLogger?.LogInformation("Editor shutdown complete");
	}

	protected override void OnKeyDown(ShellKeyCode key)
	{
		// Global shortcuts
		let keyboard = mShell.InputManager.Keyboard;
		let ctrl = keyboard.IsKeyDown(.LeftCtrl) || keyboard.IsKeyDown(.RightCtrl);
		let shift = keyboard.IsKeyDown(.LeftShift) || keyboard.IsKeyDown(.RightShift);

		if (ctrl)
		{
			switch (key)
			{
			case .S:
				if (shift)
					SaveAll();
				else
					SaveActive();
			case .Z:
				if (shift)
					Redo();
				else
					Undo();
			case .Y:
				Redo();
			case .O:
				// TODO: Show file open dialog
				mEditorLogger.LogDebug("Open project shortcut pressed");
			case .N:
				ShowNewProjectDialog();
			default:
			}
		}
	}

	// ===== View Switching =====

	/// Switch to editor layout (called when a project is opened).
	private void SwitchToEditorLayout()
	{
		if (!mShowingProjectManager)
			return;

		// Configure asset browser with project data
		if (mAssetBrowser != null && mProject != null)
		{
			mAssetBrowser.SetDatabase(mProject.AssetDatabase, mProject.RootPath);
		}

		// Update status bar
		if (mProjectStatusItem != null && mProject != null)
			mProjectStatusItem.Text = mProject.Name;

		if (mAssetCountStatusItem != null && mProject != null)
		{
			let count = mProject.AssetDatabase?.AssetCount ?? 0;
			let text = scope String();
			text.AppendF("Assets: {}", count);
			mAssetCountStatusItem.Text = text;
		}

		// Update window title
		if (mWindow != null && mProject != null)
		{
			let title = scope String();
			title.AppendF("Sedulous Editor — {}", mProject.Name);
			mWindow.Title = title;
		}

		// Rebuild recent projects submenu
		RebuildRecentProjectsMenu();

		mGUIContext.RootElement = mEditorRoot;
		mShowingProjectManager = false;
	}

	/// Switch to project manager (called when a project is closed).
	private void SwitchToProjectManager()
	{
		if (mShowingProjectManager)
			return;

		// Reset status bar
		if (mProjectStatusItem != null)
			mProjectStatusItem.Text = "No project";
		if (mAssetCountStatusItem != null)
			mAssetCountStatusItem.Text = "Assets: 0";

		// Reset window title
		if (mWindow != null)
			mWindow.Title = "Sedulous Editor";

		// Refresh the project list
		mProjectManagerView.RefreshProjectList();

		mGUIContext.RootElement = mProjectManagerView;
		mShowingProjectManager = true;
	}

	/// Show the new project dialog.
	private void ShowNewProjectDialog()
	{
		mEditorLogger.LogDebug("Showing new project dialog");

		// Create dialog if needed
		if (mNewProjectDialog == null)
		{
			mNewProjectDialog = new NewProjectDialog(mShell);

			mNewProjectDialog.ProjectCreated.Subscribe(new (name, folder) => {
				// Defer actions to next update to avoid modifying UI tree during event processing
				mPendingDialogHide = true;
				delete mPendingProjectName;
				delete mPendingProjectFolder;
				mPendingProjectName = new String(name);
				mPendingProjectFolder = new String(folder);
			});

			mNewProjectDialog.Cancelled.Subscribe(new () => {
				// Defer hide to next update
				mPendingDialogHide = true;
			});
		}

		// Show dialog as overlay on project manager
		// Use a simple container that centers the dialog
		let overlay = new Grid();
		overlay.Width = .Fill;
		overlay.Height = .Fill;
		overlay.Background = Color(0, 0, 0, 128); // Semi-transparent backdrop
		overlay.AddChild(mNewProjectDialog);

		mGUIContext.RootElement = overlay;
		mGUIContext.FocusManager?.SetFocus(mNewProjectDialog.NameInput);
	}

	/// Hide the new project dialog.
	private void HideNewProjectDialog()
	{
		// Remove dialog from overlay but don't delete it (we reuse it)
		if (mGUIContext.RootElement is Grid)
		{
			let overlay = mGUIContext.RootElement as Grid;
			// Use ClearChildren(false) to remove without deleting (we reuse the dialog)
			overlay.ClearChildren(false);
			// Switch root element first, then queue delete the overlay
			mGUIContext.RootElement = mProjectManagerView;
			mGUIContext.QueueDelete(overlay);
			return;
		}

		// Return to project manager
		mGUIContext.RootElement = mProjectManagerView;
	}

	// ===== Project Management =====

	/// Create a new project.
	public Result<void> NewProject(StringView path, StringView name)
	{
		mEditorLogger.LogInformation("Creating new project: {0} at {1}", name, path);

		// Close existing project
		CloseProject();

		// Create new project
		if (EditorProject.Create(path, name, mAssetRegistry) case .Ok(let project))
		{
			mProject = project;

			// Add to recent projects (use the full project file path)
			mRecentProjects.AddProject(name, project.ProjectFilePath);

			// Switch to editor view
			SwitchToEditorLayout();

			mProjectOpened.[Friend]Invoke(mProject);
			mEditorLogger.LogInformation("Project created: {0}", name);
			return .Ok;
		}

		mEditorLogger.LogError("Failed to create project: {0}", name);
		return .Err;
	}

	/// Open an existing project.
	public Result<void> OpenProject(StringView projectFilePath)
	{
		mEditorLogger.LogInformation("Opening project: {0}", projectFilePath);

		// Close existing project
		CloseProject();

		// Open project
		if (EditorProject.Open(projectFilePath, mAssetRegistry) case .Ok(let project))
		{
			mProject = project;

			// Add to recent projects
			mRecentProjects.AddProject(project.Name, projectFilePath);

			// Switch to editor view
			SwitchToEditorLayout();

			mProjectOpened.[Friend]Invoke(mProject);
			mEditorLogger.LogInformation("Project opened: {0}", project.Name);
			return .Ok;
		}

		mEditorLogger.LogError("Failed to open project: {0}", projectFilePath);
		return .Err;
	}

	/// Close current project.
	public void CloseProject()
	{
		if (mProject == null)
			return;

		mEditorLogger.LogInformation("Closing project: {0}", mProject.Name);

		// Close all documents
		mDocumentManager.CloseAll();

		// Dispose project
		delete mProject;
		mProject = null;

		// Switch back to project manager
		SwitchToProjectManager();

		mProjectClosed.[Friend]Invoke();
	}

	/// Save current project.
	public Result<void> SaveProject()
	{
		if (mProject == null)
		{
			mEditorLogger.LogWarning("No project to save");
			return .Err;
		}

		mEditorLogger.LogDebug("Saving project: {0}", mProject.Name);
		return mProject.Save();
	}

	// ===== Document Operations =====

	/// Save active document.
	public Result<void> SaveActive()
	{
		if (mDocumentManager.ActiveDocument == null)
		{
			mEditorLogger.LogDebug("No active document to save");
			return .Err;
		}

		let title = scope String();
		mDocumentManager.ActiveDocument.GetTitle(title);
		mEditorLogger.LogDebug("Saving active document: {0}", title);
		return mDocumentManager.SaveActive();
	}

	/// Save all dirty documents.
	public Result<void> SaveAll()
	{
		mEditorLogger.LogDebug("Saving all documents");
		return mDocumentManager.SaveAll();
	}

	/// Undo in active document.
	public void Undo()
	{
		let doc = mDocumentManager.ActiveDocument;
		if (doc != null)
		{
			mEditorLogger.LogDebug("Undo");
			doc.Undo();
		}
	}

	/// Redo in active document.
	public void Redo()
	{
		let doc = mDocumentManager.ActiveDocument;
		if (doc != null)
		{
			mEditorLogger.LogDebug("Redo");
			doc.Redo();
		}
	}

	// ===== Private Methods =====

	private void RegisterBuiltinHandlers()
	{
		mEditorLogger.LogDebug("Initializing {} editor module(s)", mModules.Count);

		// Initialize all registered modules
		for (let module in mModules)
		{
			module.Initialize(mAssetRegistry);
			mEditorLogger.LogDebug("Initialized module: {}", module.Name);
		}
	}

	private void CreateEditorLayout()
	{
		// Root layout: Menu (top) + StatusBar (bottom) + DockManager (fill)
		mEditorRoot = new DockPanel();
		mEditorRoot.Width = .Fill;
		mEditorRoot.Height = .Fill;
		mEditorRoot.LastChildFill = true;

		// Menu bar
		mMenuBar = CreateMenuBar();
		DockPanelProperties.SetDock(mMenuBar, .Top);
		mEditorRoot.AddChild(mMenuBar);

		// Status bar
		mStatusBar = CreateStatusBar();
		DockPanelProperties.SetDock(mStatusBar, .Bottom);
		mEditorRoot.AddChild(mStatusBar);

		// Dock manager (fills remaining space)
		mDockManager = new DockManager();
		mDockManager.Width = .Fill;
		mDockManager.Height = .Fill;
		mEditorRoot.AddChild(mDockManager);

		// Create default panels
		CreateDefaultPanels();

		// Set up default layout
		SetupDefaultLayout();
	}

	private void CreateDefaultPanels()
	{
		// Project browser panel
		mProjectPanel = new DockablePanel();
		mProjectPanel.Title = "Project";
		mProjectPanel.Width = .Fixed(250);
		mProjectPanel.Content = CreateProjectBrowserContent();

		// Properties panel
		mPropertiesPanel = new DockablePanel();
		mPropertiesPanel.Title = "Properties";
		mPropertiesPanel.Width = .Fixed(300);
		mPropertiesPanel.Content = CreatePropertiesContent();

		// Console panel
		mConsolePanel = new DockablePanel();
		mConsolePanel.Title = "Console";
		mConsolePanel.Height = .Fixed(200);
		mConsolePanel.Content = CreateConsoleContent();
	}

	private void SetupDefaultLayout()
	{
		// Default layout:
		// +-------------------+------------------+----------------+
		// |                   |                  |                |
		// |  Project (Left)   |   Center         | Properties     |
		// |                   |   (Documents)    |   (Right)      |
		// |                   +------------------+                |
		// |                   |  Console (Bottom)|                |
		// +-------------------+------------------+----------------+

		// Create document tab strip for center area
		mDocumentTabs = new DocumentTabStrip(mDocumentManager);
		mDocumentTabs.Width = .Fill;
		mDocumentTabs.Height = .Fill;

		// Add document tabs as center content (wrapped in a panel)
		mCenterPanel = new DockablePanel("Documents", mDocumentTabs);
		mDockManager.AddPanel(mCenterPanel);

		// Dock panels around the center
		mDockManager.DockPanel(mProjectPanel, .Left);
		mDockManager.DockPanel(mPropertiesPanel, .Right);
		mDockManager.DockPanel(mConsolePanel, .Bottom);
	}

	private Menu CreateMenuBar()
	{
		let menu = new Menu();
		menu.Padding = .(4, 2, 4, 2);

		// ===== File Menu =====
		let fileMenu = menu.AddItem("&File");

		let newProjectItem = fileMenu.AddDropdownItem("&New Project...");
		newProjectItem.ShortcutText = "Ctrl+N";
		newProjectItem.Click.Subscribe(new (item) => { ShowNewProjectDialog(); });

		let openProjectItem = fileMenu.AddDropdownItem("&Open Project...");
		openProjectItem.ShortcutText = "Ctrl+O";
		openProjectItem.Click.Subscribe(new (item) => {
			mEditorLogger.LogDebug("Open project dialog requested");
		});

		let saveProjectItem = fileMenu.AddDropdownItem("&Save Project");
		saveProjectItem.ShortcutText = "Ctrl+S";
		saveProjectItem.Click.Subscribe(new (item) => { SaveProject(); });

		fileMenu.AddDropdownSeparator();

		// Recent Projects submenu
		mRecentProjectsMenuItem = fileMenu.AddDropdownItem("Recent Projects");
		RebuildRecentProjectsMenu();

		fileMenu.AddDropdownSeparator();

		let closeProjectItem = fileMenu.AddDropdownItem("&Close Project");
		closeProjectItem.Click.Subscribe(new (item) => { CloseProject(); });

		let exitItem = fileMenu.AddDropdownItem("E&xit");
		exitItem.Click.Subscribe(new (item) => { Exit(); });

		// ===== Edit Menu =====
		let editMenu = menu.AddItem("&Edit");

		let undoItem = editMenu.AddDropdownItem("&Undo");
		undoItem.ShortcutText = "Ctrl+Z";
		undoItem.Click.Subscribe(new (item) => { Undo(); });

		let redoItem = editMenu.AddDropdownItem("&Redo");
		redoItem.ShortcutText = "Ctrl+Y";
		redoItem.Click.Subscribe(new (item) => { Redo(); });

		// ===== View Menu =====
		let viewMenu = menu.AddItem("&View");

		let projectPanelItem = viewMenu.AddDropdownItem("&Project");
		projectPanelItem.IsCheckable = true;
		projectPanelItem.IsChecked = true;
		projectPanelItem.Click.Subscribe(new (item) => {
			TogglePanel(mProjectPanel, item.IsChecked);
		});

		let propertiesPanelItem = viewMenu.AddDropdownItem("P&roperties");
		propertiesPanelItem.IsCheckable = true;
		propertiesPanelItem.IsChecked = true;
		propertiesPanelItem.Click.Subscribe(new (item) => {
			TogglePanel(mPropertiesPanel, item.IsChecked);
		});

		let consolePanelItem = viewMenu.AddDropdownItem("&Console");
		consolePanelItem.IsCheckable = true;
		consolePanelItem.IsChecked = true;
		consolePanelItem.Click.Subscribe(new (item) => {
			TogglePanel(mConsolePanel, item.IsChecked);
		});

		return menu;
	}

	/// Rebuilds the Recent Projects submenu from RecentProjectsManager.
	private void RebuildRecentProjectsMenu()
	{
		if (mRecentProjectsMenuItem == null)
			return;

		// Clear existing submenu items and tracked path strings
		mRecentProjectsMenuItem.ClearItems();
		for (let s in mRecentMenuPaths)
			delete s;
		mRecentMenuPaths.Clear();

		if (mRecentProjects == null || mRecentProjects.Count == 0)
		{
			let emptyItem = mRecentProjectsMenuItem.AddItem("(none)");
			emptyItem.IsEnabled = false;
			return;
		}

		for (let project in mRecentProjects.Projects)
		{
			let path = new String(project.Path);
			mRecentMenuPaths.Add(path);
			let item = mRecentProjectsMenuItem.AddItem(project.Name);
			item.Click.Subscribe(new (menuItem) => {
				OpenProject(path).IgnoreError();
			});
		}
	}

	/// Toggles a dockable panel's visibility.
	private void TogglePanel(DockablePanel panel, bool visible)
	{
		if (panel == null || mDockManager == null)
			return;

		panel.Visibility = visible ? .Visible : .Collapsed;
	}

	private StatusBar CreateStatusBar()
	{
		let statusBar = new StatusBar();
		statusBar.Padding = .(6, 2, 6, 2);

		mProjectStatusItem = statusBar.AddFixedItem("No project", 250);
		mAssetCountStatusItem = statusBar.AddFixedItem("Assets: 0", 120);
		statusBar.AddFlexibleItem("");  // Spacer

		return statusBar;
	}

	private UIElement CreateProjectBrowserContent()
	{
		mAssetBrowser = new AssetBrowser();
		mAssetBrowser.Width = .Fill;
		mAssetBrowser.Height = .Fill;

		// Subscribe to asset selection events
		mAssetBrowser.AssetSelected.Subscribe(new (entry) => {
			mEditorLogger.LogDebug("Asset selected: {0}", entry.Name);
			// TODO: Update properties panel with asset details
		});

		mAssetBrowser.AssetDoubleClick.Subscribe(new (entry) => {
			mEditorLogger.LogDebug("Asset double-clicked: {0}", entry.Name);
			OpenAsset(entry);
		});

		return mAssetBrowser;
	}

	/// Open an asset for editing.
	private void OpenAsset(AssetEntry entry)
	{
		if (entry == null || mProject == null)
			return;

		// Build full path to asset
		let fullPath = scope String();
		Path.InternalCombine(fullPath, mProject.RootPath, entry.Path);

		// Open via document manager
		if (mDocumentManager.OpenPath(fullPath) case .Ok(let doc))
		{
			mEditorLogger.LogInformation("Opened document: {0}", entry.Name);
		}
		else
		{
			mEditorLogger.LogWarning("Failed to open asset: {0}", entry.Path);
		}
	}

	private UIElement CreatePropertiesContent()
	{
		let panel = new StackPanel();
		panel.Orientation = .Vertical;
		panel.Padding = .(8);

		let label = new Label("No selection");
		panel.AddChild(label);

		return panel;
	}

	private UIElement CreateConsoleContent()
	{
		mConsoleLogStack = new StackPanel();
		mConsoleLogStack.Orientation = .Vertical;
		mConsoleLogStack.Spacing = 1;

		mConsoleScroller = new ScrollViewer();
		mConsoleScroller.HorizontalScrollBarVisibility = .Disabled;
		mConsoleScroller.VerticalScrollBarVisibility = .Auto;
		mConsoleScroller.Content = mConsoleLogStack;

		// Populate with any entries logged before UI was created
		if (mEditorLogger != null)
		{
			if (let editorLogger = mEditorLogger as EditorLogger)
			{
				for (let entry in editorLogger.Entries)
					AppendLogEntry(entry);
			}
		}

		return mConsoleScroller;
	}

	/// Appends a log entry to the console panel.
	private void AppendLogEntry(LogEntry entry)
	{
		if (mConsoleLogStack == null)
			return;

		// Format: [HH:MM:SS] message
		let text = scope String();
		text.AppendF("[{0:D2}:{1:D2}:{2:D2}] {3}",
			entry.Timestamp.Hour, entry.Timestamp.Minute, entry.Timestamp.Second,
			entry.Message);

		let tb = new TextBlock(text);
		tb.Margin = .(4, 1, 4, 1);

		// Color based on log level
		switch (entry.Level)
		{
		case .Error, .Critical:
			tb.Foreground = Color(255, 80, 80, 255);
		case .Warning:
			tb.Foreground = Color(255, 200, 80, 255);
		case .Debug, .Trace:
			tb.Foreground = Color(140, 140, 140, 255);
		default: // Info
			tb.Foreground = Color(220, 220, 220, 255);
		}

		mConsoleLogStack.AddChild(tb);

		// Cap visible entries to avoid UI bloat
		while (mConsoleLogStack.Children.Count > 500)
		{
			let oldest = mConsoleLogStack.Children[0];
			mConsoleLogStack.RemoveChild(oldest);  // default deleteAfterRemove: true
		}

		// Auto-scroll to bottom
		mConsoleScroller?.ScrollToBottom();
	}
}
