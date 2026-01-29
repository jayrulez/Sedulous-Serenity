namespace Sedulous.Editor.App;

using System;
using System.Collections;
using System.IO;
using Sedulous.AppFramework;
using Sedulous.Editor.Core;
using Sedulous.UI;
using Sedulous.Foundation.Core;
using Sedulous.Logging.Abstractions;

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

	// UI state
	private bool mShowingProjectManager = true;
	private ProjectManagerView mProjectManagerView;
	private DockManager mDockManager;
	private DockablePanel mProjectPanel;
	private DockablePanel mPropertiesPanel;
	private DockablePanel mConsolePanel;

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

	public this() : this(.())
	{
	}

	public this(EditorConfig config) : base(config.AppConfig)
	{
		mEditorConfig = config;
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

		mEditorLogger.LogInformation("Editor initialized successfully");
		return true;
	}

	protected override void OnUISetup(UIContext context)
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
			OpenProject(project.Path);
		});

		mProjectManagerView.NewProjectRequested.Subscribe(new () => {
			// TODO: Show new project dialog
			mEditorLogger.LogDebug("New project requested");
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
		// Update editor systems
	}

	protected override void OnCleanup()
	{
		mEditorLogger?.LogInformation("Shutting down editor...");

		// Close project
		CloseProject();

		// Clean up UI - must happen before UIContext is deleted
		// Clear root first to avoid stale references
		if (mUIContext != null)
			mUIContext.RootElement = null;

		// Delete UI elements
		if (mProjectManagerView != null)
		{
			delete mProjectManagerView;
			mProjectManagerView = null;
		}

		if (mDockManager != null)
		{
			delete mDockManager;
			mDockManager = null;
		}

		// Clear panel references (already deleted by dock manager)
		mProjectPanel = null;
		mPropertiesPanel = null;
		mConsolePanel = null;

		// Clean up theme (UIContext doesn't delete services in destructor)
		if (mUIContext.GetService<ITheme>() case .Ok(let theme))
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
				// TODO: Show open project dialog
				mEditorLogger.LogDebug("Open project shortcut pressed");
			case .N:
				// TODO: Show new project dialog
				mEditorLogger.LogDebug("New project shortcut pressed");
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

		mUIContext.RootElement = mDockManager;
		mShowingProjectManager = false;
	}

	/// Switch to project manager (called when a project is closed).
	private void SwitchToProjectManager()
	{
		if (mShowingProjectManager)
			return;

		// Refresh the project list
		mProjectManagerView.RefreshProjectList();

		mUIContext.RootElement = mProjectManagerView;
		mShowingProjectManager = true;
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

			// Add to recent projects
			mRecentProjects.AddProject(name, path);

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
		// Asset handlers will be registered by editor modules (e.g., Sedulous.Editor.Scenes)
		mEditorLogger.LogDebug("Registering built-in asset handlers");
	}

	private void CreateEditorLayout()
	{
		// Create dock manager
		mDockManager = new DockManager();
		mDockManager.Width = .Fill;
		mDockManager.Height = .Fill;

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
		mProjectPanel.PanelContent = CreateProjectBrowserContent();

		// Properties panel
		mPropertiesPanel = new DockablePanel();
		mPropertiesPanel.Title = "Properties";
		mPropertiesPanel.Width = .Fixed(300);
		mPropertiesPanel.PanelContent = CreatePropertiesContent();

		// Console panel
		mConsolePanel = new DockablePanel();
		mConsolePanel.Title = "Console";
		mConsolePanel.Height = .Fixed(200);
		mConsolePanel.PanelContent = CreateConsoleContent();
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

		// Set center content placeholder
		let centerContent = new StackPanel();
		centerContent.HorizontalAlignment = .Center;
		centerContent.VerticalAlignment = .Center;

		let welcomeLabel = new Label("Open an asset to edit");
		centerContent.AddChild(welcomeLabel);

		mDockManager.CenterContent = centerContent;

		// Dock panels
		mDockManager.LeftWidth = 250;
		mDockManager.RightWidth = 300;
		mDockManager.BottomHeight = 200;

		mDockManager.Dock(mProjectPanel, .Left);
		mDockManager.Dock(mPropertiesPanel, .Right);
		mDockManager.Dock(mConsolePanel, .Bottom);
	}

	private UIElement CreateProjectBrowserContent()
	{
		let panel = new StackPanel();
		panel.Orientation = .Vertical;
		panel.Padding = .(8);

		let label = new Label("Project files");
		panel.AddChild(label);

		return panel;
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
		let panel = new StackPanel();
		panel.Orientation = .Vertical;
		panel.Padding = .(8);

		let label = new Label("Console output");
		panel.AddChild(label);

		return panel;
	}
}
