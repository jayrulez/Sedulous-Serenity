using System;
using System.IO;
using System.Collections;
using Sedulous.Resources;

namespace Sedulous.Framework.Scenes;

/// Resource manager for loading SceneResource files via the ResourceSystem.
/// Stores component serializer prototypes that are cloned onto each loaded SceneResource.
class SceneResourceManager : ResourceManager<SceneResource>
{
	private List<IComponentSerializer> mSerializerPrototypes = new .() ~ DeleteContainerAndItems!(_);

	/// Registers a component type for scene serialization.
	/// All scenes loaded by this manager will support this component type.
	public void RegisterComponentType<T>() where T : struct, ISerializableComponent
	{
		mSerializerPrototypes.Add(new ComponentSerializer<T>());
	}

	protected override Result<SceneResource, ResourceLoadError> LoadFromFile(StringView path)
	{
		let resource = new SceneResource();

		// Clone serializer prototypes onto the resource before loading
		for (let proto in mSerializerPrototypes)
			resource.RegisterComponentSerializer(proto.CreateNew());

		if (resource.Load(path) case .Err)
		{
			delete resource;
			return .Err(.ReadError);
		}

		return .Ok(resource);
	}

	protected override Result<SceneResource, ResourceLoadError> LoadFromMemory(MemoryStream memory)
	{
		return .Err(.NotSupported);
	}

	public override void Unload(SceneResource resource)
	{
		if (resource != null)
			resource.ReleaseRef();
	}
}
