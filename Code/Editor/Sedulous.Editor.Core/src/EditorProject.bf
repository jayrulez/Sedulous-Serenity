namespace Sedulous.Editor.Core;

using System;
using System.IO;

/// Represents an editor project.
class EditorProject : IDisposable
{
	private String mRootPath = new .() ~ delete _;
	private String mProjectFilePath = new .() ~ delete _;
	private ProjectSettings mSettings = new .() ~ delete _;
	private AssetDatabase mAssetDatabase;
	private AssetRegistry mAssetRegistry;
	private bool mIsDirty;

	/// Project root directory.
	public String RootPath => mRootPath;

	/// Project file path.
	public String ProjectFilePath => mProjectFilePath;

	/// Project settings.
	public ProjectSettings Settings => mSettings;

	/// Asset database.
	public AssetDatabase AssetDatabase => mAssetDatabase;

	/// Project name (from settings).
	public StringView Name => mSettings.Name;

	/// Whether project has unsaved changes.
	public bool IsDirty => mIsDirty;

	/// Project file extension.
	public static StringView ProjectExtension => ".sedproj";

	public this(AssetRegistry assetRegistry)
	{
		mAssetRegistry = assetRegistry;
		mAssetDatabase = new AssetDatabase(assetRegistry);
	}

	public void Dispose()
	{
		delete mAssetDatabase;
	}

	/// Create a new project.
	public static Result<EditorProject> Create(StringView path, StringView name, AssetRegistry registry)
	{
		// Ensure directory exists
		if (!Directory.Exists(path))
		{
			if (Directory.CreateDirectory(path) case .Err)
				return .Err;
		}

		let project = new EditorProject(registry);
		project.mRootPath.Set(path);
		project.mSettings.Name.Set(name);
		project.mSettings.ProjectId = Guid.Create();

		// Set project file path
		Path.InternalCombine(project.mProjectFilePath, path, name);
		project.mProjectFilePath.Append(ProjectExtension);

		// Create default asset folder
		let assetPath = scope String();
		Path.InternalCombine(assetPath, path, "Assets");
		if (!Directory.Exists(assetPath))
			Directory.CreateDirectory(assetPath);

		// Initialize asset database
		project.mAssetDatabase.Initialize(path, project.mSettings.AssetFolders);

		// Save the new project
		if (project.Save() case .Err)
		{
			delete project;
			return .Err;
		}

		return project;
	}

	/// Open an existing project.
	public static Result<EditorProject> Open(StringView projectFilePath, AssetRegistry registry)
	{
		if (!File.Exists(projectFilePath))
			return .Err;

		let project = new EditorProject(registry);
		project.mProjectFilePath.Set(projectFilePath);

		// Get root directory
		Path.GetDirectoryPath(projectFilePath, project.mRootPath);

		// Load project settings
		if (project.LoadSettings() case .Err)
		{
			delete project;
			return .Err;
		}

		// Initialize asset database
		project.mAssetDatabase.Initialize(project.mRootPath, project.mSettings.AssetFolders);
		project.mAssetDatabase.Refresh();

		return project;
	}

	/// Save the project.
	public Result<void> Save()
	{
		if (SaveSettings() case .Err)
			return .Err;

		mIsDirty = false;
		return .Ok;
	}

	/// Mark project as dirty.
	public void MarkDirty()
	{
		mIsDirty = true;
	}

	/// Refresh asset database.
	public void RefreshAssets()
	{
		mAssetDatabase.Refresh();
	}

	/// Get absolute path for an asset.
	public void GetAbsolutePath(StringView relativePath, String outPath)
	{
		Path.InternalCombine(outPath, mRootPath, relativePath);
	}

	/// Get relative path from absolute.
	public bool GetRelativePath(StringView absolutePath, String outPath)
	{
		if (absolutePath.StartsWith(mRootPath, .OrdinalIgnoreCase))
		{
			var relative = absolutePath.Substring(mRootPath.Length);
			if (relative.StartsWith('/') || relative.StartsWith('\\'))
				relative = relative.Substring(1);
			outPath.Set(relative);
			return true;
		}
		return false;
	}

	/// Import an external file as an asset.
	public Result<IAsset> Import(StringView externalPath, StringView targetFolder)
	{
		// Check if handler exists for this file type
		let handler = mAssetRegistry.GetHandlerForExtension(externalPath);
		if (handler == null)
			return .Err;

		// Determine target path
		let fileName = Path.GetFileName(externalPath, .. scope .());
		let targetPath = scope String();
		Path.InternalCombine(targetPath, targetFolder, fileName);

		// Get absolute paths
		let absoluteTarget = scope String();
		GetAbsolutePath(targetPath, absoluteTarget);

		// Ensure target directory exists
		let targetDir = scope String();
		Path.GetDirectoryPath(absoluteTarget, targetDir);
		if (!Directory.Exists(targetDir))
		{
			if (Directory.CreateDirectory(targetDir) case .Err)
				return .Err;
		}

		// Copy file
		if (File.Copy(externalPath, absoluteTarget) case .Err)
			return .Err;

		// Refresh to pick up the new asset
		mAssetDatabase.Refresh();

		// Return the loaded asset
		return mAssetDatabase.GetAsset(targetPath);
	}

	// ===== Private Methods =====

	private Result<void> LoadSettings()
	{
		// TODO: Implement XML/OpenDDL loading
		// For now, create default settings
		let projectName = Path.GetFileNameWithoutExtension(mProjectFilePath, .. scope .());
		mSettings.Name.Set(projectName);
		return .Ok;
	}

	private Result<void> SaveSettings()
	{
		// TODO: Implement XML/OpenDDL saving
		// For now, just return success
		return .Ok;
	}
}
