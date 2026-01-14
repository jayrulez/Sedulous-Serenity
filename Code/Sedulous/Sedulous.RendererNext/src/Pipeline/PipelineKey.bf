namespace Sedulous.RendererNext;

using System;
using Sedulous.RHI;
using Sedulous.Shaders;

/// Blend mode for particle/sprite rendering.
enum BlendMode : uint8
{
	Opaque,
	AlphaBlend,
	Additive,
	Multiply,
	Premultiplied
}

/// Depth/stencil configuration for pipelines.
struct DepthConfig : IHashable, IEquatable<DepthConfig>
{
	public bool DepthTestEnabled;
	public bool DepthWriteEnabled;
	public CompareFunction DepthCompare;
	public TextureFormat DepthFormat;

	/// Default depth config (test and write enabled, reverse-Z).
	public static Self Default => .()
	{
		DepthTestEnabled = true,
		DepthWriteEnabled = true,
		DepthCompare = .Greater,  // Reverse-Z
		DepthFormat = .Depth24PlusStencil8
	};

	/// Depth test only (no write) - for transparent objects.
	public static Self TestOnly => .()
	{
		DepthTestEnabled = true,
		DepthWriteEnabled = false,
		DepthCompare = .Greater,
		DepthFormat = .Depth24PlusStencil8
	};

	/// No depth testing.
	public static Self None => .()
	{
		DepthTestEnabled = false,
		DepthWriteEnabled = false,
		DepthCompare = .Always,
		DepthFormat = .Depth24PlusStencil8
	};

	public int GetHashCode()
	{
		int hash = DepthTestEnabled ? 1 : 0;
		hash = hash * 31 + (DepthWriteEnabled ? 1 : 0);
		hash = hash * 31 + (int)DepthCompare;
		hash = hash * 31 + (int)DepthFormat;
		return hash;
	}

	public bool Equals(Self other)
	{
		return DepthTestEnabled == other.DepthTestEnabled &&
			   DepthWriteEnabled == other.DepthWriteEnabled &&
			   DepthCompare == other.DepthCompare &&
			   DepthFormat == other.DepthFormat;
	}

	public DepthStencilState ToRHI()
	{
		DepthStencilState state = .();
		state.DepthTestEnabled = DepthTestEnabled;
		state.DepthWriteEnabled = DepthWriteEnabled;
		state.DepthCompare = DepthCompare;
		state.Format = DepthFormat;
		return state;
	}
}

/// Unique key identifying a pipeline configuration.
/// Used by PipelineCache to deduplicate pipelines.
struct PipelineKey : IHashable, IEquatable<PipelineKey>
{
	/// Shader name (e.g., "pbr", "particle", "sprite").
	public StringView ShaderName;

	/// Shader variant flags.
	public ShaderFlags Flags;

	/// Blend mode.
	public BlendMode BlendMode;

	/// Depth configuration.
	public DepthConfig DepthConfig;

	/// Color target format.
	public TextureFormat ColorFormat;

	/// Primitive topology.
	public PrimitiveTopology Topology;

	/// Face culling mode.
	public CullMode CullMode;

	/// MSAA sample count.
	public uint32 SampleCount;

	/// Creates a default pipeline key.
	public static Self Default(StringView shaderName) => .()
	{
		ShaderName = shaderName,
		Flags = .None,
		BlendMode = .Opaque,
		DepthConfig = .Default,
		ColorFormat = .BGRA8UnormSrgb,
		Topology = .TriangleList,
		CullMode = .Back,
		SampleCount = 1
	};

	/// Creates a key for transparent rendering.
	public static Self Transparent(StringView shaderName, BlendMode blendMode = .AlphaBlend) => .()
	{
		ShaderName = shaderName,
		Flags = .None,
		BlendMode = blendMode,
		DepthConfig = .TestOnly,
		ColorFormat = .BGRA8UnormSrgb,
		Topology = .TriangleList,
		CullMode = .Back,
		SampleCount = 1
	};

	public int GetHashCode()
	{
		int hash = ShaderName.GetHashCode();
		hash = hash * 31 + (int)Flags;
		hash = hash * 31 + (int)BlendMode;
		hash = hash * 31 + DepthConfig.GetHashCode();
		hash = hash * 31 + (int)ColorFormat;
		hash = hash * 31 + (int)Topology;
		hash = hash * 31 + (int)CullMode;
		hash = hash * 31 + (int)SampleCount;
		return hash;
	}

	public bool Equals(Self other)
	{
		return ShaderName == other.ShaderName &&
			   Flags == other.Flags &&
			   BlendMode == other.BlendMode &&
			   DepthConfig.Equals(other.DepthConfig) &&
			   ColorFormat == other.ColorFormat &&
			   Topology == other.Topology &&
			   CullMode == other.CullMode &&
			   SampleCount == other.SampleCount;
	}

	public static bool operator ==(Self lhs, Self rhs) => lhs.Equals(rhs);
	public static bool operator !=(Self lhs, Self rhs) => !lhs.Equals(rhs);
}
