namespace Sedulous.Editor.Core;

using System;
using Sedulous.Resources;

/// Interface for asset transformers.
/// Transforms editor assets to runtime resources.
interface IAssetTransformer : IDisposable
{
	/// Source asset type identifier.
	StringView SourceAssetType { get; }

	/// Target resource type name.
	StringView TargetResourceType { get; }

	/// Transform asset to runtime resource.
	Result<IResource> Transform(IAsset asset, TransformContext context);

	/// Get output path for transformed resource.
	void GetOutputPath(IAsset asset, String outPath, TransformContext context);
}

/// Context for asset transformation.
class TransformContext
{
	/// Project root directory.
	public String ProjectRoot = new .() ~ delete _;

	/// Output directory for resources.
	public String OutputRoot = new .() ~ delete _;

	/// Target platform.
	public TargetPlatform Platform = .Windows;

	/// Build configuration.
	public BuildConfiguration Configuration = .Debug;

	/// Asset registry for resolving dependencies.
	public AssetRegistry AssetRegistry;

	/// Report transformation progress (0.0 - 1.0).
	public delegate void(float progress, StringView message) OnProgress;

	/// Report warning.
	public delegate void(StringView message) OnWarning;

	/// Report error.
	public delegate void(StringView message) OnError;

	/// Report progress.
	public void ReportProgress(float progress, StringView message)
	{
		OnProgress?.Invoke(progress, message);
	}

	/// Report warning.
	public void ReportWarning(StringView message)
	{
		OnWarning?.Invoke(message);
	}

	/// Report error.
	public void ReportError(StringView message)
	{
		OnError?.Invoke(message);
	}
}

/// Target platform for builds.
enum TargetPlatform
{
	Windows,
	Linux,
	MacOS,
	Android,
	iOS,
	WebGL
}

/// Build configuration.
enum BuildConfiguration
{
	Debug,
	Release,
	Shipping
}
