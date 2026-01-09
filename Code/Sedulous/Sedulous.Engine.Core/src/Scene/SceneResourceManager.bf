using System;
using System.IO;
using System.Collections;
using Sedulous.Resources;
using Sedulous.Serialization;
using Sedulous.Serialization.OpenDDL;
using Sedulous.OpenDDL;

namespace Sedulous.Engine.Core;

/// Resource manager for loading and saving scenes.
class SceneResourceManager : ResourceManager<SceneResource>
{
	private ComponentRegistry mComponentRegistry;

	/// Creates a new SceneResourceManager with the given component registry.
	public this(ComponentRegistry componentRegistry)
	{
		mComponentRegistry = componentRegistry;
	}

	protected override Result<SceneResource, ResourceLoadError> LoadFromMemory(MemoryStream memory)
	{
		// Read memory stream to string
		let data = scope List<uint8>((int)memory.Length);
		data.Count = (int)memory.Length;
		memory.Position = 0;
		if (memory.TryRead(data) case .Err)
			return .Err(.ReadError);

		// Convert to string for parsing
		let text = StringView((char8*)data.Ptr, data.Count);

		// Parse the OpenDDL data
		let document = new DataDescription();
		let parseResult = document.ProcessText(text);
		if (parseResult != .Ok)
		{
			delete document;
			return .Err(.InvalidFormat);
		}

		// Create the serializer in read mode
		let serializer = OpenDDLSerializer.CreateReader(document);
		defer delete serializer;
		defer delete document;

		// Create the scene resource
		let resource = new SceneResource();
		resource.CreateScene("Unnamed", mComponentRegistry);

		// Deserialize
		if (resource.Serialize(serializer) != .Ok)
		{
			delete resource;
			return .Err(.InvalidFormat);
		}

		return .Ok(resource);
	}

	public override void Unload(SceneResource resource)
	{
		// Resource cleanup happens via reference counting
	}

	/// Saves a scene to a file.
	public Result<void, ResourceLoadError> SaveToFile(SceneResource resource, StringView path)
	{
		// Create serializer in write mode
		let serializer = OpenDDLSerializer.CreateWriter();
		defer delete serializer;

		// Serialize the scene
		if (resource.Serialize(serializer) != .Ok)
			return .Err(.InvalidFormat);

		// Get the output
		let output = scope String();
		serializer.GetOutput(output);

		// Write to file
		let stream = scope FileStream();
		if (stream.Create(path, .Write) case .Err)
			return .Err(.NotFound);

		if (stream.TryWrite(.((uint8*)output.Ptr, output.Length)) case .Err)
			return .Err(.Unknown);

		return .Ok;
	}

	/// Saves a scene to a string (for debugging/testing).
	public Result<void> SaveToString(SceneResource resource, String output)
	{
		let serializer = OpenDDLSerializer.CreateWriter();
		defer delete serializer;

		if (resource.Serialize(serializer) != .Ok)
			return .Err;

		serializer.GetOutput(output);
		return .Ok;
	}
}
