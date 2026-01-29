namespace Sedulous.Editor.Scenes;

using System;
using Sedulous.Editor.Core;

/// Handler for scene assets.
class SceneAssetHandler : AssetHandler
{
	public override StringView AssetType => "scene";
	public override StringView DisplayName => "Scene";

	public this()
	{
		AddExtension(".scene");
		AddExtension(".scn");
		SetTransformer(new SceneTransformer());
	}

	public override Result<IAsset> CreateNew(StringView name)
	{
		let asset = new SceneAsset(name);
		asset.CreateDefault();
		return asset;
	}

	public override Result<IAsset> Load(StringView path)
	{
		let asset = new SceneAsset();
		if (asset.Load(path) case .Err)
		{
			delete asset;
			return .Err;
		}
		return asset;
	}

	public override Result<void> Save(IAsset asset, StringView path)
	{
		if (let sceneAsset = asset as SceneAsset)
		{
			return sceneAsset.Save(path);
		}
		return .Err;
	}

	public override Result<IAssetDocument> CreateDocument(IAsset asset)
	{
		if (let sceneAsset = asset as SceneAsset)
		{
			let doc = new SceneAssetDocument(sceneAsset);
			return doc;
		}
		return .Err;
	}
}
