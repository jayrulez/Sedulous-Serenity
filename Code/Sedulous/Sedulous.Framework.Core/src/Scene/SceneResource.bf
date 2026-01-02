using System;
using Sedulous.Resources;
using Sedulous.Serialization;

namespace Sedulous.Framework.Core;

/// A scene as a loadable resource.
/// Wraps a Scene for use with the resource system.
class SceneResource : Resource
{
	private Scene mScene ~ delete _;

	/// Gets the wrapped scene.
	public Scene Scene => mScene;

	/// Creates an empty SceneResource.
	public this()
	{
	}

	/// Creates a SceneResource wrapping the given scene.
	public this(Scene scene)
	{
		mScene = scene;
		Name.Set(scene.Name);
	}

	/// Creates a new scene with the given name and component registry.
	public void CreateScene(StringView name, ComponentRegistry componentRegistry)
	{
		if (mScene != null)
			delete mScene;
		mScene = new Scene(name, componentRegistry);
		Name.Set(name);
	}

	public override int32 SerializationVersion => 1;

	protected override SerializationResult OnSerialize(Serializer s)
	{
		// Serialize the scene
		if (s.IsWriting)
		{
			if (mScene == null)
				return .NullValue;
			return mScene.Serialize(s);
		}
		else
		{
			// Scene will be deserialized but we need a component registry
			// This is handled by SceneResourceManager which sets up the scene
			if (mScene != null)
				return mScene.Serialize(s);
			return .Ok;
		}
	}
}
