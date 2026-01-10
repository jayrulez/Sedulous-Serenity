using System;
using System.IO;
using System.Collections;
using Sedulous.Resources;
using Sedulous.Mathematics;
using Sedulous.Serialization;
using Sedulous.Serialization.OpenDDL;
using Sedulous.OpenDDL;

namespace Sedulous.Renderer.Resources;

/// Material types supported by the renderer.
enum MaterialType
{
	/// Custom material with user-defined shader.
	Custom,
	/// PBR metallic-roughness workflow.
	PBR,
	/// Unlit material (no lighting calculations).
	Unlit,
	/// Phong/Blinn-Phong lighting.
	Phong,
	/// Toon/cel-shading.
	Toon
}

/// Alpha blending mode for materials.
enum MaterialAlphaMode
{
	Opaque,
	Mask,
	Blend
}

/// A material parameter value (stored as variant).
struct MaterialParameter
{
	public enum ValueType { None, Float, Float2, Float3, Float4, Int, Matrix4x4 }

	public ValueType Type;
	public float[16] Data; // Enough for Matrix4x4

	public static MaterialParameter Float(float v)
	{
		Self p = .();
		p.Type = .Float;
		p.Data[0] = v;
		return p;
	}

	public static MaterialParameter Float2(Vector2 v)
	{
		Self p = .();
		p.Type = .Float2;
		p.Data[0] = v.X;
		p.Data[1] = v.Y;
		return p;
	}

	public static MaterialParameter Float3(Vector3 v)
	{
		Self p = .();
		p.Type = .Float3;
		p.Data[0] = v.X;
		p.Data[1] = v.Y;
		p.Data[2] = v.Z;
		return p;
	}

	public static MaterialParameter Float4(Vector4 v)
	{
		Self p = .();
		p.Type = .Float4;
		p.Data[0] = v.X;
		p.Data[1] = v.Y;
		p.Data[2] = v.Z;
		p.Data[3] = v.W;
		return p;
	}

	public static MaterialParameter Color(Vector4 color) => Float4(color);

	public float AsFloat() => Data[0];
	public Vector2 AsFloat2() => .(Data[0], Data[1]);
	public Vector3 AsFloat3() => .(Data[0], Data[1], Data[2]);
	public Vector4 AsFloat4() => .(Data[0], Data[1], Data[2], Data[3]);
}

/// CPU-side material resource for serialization and editing.
/// Can be used to create Material and MaterialInstance at runtime.
class MaterialResource : Resource
{
	public const int32 FileVersion = 1;
	public const int32 FileType = 6; // ResourceFileType.Material

	/// Material type (PBR, Unlit, etc.)
	public MaterialType Type = .PBR;

	/// Custom shader name (for Custom type).
	public String ShaderName = new .() ~ delete _;

	/// Rendering properties
	public MaterialAlphaMode AlphaMode = .Opaque;
	public float AlphaCutoff = 0.5f;
	public bool DoubleSided = false;
	public bool CastShadows = true;
	public bool ReceiveShadows = true;

	/// Render queue priority (lower = rendered first).
	public int32 RenderQueue = 0;

	/// Scalar/vector parameters (name -> value).
	public Dictionary<String, MaterialParameter> Parameters = new .() ~ DeleteDictionaryAndKeys!(_);

	/// Texture paths (slot name -> path).
	public Dictionary<String, String> Textures = new .() ~ DeleteDictionaryAndKeysAndValues!(_);

	public this()
	{
	}

	public this(MaterialType type)
	{
		Type = type;
		SetupDefaults();
	}

