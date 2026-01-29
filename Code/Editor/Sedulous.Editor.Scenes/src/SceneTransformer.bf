namespace Sedulous.Editor.Scenes;

using System;
using System.IO;
using System.Collections;
using Sedulous.Editor.Core;
using Sedulous.Resources;
using Sedulous.Serialization;

/// Transforms SceneAsset to runtime SceneResource.
class SceneTransformer : IAssetTransformer
{
	public StringView SourceAssetType => "scene";
	public StringView TargetResourceType => "SceneResource";

	public Result<IResource> Transform(IAsset asset, TransformContext context)
	{
		let sceneAsset = asset as SceneAsset;
		if (sceneAsset == null)
		{
			context.ReportError("Invalid asset type - expected SceneAsset");
			return .Err;
		}

		context.ReportProgress(0.0f, "Creating scene resource...");

		// Create the runtime scene resource
		let resource = new RuntimeSceneResource();
		resource.Name.Set(sceneAsset.SceneName);
		resource.Id = sceneAsset.AssetId;

		// Copy scene settings
		resource.Settings = sceneAsset.Settings;

		context.ReportProgress(0.3f, "Converting entities...");

		// Convert entities
		for (let entityData in sceneAsset.Entities)
		{
			let runtimeEntity = new RuntimeEntityData();
			ConvertEntity(entityData, runtimeEntity);
			resource.Entities.Add(runtimeEntity);
		}

		context.ReportProgress(1.0f, "Scene conversion complete");
		return resource;
	}

	private void ConvertEntity(EntityData source, RuntimeEntityData dest)
	{
		dest.Name.Set(source.Name);
		dest.EntityId = source.EntityId;
		dest.ParentId = source.ParentId;
		dest.Position = source.Position;
		dest.Rotation = source.Rotation;
		dest.Scale = source.Scale;

		// Convert components
		for (let componentData in source.Components)
		{
			let runtimeComponent = new RuntimeComponentData();
			runtimeComponent.TypeName.Set(componentData.TypeName);

			// Copy properties
			for (let kv in componentData.Properties)
			{
				let keyCopy = new String(kv.key);
				let valCopy = new String(kv.value);
				runtimeComponent.Properties[keyCopy] = valCopy;
			}

			dest.Components.Add(runtimeComponent);
		}

		// Copy child IDs
		for (let childId in source.ChildIds)
			dest.ChildIds.Add(childId);
	}

	public void GetOutputPath(IAsset asset, String outPath, TransformContext context)
	{
		// Build output path: OutputRoot/scenes/assetname.scene.bin
		outPath.Clear();
		outPath.Append(context.OutputRoot);
		if (!outPath.EndsWith("/") && !outPath.EndsWith("\\"))
			outPath.Append("/");
		outPath.Append("scenes/");

		// Get asset name without extension
		let name = asset.Name;
		outPath.Append(name);
		outPath.Append(".scene.bin");
	}

	public void Dispose()
	{
	}
}

/// Runtime scene resource that can be serialized/loaded.
class RuntimeSceneResource : Resource
{
	/// Scene settings.
	public SceneSettings Settings;

	/// Entities in the scene.
	public List<RuntimeEntityData> Entities = new .() ~ DeleteContainerAndItems!(_);

	public override int32 SerializationVersion => 1;

	protected override SerializationResult OnSerialize(Serializer s)
	{
		// Serialize settings
		var result = SerializeSettings(s);
		if (result != .Ok)
			return result;

		// Serialize entities
		int32 entityCount = (int32)Entities.Count;
		result = s.BeginArray("entities", ref entityCount);
		if (result != .Ok)
			return result;

		if (s.IsWriting)
		{
			for (let entity in Entities)
			{
				result = SerializeEntity(s, entity);
				if (result != .Ok)
					return result;
			}
		}
		else
		{
			Entities.ClearAndDeleteItems();
			for (int i = 0; i < entityCount; i++)
			{
				let entity = new RuntimeEntityData();
				result = SerializeEntity(s, entity);
				if (result != .Ok)
				{
					delete entity;
					return result;
				}
				Entities.Add(entity);
			}
		}

		return s.EndArray();
	}

