using System;
using System.IO;
using Sedulous.Resources;
using Sedulous.Serialization;
using Sedulous.Serialization.OpenDDL;
using Sedulous.OpenDDL;
using System.Collections;

namespace Sedulous.Engine.Scenes;

/// Resource wrapper for a Scene, providing file I/O via OpenDDL serialization.
/// SceneResource is a pure data wrapper — it never owns the Scene.
/// The caller is responsible for Scene lifetime (typically via SceneSubsystem).
/// For full component serialization, the Scene should have modules attached
/// before calling Load or Save.
class SceneResource : Resource
{
	public override ResourceType ResourceType => .("scene");

	private Scene mScene;

	/// Gets or sets the scene to serialize.
	/// SceneResource does not own the scene — caller manages its lifetime.
	public Scene Scene
	{
		get => mScene;
		set => mScene = value;
	}

	public this()
	{
		mScene = null;
	}

	public this(Scene scene)
	{
		mScene = scene;
	}

	// ---- Serialization ----

	protected override SerializationResult OnSerialize(Serializer s)
	{
		if (mScene == null)
			return .InvalidData;

		return mScene.Serialize(s);
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

	/// Loads scene data from a file into the current Scene.
	/// The Scene property must be set before calling this method.
	/// For full component support, the scene should have modules attached.
	public Result<void> Load(StringView path)
	{
		if (mScene == null)
			return .Err;

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
}
