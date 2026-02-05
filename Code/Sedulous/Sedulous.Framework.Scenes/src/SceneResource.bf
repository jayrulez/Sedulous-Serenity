using System;
using System.IO;
using Sedulous.Resources;
using Sedulous.Serialization;
using Sedulous.Serialization.OpenDDL;
using Sedulous.OpenDDL;

namespace Sedulous.Framework.Scenes;

/// Resource wrapper for a Scene, providing file I/O via OpenDDL serialization.
class SceneResource : Resource
{
	private Scene mScene;
	private bool mOwnsScene;

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
			// Reading
			let scene = new Scene();
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

	/// Creates an empty scene resource with the given name.
	public static SceneResource CreateEmpty(StringView name)
	{
		let scene = new Scene(name);
		let resource = new SceneResource(scene, true);
		resource.Name.Set(name);
		return resource;
	}
}