	/// Sets up default parameters for the material type.
	public void SetupDefaults()
	{
		Parameters.Clear();
		Textures.Clear();

		switch (Type)
		{
		case .PBR:
			// Parameter names match Material.CreatePBR() exactly
			SetFloat4("baseColor", .(1, 1, 1, 1));
			SetFloat("metallic", 0.0f);
			SetFloat("roughness", 0.5f);
			SetFloat("ao", 1.0f);
			SetFloat4("emissive", .(0, 0, 0, 1));

		case .Unlit:
			SetFloat4("color", .(1, 1, 1, 1));

		case .Phong:
			SetFloat4("diffuseColor", .(1, 1, 1, 1));
			SetFloat4("specularColor", .(1, 1, 1, 1));
			SetFloat("shininess", 32.0f);

		case .Toon:
			SetFloat4("color", .(1, 1, 1, 1));
			SetFloat("levels", 3.0f);
			SetFloat("outlineWidth", 0.02f);
			SetFloat4("outlineColor", .(0, 0, 0, 1));

		case .Custom:
			// No defaults for custom
			break;
		}
	}

	// ---- Parameter setters ----

	public void SetFloat(StringView name, float value)
	{
		let key = new String(name);
		if (Parameters.TryAdd(key, .Float(value)))
			return;
		delete key;
		Parameters[scope String(name)] = .Float(value);
	}

	public void SetFloat2(StringView name, Vector2 value)
	{
		let key = new String(name);
		if (Parameters.TryAdd(key, .Float2(value)))
			return;
		delete key;
		Parameters[scope String(name)] = .Float2(value);
	}

	public void SetFloat3(StringView name, Vector3 value)
	{
		let key = new String(name);
		if (Parameters.TryAdd(key, .Float3(value)))
			return;
		delete key;
		Parameters[scope String(name)] = .Float3(value);
	}

	public void SetFloat4(StringView name, Vector4 value)
	{
		let key = new String(name);
		if (Parameters.TryAdd(key, .Float4(value)))
			return;
		delete key;
		Parameters[scope String(name)] = .Float4(value);
	}

	public void SetColor(StringView name, Vector4 color) => SetFloat4(name, color);

	// ---- Parameter getters ----

	public float GetFloat(StringView name, float defaultValue = 0)
	{
		if (Parameters.TryGetValue(scope String(name), let param))
			return param.AsFloat();
		return defaultValue;
	}

	public Vector2 GetFloat2(StringView name, Vector2 defaultValue = .Zero)
	{
		if (Parameters.TryGetValue(scope String(name), let param))
			return param.AsFloat2();
		return defaultValue;
	}

	public Vector3 GetFloat3(StringView name, Vector3 defaultValue = .Zero)
	{
		if (Parameters.TryGetValue(scope String(name), let param))
			return param.AsFloat3();
		return defaultValue;
	}

	public Vector4 GetFloat4(StringView name, Vector4 defaultValue = .Zero)
	{
		if (Parameters.TryGetValue(scope String(name), let param))
			return param.AsFloat4();
		return defaultValue;
	}

	// ---- Texture management ----

	public void SetTexture(StringView slot, StringView path)
	{
		let slotKey = scope String(slot);
		if (Textures.TryGetValue(slotKey, let existing))
		{
			existing.Set(path);
		}
		else
		{
			Textures[new String(slot)] = new String(path);
		}
	}

	public StringView GetTexture(StringView slot)
	{
		if (Textures.TryGetValue(scope String(slot), let path))
			return path;
		return "";
	}

	public bool HasTexture(StringView slot)
	{
		if (Textures.TryGetValue(scope String(slot), let path))
			return !path.IsEmpty;
		return false;
	}

	// ---- PBR convenience accessors ----

	public Vector4 BaseColor
	{
		get => GetFloat4("baseColor", .(1, 1, 1, 1));
		set => SetFloat4("baseColor", value);
	}

	public float Metallic
	{
		get => GetFloat("metallic", 0);
		set => SetFloat("metallic", value);
	}

	public float Roughness
	{
		get => GetFloat("roughness", 0.5f);
		set => SetFloat("roughness", value);
	}

	public float AO
	{
		get => GetFloat("ao", 1.0f);
		set => SetFloat("ao", value);
	}

	public Vector4 Emissive
	{
		get => GetFloat4("emissive", .(0, 0, 0, 1));
		set => SetFloat4("emissive", value);
	}

	/// Convenience setter for emissive from RGB color.
	public Vector3 EmissiveFactor
	{
		get
		{
			let v = GetFloat4("emissive", .Zero);
			return .(v.X, v.Y, v.Z);
		}
		set => SetFloat4("emissive", .(value.X, value.Y, value.Z, 1.0f));
	}

