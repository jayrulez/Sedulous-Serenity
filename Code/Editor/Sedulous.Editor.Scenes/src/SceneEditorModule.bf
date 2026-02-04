namespace Sedulous.Editor.Scenes;

using System;
using Sedulous.Editor.Core;

/// Editor module for scene editing.
/// Registers scene asset handler and provides scene-related menu items.
class SceneEditorModule : IEditorModule
{
	private SceneAssetHandler mHandler /*~ delete _*/;

	public StringView Name => "Scene Editor";

	public void Initialize(AssetRegistry registry)
	{
		// Create and register scene asset handler
		mHandler = new SceneAssetHandler();
		registry.RegisterHandler(mHandler);
	}

	public void Shutdown()
	{
		// Handler is deleted in destructor
	}
}
