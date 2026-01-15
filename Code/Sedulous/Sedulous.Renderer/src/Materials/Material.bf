namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Shaders;
using Sedulous.Mathematics;

/// Blend mode presets for materials.
enum BlendMode
{
	/// No blending, fully opaque.
	Opaque,
	/// Alpha blending (src.a, 1-src.a).
	AlphaBlend,
	/// Additive blending (one, one).
	Additive,
	/// Multiply blending.
	Multiply,
	/// Premultiplied alpha.
	PremultipliedAlpha
}

/// Depth testing mode.
enum DepthMode
{
	/// No depth testing or writing.
	Disabled,
	/// Read and write depth (default for opaque).
	ReadWrite,
	/// Read only (for transparents).
	ReadOnly,
	/// Write only (for depth prepass).
	WriteOnly
}

/// Type of material parameter.
enum MaterialParameterType
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
	Sampler
}

/// Describes a material parameter.
class MaterialParameterDesc
{
	public String Name ~ delete _;
	public MaterialParameterType Type;
	public uint32 Binding;
	public uint32 Offset;   // Offset in uniform buffer (for non-texture params)

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
	public ShaderFlags ShaderFlags;

	/// Blend mode.
	public BlendMode BlendMode = .Opaque;

	/// Face culling (uses RHI CullMode).
	public Sedulous.RHI.CullMode CullMode = .Back;

	/// Depth testing mode.
	public DepthMode DepthMode = .ReadWrite;

	/// Whether this material uses reverse-Z depth.
	public bool UseReverseZ = false;

	/// Whether this material casts shadows.
	public bool CastShadows = true;

	/// Whether this material receives shadows.
	public bool ReceiveShadows = true;

	/// Render queue priority (lower = rendered first).
	/// Opaques: 0-999, AlphaTest: 1000-1999, Transparent: 2000+
	public int32 RenderQueue = 0;

	/// Parameter declarations.
	public List<MaterialParameterDesc> Parameters = new .() ~ DeleteContainerAndItems!(_);

	/// Size of the material uniform buffer in bytes.
	public uint32 UniformBufferSize = 0;

	public this(StringView name, StringView shaderName)
	{
		Name = new String(name);
		ShaderName = new String(shaderName);
	}

	/// Adds a float parameter.
	public void AddFloatParam(StringView name, uint32 binding, uint32 offset)
	{
		Parameters.Add(new .(name, .Float, binding, offset));
	}

	/// Adds a float4 parameter (e.g., color).
	public void AddFloat4Param(StringView name, uint32 binding, uint32 offset)
	{
		Parameters.Add(new .(name, .Float4, binding, offset));
	}

	/// Adds a matrix parameter.
	public void AddMatrixParam(StringView name, uint32 binding, uint32 offset)
	{
		Parameters.Add(new .(name, .Matrix4x4, binding, offset));
	}

	/// Adds a texture parameter.
	public void AddTextureParam(StringView name, uint32 binding)
	{
		Parameters.Add(new .(name, .Texture2D, binding, 0));
	}

	/// Adds a sampler parameter.
	public void AddSamplerParam(StringView name, uint32 binding)
	{
		Parameters.Add(new .(name, .Sampler, binding, 0));
	}

	/// Gets the blend state for this material.
	public BlendState? GetBlendState()
	{
		switch (BlendMode)
		{
		case .Opaque:
			return null; // No blending
		case .AlphaBlend:
			return .()
			{
				Color = .(.Add, .SrcAlpha, .OneMinusSrcAlpha),
				Alpha = .(.Add, .One, .OneMinusSrcAlpha)
			};
		case .Additive:
			return .()
			{
				Color = .(.Add, .One, .One),
				Alpha = .(.Add, .One, .One)
			};
		case .Multiply:
			return .()
			{
				Color = .(.Add, .Dst, .Zero),
				Alpha = .(.Add, .DstAlpha, .Zero)
			};
		case .PremultipliedAlpha:
			return .()
			{
				Color = .(.Add, .One, .OneMinusSrcAlpha),
				Alpha = .(.Add, .One, .OneMinusSrcAlpha)
			};
		}
	}

	/// Gets the depth stencil state for this material.
	public DepthStencilState GetDepthStencilState()
	{
		DepthStencilState state = .();
		let compare = UseReverseZ ? CompareFunction.Greater : CompareFunction.Less;

		switch (DepthMode)
		{
		case .Disabled:
			state.DepthTestEnabled = false;
			state.DepthWriteEnabled = false;
		case .ReadWrite:
			state.DepthTestEnabled = true;
			state.DepthWriteEnabled = true;
			state.DepthCompare = compare;
		case .ReadOnly:
			state.DepthTestEnabled = true;
			state.DepthWriteEnabled = false;
			state.DepthCompare = compare;
		case .WriteOnly:
			state.DepthTestEnabled = true;
			state.DepthWriteEnabled = true;
			state.DepthCompare = .Always;
		}

		return state;
	}

	/// Gets the primitive state (cull mode).
	public PrimitiveState GetPrimitiveState()
	{
		PrimitiveState state = .();
		state.Topology = .TriangleList;
		state.FrontFace = .CCW;
		state.CullMode = CullMode;
		return state;
	}

	/// Converts DepthMode and UseReverseZ to ShaderFlags.
	/// Use this when shader variants need to know about depth configuration.
	/// Note: Most shaders don't need this since depth is typically pipeline state only.
	public ShaderFlags GetDepthShaderFlags()
	{
		ShaderFlags flags = .None;

		switch (DepthMode)
		{
		case .Disabled:
			// No depth flags
			break;
		case .ReadWrite:
			flags |= .DepthTest | .DepthWrite;
		case .ReadOnly:
			flags |= .DepthTest;
		case .WriteOnly:
			flags |= .DepthWrite;
		}

		if (UseReverseZ)
			flags |= .ReverseZ;

		return flags;
	}

	/// Gets all shader flags for this material, including depth flags.
	/// Combines user-set ShaderFlags with depth configuration flags.
	public ShaderFlags GetAllShaderFlags()
	{
		return ShaderFlags | GetDepthShaderFlags();
	}

	/// Creates a standard PBR material.
	public static Material CreatePBR(StringView name)
	{
		let mat = new Material(name, "pbr");
		mat.ShaderFlags = .NormalMap;
		mat.RenderQueue = 0;

		// PBR parameters (binding 1 = material uniform buffer)
		mat.AddFloat4Param("baseColor", 1, 0);       // vec4 at offset 0
		mat.AddFloatParam("metallic", 1, 16);        // float at offset 16
		mat.AddFloatParam("roughness", 1, 20);       // float at offset 20
		mat.AddFloatParam("ao", 1, 24);              // float at offset 24
		mat.AddFloat4Param("emissive", 1, 32);       // vec4 at offset 32
		mat.UniformBufferSize = 48;

		// Textures (bindings start at higher values due to Vulkan shifts)
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

		mat.AddFloat4Param("color", 1, 0);
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

	public static readonly Self Invalid = .((uint32)-1, 0);

	public uint32 Index => mIndex;
	public uint32 Generation => mGeneration;
	public bool IsValid => mIndex != (uint32)-1;

	public this(uint32 index, uint32 generation)
	{
		mIndex = index;
		mGeneration = generation;
	}

	public bool Equals(MaterialHandle other)
	{
		return mIndex == other.mIndex && mGeneration == other.mGeneration;
	}

	public int GetHashCode()
	{
		return (int)(mIndex ^ (mGeneration << 16));
	}
}