	private SerializationResult SerializeSettings(Serializer s)
	{
		var result = s.BeginObject("settings");
		if (result != .Ok)
			return result;

		// Ambient color
		float[4] ambient = .(
			Settings.AmbientColor.R / 255.0f,
			Settings.AmbientColor.G / 255.0f,
			Settings.AmbientColor.B / 255.0f,
			Settings.AmbientColor.A / 255.0f
		);
		result = s.FixedFloatArray("ambientColor", &ambient, 4);
		if (result != .Ok)
			return result;

		if (s.IsReading)
			Settings.AmbientColor = .(ambient[0], ambient[1], ambient[2], ambient[3]);

		// Fog settings
		var fogEnabled = Settings.FogEnabled;
		result = s.Bool("fogEnabled", ref fogEnabled);
		if (result != .Ok)
			return result;
		Settings.FogEnabled = fogEnabled;

		float[4] fogColor = .(
			Settings.FogColor.R / 255.0f,
			Settings.FogColor.G / 255.0f,
			Settings.FogColor.B / 255.0f,
			Settings.FogColor.A / 255.0f
		);
		result = s.FixedFloatArray("fogColor", &fogColor, 4);
		if (result != .Ok)
			return result;

		if (s.IsReading)
			Settings.FogColor = .(fogColor[0], fogColor[1], fogColor[2], fogColor[3]);

		var fogDensity = Settings.FogDensity;
		result = s.Float("fogDensity", ref fogDensity);
		if (result != .Ok)
			return result;
		Settings.FogDensity = fogDensity;

		return s.EndObject();
	}

	private SerializationResult SerializeEntity(Serializer s, RuntimeEntityData entity)
	{
		var result = s.BeginObject(default);
		if (result != .Ok)
			return result;

		// Name
		result = s.String("name", entity.Name);
		if (result != .Ok)
			return result;

		// Entity ID
		let idStr = scope String();
		if (s.IsWriting)
			entity.EntityId.ToString(idStr);
		result = s.String("id", idStr);
		if (result != .Ok)
			return result;
		if (s.IsReading)
		{
			if (Guid.Parse(idStr) case .Ok(let guid))
				entity.EntityId = guid;
		}

		// Parent ID
		let parentStr = scope String();
		if (s.IsWriting && entity.ParentId != default)
			entity.ParentId.ToString(parentStr);
		result = s.String("parentId", parentStr);
		if (result != .Ok)
			return result;
		if (s.IsReading && !parentStr.IsEmpty)
		{
			if (Guid.Parse(parentStr) case .Ok(let guid))
				entity.ParentId = guid;
		}

		// Transform
		float[3] pos = .(entity.Position.X, entity.Position.Y, entity.Position.Z);
		result = s.FixedFloatArray("position", &pos, 3);
		if (result != .Ok)
			return result;
		if (s.IsReading)
			entity.Position = .(pos[0], pos[1], pos[2]);

		float[3] rot = .(entity.Rotation.X, entity.Rotation.Y, entity.Rotation.Z);
		result = s.FixedFloatArray("rotation", &rot, 3);
		if (result != .Ok)
			return result;
		if (s.IsReading)
			entity.Rotation = .(rot[0], rot[1], rot[2]);

		float[3] scale = .(entity.Scale.X, entity.Scale.Y, entity.Scale.Z);
		result = s.FixedFloatArray("scale", &scale, 3);
		if (result != .Ok)
			return result;
		if (s.IsReading)
			entity.Scale = .(scale[0], scale[1], scale[2]);

		// Components
		int32 componentCount = (int32)entity.Components.Count;
		result = s.BeginArray("components", ref componentCount);
		if (result != .Ok)
			return result;

		if (s.IsWriting)
		{
			for (let component in entity.Components)
			{
				result = SerializeComponent(s, component);
				if (result != .Ok)
					return result;
			}
		}
		else
		{
			entity.Components.ClearAndDeleteItems();
			for (int i = 0; i < componentCount; i++)
			{
				let component = new RuntimeComponentData();
				result = SerializeComponent(s, component);
				if (result != .Ok)
				{
					delete component;
					return result;
				}
				entity.Components.Add(component);
			}
		}

		result = s.EndArray();
		if (result != .Ok)
			return result;

		// Child IDs
		int32 childCount = (int32)entity.ChildIds.Count;
		result = s.BeginArray("childIds", ref childCount);
		if (result != .Ok)
			return result;

		if (s.IsWriting)
		{
			for (let childId in entity.ChildIds)
			{
				let childStr = scope String();
				childId.ToString(childStr);
				result = s.String(default, childStr);
				if (result != .Ok)
					return result;
			}
		}
		else
		{
			entity.ChildIds.Clear();
			for (int i = 0; i < childCount; i++)
			{
				let childStr = scope String();
				result = s.String(default, childStr);
				if (result != .Ok)
					return result;
				if (Guid.Parse(childStr) case .Ok(let guid))
					entity.ChildIds.Add(guid);
			}
		}

		result = s.EndArray();
		if (result != .Ok)
			return result;

		return s.EndObject();
	}

