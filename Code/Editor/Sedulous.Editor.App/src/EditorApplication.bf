namespace Sedulous.Editor.App;

using System;
using System.Collections;
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
}

/// Main editor application.
public class EditorApplication : Application
{
	private EditorConfig mEditorConfig;

	// Logging
	private static ILogger sLogger;

	// Core systems
	private AssetRegistry mAssetRegistry;
	private DocumentManager mDocumentManager;
	private EditorProject mProject;

	// UI components
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

	/// Logger instance.
	public static ILogger Logger => sLogger;

	public this() : this(.())
	{
	}

	public this(EditorConfig config) : base(config.AppConfig)
	{
		mEditorConfig = config;
	}

	/// Set the logger for the editor application.
	public static void SetLogger(ILogger logger)
	{
		sLogger = logger;
	}

	protected override bool OnInitialize()
	{
		sLogger?.LogInformation("Initializing editor...");

		// Create core systems
		mAssetRegistry = new AssetRegistry();
		mDocumentManager = new DocumentManager(mAssetRegistry);

		// Register built-in asset handlers
		RegisterBuiltinHandlers();

		sLogger?.LogInformation("Editor initialized successfully");
		return true;
	}

	protected override void OnUISetup(UIContext context)
	{
		sLogger?.LogDebug("Setting up editor UI...");

		// Create main dock manager
		mDockManager = new DockManager();
		mDockManager.Width = .Fill;
		mDockManager.Height = .Fill;

		// Create default panels
		CreateDefaultPanels();

		// Set up default layout
		SetupDefaultLayout();

		// Set as root
		context.RootElement = mDockManager;

		sLogger?.LogDebug("Editor UI setup complete");
	}

	protected override void OnUpdate(float deltaTime)
	{
		// Update editor systems
	}

	protected override void OnCleanup()
	{
		sLogger?.LogInformation("Shutting down editor...");

		// Close project
		CloseProject();

		// Clean up core systems
		if (mDocumentManager != null)
			delete mDocumentManager;

		if (mAssetRegistry != null)
			delete mAssetRegistry;

		sLogger?.LogInformation("Editor shutdown complete");
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
				sLogger?.LogDebug("Open project shortcut pressed");
			case .N:
				// TODO: Show new project dialog
				sLogger?.LogDebug("New project shortcut pressed");
			default:
			}
		}
	}

	// ===== Project Management =====

	/// Create a new project.
	public Result<void> NewProject(StringView path, StringView name)
	{
		sLogger?.LogInformation("Creating new project: {0} at {1}", name, path);

		// Close existing project
		CloseProject();

		// Create new project
		if (EditorProject.Create(path, name, mAssetRegistry) case .Ok(let project))
		{
			mProject = project;
			mProjectOpened.[Friend]Invoke(mProject);
			sLogger?.LogInformation("Project created: {0}", name);
			return .Ok;
		}

		sLogger?.LogError("Failed to create project: {0}", name);
		return .Err;
	}

	/// Open an existing project.
	public Result<void> OpenProject(StringView projectFilePath)
	{
		sLogger?.LogInformation("Opening project: {0}", projectFilePath);

		// Close existing project
		CloseProject();

		// Open project
		if (EditorProject.Open(projectFilePath, mAssetRegistry) case .Ok(let project))
		{
			mProject = project;
			mProjectOpened.[Friend]Invoke(mProject);
			sLogger?.LogInformation("Project opened: {0}", project.Name);
			return .Ok;
		}

		sLogger?.LogError("Failed to open project: {0}", projectFilePath);
		return .Err;
	}

	/// Close current project.
	public void CloseProject()
	{
		if (mProject == null)
			return;

		sLogger?.LogInformation("Closing project: {0}", mProject.Name);

		// Close all documents
		mDocumentManager.CloseAll();

		// Dispose project
		delete mProject;
		mProject = null;

		mProjectClosed.[Friend]Invoke();
	}

	/// Save current project.
	public Result<void> SaveProject()
	{
		if (mProject == null)
		{
			sLogger?.LogWarning("No project to save");
			return .Err;
		}

		sLogger?.LogDebug("Saving project: {0}", mProject.Name);
		return mProject.Save();
	}

	// ===== Document Operations =====

	/// Save active document.
	public Result<void> SaveActive()
	{
		if (mDocumentManager.ActiveDocument == null)
		{
			sLogger?.LogDebug("No active document to save");
			return .Err;
		}

		let title = scope String();
		mDocumentManager.ActiveDocument.GetTitle(title);
		sLogger?.LogDebug("Saving active document: {0}", title);
		return mDocumentManager.SaveActive();
	}

	/// Save all dirty documents.
	public Result<void> SaveAll()
	{
		sLogger?.LogDebug("Saving all documents");
		return mDocumentManager.SaveAll();
	}

	/// Undo in active document.
	public void Undo()
	{
		let doc = mDocumentManager.ActiveDocument;
		if (doc != null)
		{
			sLogger?.LogDebug("Undo");
			doc.Undo();
		}
	}

	/// Redo in active document.
	public void Redo()
	{
		let doc = mDocumentManager.ActiveDocument;
		if (doc != null)
		{
			sLogger?.LogDebug("Redo");
			doc.Redo();
		}
	}

	// ===== Private Methods =====

	private void RegisterBuiltinHandlers()
	{
		// Asset handlers will be registered by editor modules (e.g., Sedulous.Editor.Scenes)
		sLogger?.LogDebug("Registering built-in asset handlers");
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

		let welcomeLabel = new Label("Open a project to begin");
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

		let label = new Label("No project open");
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
