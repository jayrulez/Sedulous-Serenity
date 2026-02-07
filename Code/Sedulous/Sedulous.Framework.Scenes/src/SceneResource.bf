using System;
using System.IO;
using Sedulous.Resources;
using Sedulous.Serialization;
using Sedulous.Serialization.OpenDDL;
using Sedulous.OpenDDL;
using System.Collections;

namespace Sedulous.Framework.Scenes;

/// Resource wrapper for a Scene, providing file I/O via OpenDDL serialization.
class SceneResource : Resource
{
	private Scene mScene;
	private bool mOwnsScene;
	private List<IComponentSerializer> mSerializerPrototypes = new .() ~ DeleteContainerAndItems!(_);

	/// The underlying scene.
	public Scene Scene => mScene;

	public this()
	{
		mScene = null;
		mOwnsScene = false;
	}

	public this(Scene scene, bool ownsScene = false)
	{
		mScene = scene;
		mOwnsScene = ownsScene;
	}

	public ~this()
	{
		if (mOwnsScene && mScene != null)
			delete mScene;
	}

	// ---- Serialization ----

	protected override SerializationResult OnSerialize(Serializer s)
	{
		if (s.IsWriting)
		{
			if (mScene == null)
				return .InvalidData;

			mScene.Serialize(s);
		}
		else
		{
			// Reading - create component serializers on the new scene before deserializing
			let scene = new Scene();
			for (let proto in mSerializerPrototypes)
				scene.RegisterComponentSerializer(proto.CreateNew());
			scene.Serialize(s);

			mScene = scene;
			mOwnsScene = true;
		}

		return .Ok;
	}

	/// Save this scene resource to a file.
	public Result<void> SaveToFile(StringView path)
	{
		if (mScene == null)
			return .Err;

		let writer = OpenDDLSerializer.CreateWriter();
		defer delete writer;

		Serialize(writer);

		let output = scope String();
		writer.GetOutput(output);

		return File.WriteAllText(path, output);
	}

	/// Load a scene resource from a file.
	public static Result<SceneResource> LoadFromFile(StringView path)
	{
		let text = scope String();
		if (File.ReadAllText(path, text) case .Err)
			return .Err;

		let doc = scope SerializerDataDescription();
		if (doc.ParseText(text) != .Ok)
			return .Err;

		let reader = OpenDDLSerializer.CreateReader(doc);
		defer delete reader;

		let resource = new SceneResource();
		if (resource.Serialize(reader) case .InvalidData)
		{
			delete resource;
			return .Err;
		}

		return .Ok(resource);
	}

	/// Registers a component type for serialization.
	/// Stores a prototype serializer for creating copies during load.
	/// Also registers on the current scene (if any).
	public void RegisterComponentType<T>() where T : struct, ISerializableComponent
	{
		// WORKAROUND: Uses prototype + CreateNew() instead of a lambda calling
		// scene.RegisterComponentSerializer<T>() due to Beef compiler bug with
		// generic constraints in cross-project lambdas.
		// See BeefBugs/GenericLambdaCrossProject/ for repro.
		RegisterComponentSerializer(new ComponentSerializer<T>());
	}

	/// Registers a component serializer prototype directly.
	/// Used by SceneResourceManager to pass pre-created serializer prototypes.
	public void RegisterComponentSerializer(IComponentSerializer serializer)
	{
		mSerializerPrototypes.Add(serializer);
		if (mScene != null)
			mScene.RegisterComponentSerializer(serializer.CreateNew());
	}

	/// Takes the scene from this resource, transferring ownership to the caller.
	/// After this call, Scene returns null and the resource no longer owns it.
	public Scene TakeScene()
	{
		let scene = mScene;
		mScene = null;
		mOwnsScene = false;
		return scene;
	}

	/// Loads a scene resource from a file (instance method).
	/// Register component types before calling this.
	public Result<void> Load(StringView path)
	{
		let text = scope String();
		if (File.ReadAllText(path, text) case .Err)
			return .Err;

		let doc = scope SerializerDataDescription();
		if (doc.ParseText(text) != .Ok)
			return .Err;

		let reader = OpenDDLSerializer.CreateReader(doc);
		defer delete reader;

		if (Serialize(reader) case .InvalidData)
			return .Err;

		return .Ok;
	}

	/// Creates an empty scene resource with the given name.
	public static SceneResource CreateEmpty(StringView name)
	{
		let scene = new Scene(name);
		let resource = new SceneResource(scene, true);
		resource.Name.Set(name);
		return resource;
	}
}
