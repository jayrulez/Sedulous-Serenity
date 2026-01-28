using System;
using System.IO;
using System.Collections;
using Sedulous.Resources;
using Sedulous.Materials;
using Sedulous.Mathematics;
using Sedulous.Serialization;
using Sedulous.Serialization.OpenDDL;
using Sedulous.OpenDDL;

namespace Sedulous.Materials.Resources;

/// CPU-side material resource for serialization.
/// Wraps a Material and can save/load it.
class MaterialResource : Resource
{
	public const int32 FileVersion = 1;
	public const int32 FileType = 6;

	private Material mMaterial;
	private bool mOwnsMaterial;

	/// Texture paths (slot name -> path).
	/// At runtime, these paths are resolved to actual textures.
	public Dictionary<String, String> TexturePaths = new .() ~ DeleteDictionaryAndKeysAndValues!(_);

	/// The wrapped material.
	public Material Material => mMaterial;

	public this()
	{
		mMaterial = null;
		mOwnsMaterial = false;
	}

	public this(Material material, bool ownsMaterial = false)
	{
		mMaterial = material;
		mOwnsMaterial = ownsMaterial;
	}

	public ~this()
	{
		if (mOwnsMaterial && mMaterial != null)
			delete mMaterial;
	}

	/// Sets the material. Takes ownership if ownsMaterial is true.
	public void SetMaterial(Material material, bool ownsMaterial = false)
	{
		if (mOwnsMaterial && mMaterial != null)
			delete mMaterial;
		mMaterial = material;
		mOwnsMaterial = ownsMaterial;
	}

	/// Sets a texture path for a slot.
	public void SetTexturePath(StringView slot, StringView path)
	{
		let slotKey = scope String(slot);
		if (TexturePaths.TryGetValue(slotKey, let existing))
			existing.Set(path);
		else
			TexturePaths[new String(slot)] = new String(path);
	}

	/// Gets a texture path for a slot.
	public StringView GetTexturePath(StringView slot)
	{
		if (TexturePaths.TryGetValue(scope String(slot), let path))
			return path;
		return "";
	}

	// ---- Serialization ----

	public override int32 SerializationVersion => FileVersion;

