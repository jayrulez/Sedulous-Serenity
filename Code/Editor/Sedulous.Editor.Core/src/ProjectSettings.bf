namespace Sedulous.Editor.Core;

using System;
using System.Collections;

/// Project version information.
struct ProjectVersion
{
	public int32 Major;
	public int32 Minor;
	public int32 Patch;

	public this(int32 major = 1, int32 minor = 0, int32 patch = 0)
	{
		Major = major;
		Minor = minor;
		Patch = patch;
	}

	public override void ToString(String strBuffer)
	{
		strBuffer.AppendF("{}.{}.{}", Major, Minor, Patch);
	}

	public static Result<ProjectVersion> Parse(StringView str)
	{
		var parts = str.Split('.');
		int32 major = 1, minor = 0, patch = 0;

		if (parts.GetNext() case .Ok(let majorStr))
		{
			if (int32.Parse(majorStr) case .Ok(let val))
				major = val;
		}
		if (parts.GetNext() case .Ok(let minorStr))
		{
			if (int32.Parse(minorStr) case .Ok(let val))
				minor = val;
		}
		if (parts.GetNext() case .Ok(let patchStr))
		{
			if (int32.Parse(patchStr) case .Ok(let val))
				patch = val;
		}

		return ProjectVersion(major, minor, patch);
	}
}

/// Physics backend options.
enum PhysicsBackend
{
	None,
	Jolt
}

/// Audio backend options.
enum AudioBackend
{
	None,
	SDL3
}

/// Optimization level for builds.
enum OptimizationLevel
{
	None,
	Size,
	Speed
}

/// Subsystem configuration.
class SubsystemConfig
{
	/// Physics subsystem enabled.
	public bool Physics = true;

	/// Physics backend.
	public PhysicsBackend PhysicsBackend = .Jolt;

	/// Audio subsystem enabled.
	public bool Audio = true;

	/// Audio backend.
	public AudioBackend AudioBackend = .SDL3;

	/// Navigation subsystem enabled.
	public bool Navigation = true;

	/// UI subsystem enabled.
	public bool UI = true;

	/// Input subsystem enabled.
	public bool Input = true;
}

/// Build configuration.
class BuildConfig
{
	/// Configuration name (e.g., "Debug", "Release", "Shipping").
	public String Name = new .() ~ delete _;

	/// Output directory (relative to project root).
	public String OutputDir = new .() ~ delete _;

	/// Debug symbols enabled.
	public bool DebugSymbols = true;

	/// Optimization level.
	public OptimizationLevel Optimization = .None;

	/// Asset compression enabled.
	public bool CompressAssets = false;

	/// Include editor-only data in build.
	public bool IncludeEditorData = false;

	/// Custom defines.
	public List<String> Defines = new .() ~ DeleteContainerAndItems!(_);

	public this()
	{
	}

	public this(StringView name)
	{
		Name.Set(name);
	}
}

/// Project settings.
class ProjectSettings
{
	/// Project name.
	public String Name = new .() ~ delete _;

	/// Project version.
	public ProjectVersion Version = .(1, 0, 0);

	/// Unique project identifier.
	public Guid ProjectId;

	/// Default startup scene (asset path).
	public String StartupScene = new .() ~ delete _;

	/// Asset directories to scan (relative to project root).
	public List<String> AssetFolders = new .() ~ DeleteContainerAndItems!(_);

	/// Enabled subsystems.
	public SubsystemConfig Subsystems = new .() ~ delete _;

	/// Build configurations.
	public List<BuildConfig> BuildConfigs = new .() ~ DeleteContainerAndItems!(_);

	/// Platform targets.
	public List<TargetPlatform> Platforms = new .() ~ delete _;

	/// Custom project metadata.
	public Dictionary<String, String> Metadata = new .() ~ {
		for (let kv in _)
		{
			delete kv.key;
			delete kv.value;
		}
		delete _;
	};

	public this()
	{
		ProjectId = Guid.Create();

		// Default asset folder
		AssetFolders.Add(new String("Assets"));

		// Default platforms
		Platforms.Add(.Windows);

		// Default build configs
		let debug = new BuildConfig("Debug");
		debug.OutputDir.Set("Build/Debug");
		debug.DebugSymbols = true;
		debug.Optimization = .None;
		BuildConfigs.Add(debug);

		let release = new BuildConfig("Release");
		release.OutputDir.Set("Build/Release");
		release.DebugSymbols = false;
		release.Optimization = .Speed;
		release.CompressAssets = true;
		BuildConfigs.Add(release);
	}

	/// Get a build config by name.
	public BuildConfig GetBuildConfig(StringView name)
	{
		for (let config in BuildConfigs)
		{
			if (config.Name == name)
				return config;
		}
		return null;
	}

	/// Add or update metadata.
	public void SetMetadata(StringView key, StringView value)
	{
		for (let kv in Metadata)
		{
			if (kv.key == key)
			{
				kv.value.Set(value);
				return;
			}
		}
		Metadata[new String(key)] = new String(value);
	}

	/// Get metadata value.
	public StringView GetMetadata(StringView key)
	{
		for (let kv in Metadata)
		{
			if (kv.key == key)
				return kv.value;
		}
		return default;
	}
}