	// ---- Unlit convenience accessor ----

	public Vector4 Color
	{
		get => GetFloat4("color", .(1, 1, 1, 1));
		set => SetFloat4("color", value);
	}

	// ---- Factory methods ----

	/// Creates a default PBR material (white, non-metallic).
	public static MaterialResource CreateDefault(StringView name = "Default Material")
	{
		let mat = new MaterialResource(.PBR);
		mat.Name.Set(name);
		mat.BaseColor = .(1, 1, 1, 1);
		mat.Metallic = 0.0f;
		mat.Roughness = 0.5f;
		return mat;
	}

	/// Creates a default PBR material.
	public static MaterialResource CreatePBR(StringView name = "PBR Material")
	{
		let mat = new MaterialResource(.PBR);
		mat.Name.Set(name);
		return mat;
	}

	/// Creates an unlit material.
	public static MaterialResource CreateUnlit(StringView name = "Unlit Material")
	{
		let mat = new MaterialResource(.Unlit);
		mat.Name.Set(name);
		return mat;
	}

	/// Creates a PBR metallic material.
	public static MaterialResource CreateMetallic(StringView name, Vector4 color, float roughness = 0.3f)
	{
		let mat = new MaterialResource(.PBR);
		mat.Name.Set(name);
		mat.BaseColor = color;
		mat.Metallic = 1.0f;
		mat.Roughness = roughness;
		return mat;
	}

	/// Creates a PBR dielectric material.
	public static MaterialResource CreateDielectric(StringView name, Vector4 color, float roughness = 0.5f)
	{
		let mat = new MaterialResource(.PBR);
		mat.Name.Set(name);
		mat.BaseColor = color;
		mat.Metallic = 0.0f;
		mat.Roughness = roughness;
		return mat;
	}

	/// Creates an emissive PBR material.
	public static MaterialResource CreateEmissive(StringView name, Vector3 emissiveColor, float strength = 1.0f)
	{
		let mat = new MaterialResource(.PBR);
		mat.Name.Set(name);
		mat.BaseColor = .(0, 0, 0, 1);
		mat.Metallic = 0.0f;
		mat.Roughness = 0.5f;
		// Bake strength into emissive color
		mat.Emissive = .(emissiveColor.X * strength, emissiveColor.Y * strength, emissiveColor.Z * strength, 1.0f);
		return mat;
	}

	/// Creates a clone of this material.
	public MaterialResource Clone(StringView newName = default)
	{
		let clone = new MaterialResource();
		clone.Type = Type;
		clone.ShaderName.Set(ShaderName);
		clone.AlphaMode = AlphaMode;
		clone.AlphaCutoff = AlphaCutoff;
		clone.DoubleSided = DoubleSided;
		clone.CastShadows = CastShadows;
		clone.ReceiveShadows = ReceiveShadows;
		clone.RenderQueue = RenderQueue;

		for (let kv in Parameters)
			clone.Parameters[new String(kv.key)] = kv.value;

		for (let kv in Textures)
			clone.Textures[new String(kv.key)] = new String(kv.value);

		if (!newName.IsEmpty)
			clone.Name.Set(newName);
		else
			clone.Name.Set(Name);

		return clone;
	}

	// ---- Serialization ----

	public override int32 SerializationVersion => 1;