	protected override SerializationResult OnSerialize(Serializer s)
	{
		if (s.IsWriting)
		{
			if (mMaterial == null)
				return .InvalidData;

			// Write material name and shader
			s.String("materialName", mMaterial.Name);
			s.String("shaderName", mMaterial.ShaderName);

			// Write shader flags
			int32 shaderFlags = (int32)mMaterial.ShaderFlags;
			s.Int32("shaderFlags", ref shaderFlags);

			// Write pipeline config (material-relevant fields only)
			int32 blendMode = (int32)mMaterial.PipelineConfig.BlendMode;
			int32 depthMode = (int32)mMaterial.PipelineConfig.DepthMode;
			int32 cullMode = (int32)mMaterial.PipelineConfig.CullMode;
			s.Int32("blendMode", ref blendMode);
			s.Int32("depthMode", ref depthMode);
			s.Int32("cullMode", ref cullMode);

			// Write property definitions
			int32 propCount = (int32)mMaterial.PropertyCount;
			s.Int32("propertyCount", ref propCount);

			for (int32 i = 0; i < propCount; i++)
			{
				let prop = mMaterial.GetProperty(i);
				s.BeginObject(scope $"prop{i}");

				String propName = scope String(prop.Name);
				s.String("name", propName);

				int32 propType = (int32)prop.Type;
				s.Int32("type", ref propType);

				uint32 binding = prop.Binding;
				uint32 offset = prop.Offset;
				uint32 size = prop.Size;
				s.UInt32("binding", ref binding);
				s.UInt32("offset", ref offset);
				s.UInt32("size", ref size);

				s.EndObject();
			}

			// Write uniform data
			let uniformData = mMaterial.DefaultUniformData;
			int32 uniformSize = (int32)uniformData.Length;
			s.Int32("uniformSize", ref uniformSize);

			if (uniformSize > 0)
			{
				let floatCount = uniformSize / 4;
				s.FixedFloatArray("uniformData", (float*)uniformData.Ptr, (int32)floatCount);
			}

			// Write texture paths
			int32 texCount = (int32)TexturePaths.Count;
			s.Int32("textureCount", ref texCount);

			int32 idx = 0;
			for (let kv in TexturePaths)
			{
				s.BeginObject(scope $"tex{idx}");
				String slot = scope String(kv.key);
				String path = scope String(kv.value);
				s.String("slot", slot);
				s.String("path", path);
				s.EndObject();
				idx++;
			}
		}
		else
		{
			// Read material name and shader
			String materialName = scope String();
			String shaderName = scope String();
			s.String("materialName", materialName);
			s.String("shaderName", shaderName);

			// Read shader flags
			int32 shaderFlags = 0;
			s.Int32("shaderFlags", ref shaderFlags);

			// Read pipeline config
			int32 blendMode = 0, depthMode = 0, cullMode = 0;
			s.Int32("blendMode", ref blendMode);
			s.Int32("depthMode", ref depthMode);
			s.Int32("cullMode", ref cullMode);

			// Create material
			let mat = new Material();
			mat.Name.Set(materialName);
			mat.ShaderName.Set(shaderName);
			mat.ShaderFlags = (.)shaderFlags;
			mat.PipelineConfig.BlendMode = (.)blendMode;
			mat.PipelineConfig.DepthMode = (.)depthMode;
			mat.PipelineConfig.CullMode = (.)cullMode;

			// Read property definitions
			int32 propCount = 0;
			s.Int32("propertyCount", ref propCount);

			for (int32 i = 0; i < propCount; i++)
			{
				s.BeginObject(scope $"prop{i}");

				String propName = scope String();
				s.String("name", propName);

				int32 propType = 0;
				s.Int32("type", ref propType);

				uint32 binding = 0, offset = 0, size = 0;
				s.UInt32("binding", ref binding);
				s.UInt32("offset", ref offset);
				s.UInt32("size", ref size);

				mat.AddProperty(.(propName, (MaterialPropertyType)propType, binding, offset, size));

				s.EndObject();
			}

			// Read uniform data
			int32 uniformSize = 0;
			s.Int32("uniformSize", ref uniformSize);

			if (uniformSize > 0)
			{
				mat.AllocateDefaultUniformData();
				let floatCount = uniformSize / 4;
				s.FixedFloatArray("uniformData", (float*)mat.DefaultUniformData.Ptr, (int32)floatCount);
			}

			SetMaterial(mat, true);

			// Read texture paths
			int32 texCount = 0;
			s.Int32("textureCount", ref texCount);

			for (int32 i = 0; i < texCount; i++)
			{
				s.BeginObject(scope $"tex{i}");
				String slot = scope String();
				String path = scope String();
				s.String("slot", slot);
				s.String("path", path);
				TexturePaths[new String(slot)] = new String(path);
				s.EndObject();
			}
		}

		return .Ok;
	}

	/// Save to file.
	public Result<void> SaveToFile(StringView path)
	{
		if (mMaterial == null)
			return .Err;

		let writer = OpenDDLSerializer.CreateWriter();
		defer delete writer;

		int32 version = FileVersion;
		writer.Int32("version", ref version);

		int32 fileType = FileType;
		writer.Int32("fileType", ref fileType);

		Serialize(writer);

		let output = scope String();
		writer.GetOutput(output);

		return File.WriteAllText(path, output);
	}

	/// Load from file.
	public static Result<MaterialResource> LoadFromFile(StringView path)
	{
		let text = scope String();
		if (File.ReadAllText(path, text) case .Err)
			return .Err;

		let doc = scope SerializerDataDescription();
		if (doc.ParseText(text) != .Ok)
			return .Err;

		let reader = OpenDDLSerializer.CreateReader(doc);
		defer delete reader;

		int32 version = 0;
		reader.Int32("version", ref version);
		if (version > FileVersion)
			return .Err;

		int32 fileType = 0;
		reader.Int32("fileType", ref fileType);
		if (fileType != FileType)
			return .Err;

		let resource = new MaterialResource();
		resource.Serialize(reader);

		return .Ok(resource);
	}
}