	private SerializationResult SerializeComponent(Serializer s, RuntimeComponentData component)
	{
		var result = s.BeginObject(default);
		if (result != .Ok)
			return result;

		// Type name
		result = s.String("type", component.TypeName);
		if (result != .Ok)
			return result;

		// Properties as key-value pairs
		int32 propCount = (int32)component.Properties.Count;
		result = s.BeginArray("properties", ref propCount);
		if (result != .Ok)
			return result;

		if (s.IsWriting)
		{
			for (let kv in component.Properties)
			{
				result = s.BeginObject(default);
				if (result != .Ok)
					return result;

				result = s.String("key", scope String(kv.key));
				if (result != .Ok)
					return result;

				result = s.String("value", scope String(kv.value));
				if (result != .Ok)
					return result;

				result = s.EndObject();
				if (result != .Ok)
					return result;
			}
		}
		else
		{
			for (let kv in component.Properties)
			{
				delete kv.key;
				delete kv.value;
			}
			component.Properties.Clear();

			for (int i = 0; i < propCount; i++)
			{
				result = s.BeginObject(default);
				if (result != .Ok)
					return result;

				let key = new String();
				result = s.String("key", key);
				if (result != .Ok)
				{
					delete key;
					return result;
				}

				let val = new String();
				result = s.String("value", val);
				if (result != .Ok)
				{
					delete key;
					delete val;
					return result;
				}

				component.Properties[key] = val;

				result = s.EndObject();
				if (result != .Ok)
					return result;
			}
		}

		result = s.EndArray();
		if (result != .Ok)
			return result;

		return s.EndObject();
	}
}

/// Runtime entity data (serializable).
class RuntimeEntityData
{
	public String Name = new .() ~ delete _;
	public Guid EntityId;
	public Guid ParentId;
	public Sedulous.Mathematics.Vector3 Position;
	public Sedulous.Mathematics.Vector3 Rotation;
	public Sedulous.Mathematics.Vector3 Scale = .(1, 1, 1);
	public List<RuntimeComponentData> Components = new .() ~ DeleteContainerAndItems!(_);
	public List<Guid> ChildIds = new .() ~ delete _;
}

/// Runtime component data (serializable).
class RuntimeComponentData
{
	public String TypeName = new .() ~ delete _;
	public Dictionary<String, String> Properties = new .() ~ DeleteDictionaryAndValues!(_);
}