	protected override SerializationResult OnSerialize(Serializer s)
	{
		// Material type
		int32 typeInt = (int32)Type;
		s.Int32("type", ref typeInt);
		if (s.IsReading)
			Type = (MaterialType)typeInt;

		s.String("shaderName", ShaderName);

		// Rendering properties
		int32 alphaModeInt = (int32)AlphaMode;
		s.Int32("alphaMode", ref alphaModeInt);
		if (s.IsReading)
			AlphaMode = (MaterialAlphaMode)alphaModeInt;

		s.Float("alphaCutoff", ref AlphaCutoff);
		s.Bool("doubleSided", ref DoubleSided);
		s.Bool("castShadows", ref CastShadows);
		s.Bool("receiveShadows", ref ReceiveShadows);
		s.Int32("renderQueue", ref RenderQueue);

		// Parameters
		int32 paramCount = (int32)Parameters.Count;
		s.Int32("paramCount", ref paramCount);

		if (s.IsWriting)
		{
			int32 idx = 0;
			for (let kv in Parameters)
			{
				s.BeginObject(scope $"param{idx}");
				String paramName = scope String(kv.key);
				s.String("name", paramName);

				int32 valueType = (int32)kv.value.Type;
				s.Int32("valueType", ref valueType);

				int32 dataCount = GetDataCount(kv.value.Type);
				float[16] data = kv.value.Data;
				s.FixedFloatArray("data", &data[0], dataCount);

				s.EndObject();
				idx++;
			}
		}
		else
		{
			for (int32 i = 0; i < paramCount; i++)
			{
				s.BeginObject(scope $"param{i}");

				String paramName = scope String();
				s.String("name", paramName);

				int32 valueType = 0;
				s.Int32("valueType", ref valueType);

				MaterialParameter param = .();
				param.Type = (MaterialParameter.ValueType)valueType;

				int32 dataCount = GetDataCount(param.Type);
				s.FixedFloatArray("data", &param.Data[0], dataCount);

				Parameters[new String(paramName)] = param;

				s.EndObject();
			}
		}

		// Textures
		int32 texCount = (int32)Textures.Count;
		s.Int32("textureCount", ref texCount);

		if (s.IsWriting)
		{
			int32 idx = 0;
			for (let kv in Textures)
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
			for (int32 i = 0; i < texCount; i++)
			{
				s.BeginObject(scope $"tex{i}");

				String slot = scope String();
				String path = scope String();
				s.String("slot", slot);
				s.String("path", path);

				Textures[new String(slot)] = new String(path);

				s.EndObject();
			}
		}

		return .Ok;
	}

	private static int32 GetDataCount(MaterialParameter.ValueType type)
	{
		switch (type)
		{
		case .None: return 0;
		case .Float: return 1;
		case .Float2: return 2;
		case .Float3: return 3;
		case .Float4: return 4;
		case .Int: return 1;
		case .Matrix4x4: return 16;
		}
	}

	/// Creates a Material (GPU-side template) from this resource.
	public Material CreateMaterial()
	{
		String shaderName = scope String();
		switch (Type)
		{
		case .PBR: shaderName.Set("pbr");
		case .Unlit: shaderName.Set("unlit");
		case .Phong: shaderName.Set("phong");
		case .Toon: shaderName.Set("toon");
		case .Custom: shaderName.Set(ShaderName);
		}

		let mat = new Material(Name, shaderName);

		// Set blend mode based on alpha mode
		switch (AlphaMode)
		{
		case .Opaque:
			mat.BlendMode = .Opaque;
			mat.DepthMode = .ReadWrite;
		case .Mask:
			mat.BlendMode = .Opaque;
			mat.DepthMode = .ReadWrite;
		case .Blend:
			mat.BlendMode = .AlphaBlend;
			mat.DepthMode = .ReadOnly;
		}

		mat.CullMode = DoubleSided ? .None : .Back;
		mat.CastShadows = CastShadows;
		mat.ReceiveShadows = ReceiveShadows;
		mat.RenderQueue = RenderQueue;

		return mat;
	}

	/// Save this material resource to a file.
	public Result<void> SaveToFile(StringView path)
	{
		let writer = OpenDDLSerializer.CreateWriter();
		defer delete writer;

		int32 version = FileVersion;
		writer.Int32("version", ref version);

		int32 fileType = FileType;
		writer.Int32("type", ref fileType);

		Serialize(writer);

		let output = scope String();
		writer.GetOutput(output);

		return File.WriteAllText(path, output);
	}

	/// Load a material resource from a file.
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
		reader.Int32("type", ref fileType);
		if (fileType != FileType)
			return .Err;

		let resource = new MaterialResource();
		resource.Serialize(reader);

		return .Ok(resource);
	}
}
