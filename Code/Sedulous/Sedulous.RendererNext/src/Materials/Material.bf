namespace Sedulous.RendererNext;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Shaders;

/// Type of material parameter.
enum MaterialParameterType : uint8
{
	Float,
	Float2,
	Float3,
	Float4,
	Int,
	Int2,
	Int3,
	Int4,
	Matrix4x4,
	Texture2D,
	TextureCube,
	Sampler
}

/// Describes a material parameter.
class MaterialParameterDesc
{
	public String Name ~ delete _;
	public MaterialParameterType Type;
	public uint32 Binding;
	public uint32 Offset;   // Offset in uniform buffer (for scalar params)

	public this(StringView name, MaterialParameterType type, uint32 binding, uint32 offset = 0)
	{
		Name = new String(name);
		Type = type;
		Binding = binding;
		Offset = offset;
	}
}

/// A material defines how geometry should be rendered.
/// Contains shader reference, render state, and parameter declarations.
class Material
{
	/// Material name for debugging.
	public String Name ~ delete _;

	/// Shader name (looked up in ShaderLibrary).
	public String ShaderName ~ delete _;

	/// Shader variant flags.
	public ShaderFlags ShaderFlags = .None;

	/// Blend mode.
	public BlendMode BlendMode = .Opaque;

	/// Depth configuration.
	public DepthConfig DepthConfig = .Default;

	/// Face culling mode.
	public CullMode CullMode = .Back;

	/// Whether this material casts shadows.
	public bool CastShadows = true;

	/// Render queue priority (lower = rendered first).
	/// Opaques: 0-999, AlphaTest: 1000-1999, Transparent: 2000+
	public int32 RenderQueue = 0;

	/// Parameter declarations.
	public List<MaterialParameterDesc> Parameters = new .() ~ DeleteContainerAndItems!(_);

	/// Size of the material uniform buffer in bytes.
	public uint32 UniformBufferSize = 0;

	/// Uniform buffer binding slot.
	public uint32 UniformBufferBinding = 1;

	public this(StringView name, StringView shaderName)
	{
		Name = new String(name);
		ShaderName = new String(shaderName);
	}

	/// Adds a float parameter.
	public void AddFloatParam(StringView name, uint32 offset)
	{
		Parameters.Add(new .(name, .Float, UniformBufferBinding, offset));
	}

	/// Adds a float2 parameter.
	public void AddFloat2Param(StringView name, uint32 offset)
	{
		Parameters.Add(new .(name, .Float2, UniformBufferBinding, offset));
	}

	/// Adds a float3 parameter.
	public void AddFloat3Param(StringView name, uint32 offset)
	{
		Parameters.Add(new .(name, .Float3, UniformBufferBinding, offset));
	}

	/// Adds a float4/color parameter.
	public void AddFloat4Param(StringView name, uint32 offset)
	{
		Parameters.Add(new .(name, .Float4, UniformBufferBinding, offset));
	}

	/// Adds a matrix parameter.
	public void AddMatrixParam(StringView name, uint32 offset)
	{
		Parameters.Add(new .(name, .Matrix4x4, UniformBufferBinding, offset));
	}

	/// Adds a texture parameter.
	public void AddTextureParam(StringView name, uint32 binding)
	{
		Parameters.Add(new .(name, .Texture2D, binding, 0));
	}

	/// Adds a cube texture parameter.
	public void AddTextureCubeParam(StringView name, uint32 binding)
	{
		Parameters.Add(new .(name, .TextureCube, binding, 0));
	}

	/// Adds a sampler parameter.
	public void AddSamplerParam(StringView name, uint32 binding)
	{
		Parameters.Add(new .(name, .Sampler, binding, 0));
	}

	/// Creates a PipelineKey from this material's configuration.
	public PipelineKey GetPipelineKey(TextureFormat colorFormat = .BGRA8UnormSrgb, uint32 sampleCount = 1)
	{
		return .()
		{
			ShaderName = ShaderName,
			Flags = ShaderFlags,
			BlendMode = BlendMode,
			DepthConfig = DepthConfig,
			ColorFormat = colorFormat,
			Topology = .TriangleList,
			CullMode = CullMode,
			SampleCount = sampleCount
		};
	}

	/// Creates a standard PBR material.
	public static Material CreatePBR(StringView name)
	{
		let mat = new Material(name, "pbr");
		mat.ShaderFlags = .NormalMap;
		mat.RenderQueue = 0;

		// PBR parameters (uniform buffer at binding 1)
		mat.AddFloat4Param("baseColor", 0);       // vec4 at offset 0
		mat.AddFloatParam("metallic", 16);        // float at offset 16
		mat.AddFloatParam("roughness", 20);       // float at offset 20
		mat.AddFloatParam("ao", 24);              // float at offset 24
		mat.AddFloatParam("_pad0", 28);           // padding
		mat.AddFloat4Param("emissive", 32);       // vec4 at offset 32
		mat.UniformBufferSize = 48;

		// Textures (material bind group)
		mat.AddTextureParam("albedoMap", 0);
		mat.AddTextureParam("normalMap", 1);
		mat.AddTextureParam("metallicRoughnessMap", 2);
		mat.AddTextureParam("aoMap", 3);
		mat.AddTextureParam("emissiveMap", 4);

		// Samplers
		mat.AddSamplerParam("materialSampler", 0);

		return mat;
	}

	/// Creates an unlit material (no lighting).
	public static Material CreateUnlit(StringView name)
	{
		let mat = new Material(name, "unlit");
		mat.RenderQueue = 0;

		mat.AddFloat4Param("color", 0);
		mat.UniformBufferSize = 16;

		mat.AddTextureParam("mainTexture", 0);
		mat.AddSamplerParam("mainSampler", 0);

		return mat;
	}

	/// Creates a transparent material.
	public static Material CreateTransparent(StringView name, BlendMode blendMode = .AlphaBlend)
	{
		let mat = new Material(name, "unlit");
		mat.BlendMode = blendMode;
		mat.DepthConfig = .TestOnly;  // Don't write depth
		mat.RenderQueue = 2000;

		mat.AddFloat4Param("color", 0);
		mat.UniformBufferSize = 16;

		mat.AddTextureParam("mainTexture", 0);
		mat.AddSamplerParam("mainSampler", 0);

		return mat;
	}
}

/// Handle to a material resource.
struct MaterialHandle : IEquatable<MaterialHandle>, IHashable
{
	private uint32 mIndex;
	private uint32 mGeneration;

	public static readonly Self Invalid = .(uint32.MaxValue, 0);

	public uint32 Index => mIndex;
	public uint32 Generation => mGeneration;
	public bool IsValid => mIndex != uint32.MaxValue;

	public this(uint32 index, uint32 generation)
	{
		mIndex = index;
		mGeneration = generation;
	}

	public bool Equals(Self other)
	{
		return mIndex == other.mIndex && mGeneration == other.mGeneration;
	}

	public int GetHashCode()
	{
		return (int)(mIndex ^ (mGeneration << 16));
	}

	public static bool operator ==(Self lhs, Self rhs) => lhs.Equals(rhs);
	public static bool operator !=(Self lhs, Self rhs) => !lhs.Equals(rhs);
}
