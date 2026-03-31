namespace Sedulous.RenderGraph;

using System;
using Sedulous.RHI;

/// Opaque handle to a render graph resource. Lightweight value type.
/// Resources are referenced by index + version to enable SSA-style tracking.
struct RGResource : IHashable
{
	public const Self Invalid = .((uint32)0, (uint32)0);

	public uint32 Index;
	public uint32 Version;

	public this(uint32 index, uint32 version)
	{
		Index = index;
		Version = version;
	}

	public bool IsValid => Index != 0 || Version != 0;

	public int GetHashCode()
	{
		return (int)(Index * 397 ^ Version);
	}

	public static bool operator==(Self lhs, Self rhs) => lhs.Index == rhs.Index && lhs.Version == rhs.Version;
	public static bool operator!=(Self lhs, Self rhs) => !(lhs == rhs);
}

/// Opaque handle to a render graph texture.
struct RGTexture : IHashable
{
	public RGResource Resource;

	public this(RGResource resource)
	{
		Resource = resource;
	}

	public this(uint32 index, uint32 version)
	{
		Resource = .(index, version);
	}

	public bool IsValid => Resource.IsValid;
	public uint32 Index => Resource.Index;
	public uint32 Version => Resource.Version;

	public int GetHashCode() => Resource.GetHashCode();

	public static bool operator==(Self lhs, Self rhs) => lhs.Resource == rhs.Resource;
	public static bool operator!=(Self lhs, Self rhs) => !(lhs == rhs);
}

/// Opaque handle to a render graph buffer.
struct RGBuffer : IHashable
{
	public RGResource Resource;

	public this(RGResource resource)
	{
		Resource = resource;
	}

	public this(uint32 index, uint32 version)
	{
		Resource = .(index, version);
	}

	public bool IsValid => Resource.IsValid;
	public uint32 Index => Resource.Index;
	public uint32 Version => Resource.Version;

	public int GetHashCode() => Resource.GetHashCode();

	public static bool operator==(Self lhs, Self rhs) => lhs.Resource == rhs.Resource;
	public static bool operator!=(Self lhs, Self rhs) => !(lhs == rhs);
}

/// Describes a transient texture to be created by the render graph.
struct RGTextureDesc
{
	public TextureFormat Format;
	public uint32 Width;
	public uint32 Height;
	public uint32 ArrayLayerCount = 1;
	public uint32 MipLevelCount = 1;
	public uint32 SampleCount = 1;
	public StringView Name;

	public static Self RenderTarget(TextureFormat format, uint32 width, uint32 height,
		uint32 sampleCount = 1, StringView name = default)
	{
		return .()
		{
			Format = format,
			Width = width,
			Height = height,
			SampleCount = sampleCount,
			Name = name
		};
	}

	public static Self DepthBuffer(TextureFormat format, uint32 width, uint32 height,
		uint32 sampleCount = 1, StringView name = default)
	{
		return .()
		{
			Format = format,
			Width = width,
			Height = height,
			SampleCount = sampleCount,
			Name = name
		};
	}
}

/// Describes a transient buffer to be created by the render graph.
struct RGBufferDesc
{
	public uint64 Size;
	public BufferUsage Usage;
	public StringView Name;
}

/// How a pass accesses a resource.
enum RGAccessType
{
	/// Sampled texture read in shader stages.
	ReadTexture,
	/// Buffer read as uniform.
	ReadUniformBuffer,
	/// Buffer read as storage (read-only SSBO / SRV).
	ReadStorageBuffer,
	/// Depth/stencil read-only.
	ReadDepthStencil,
	/// Copy source.
	ReadCopySrc,
	/// Render target content read via LoadOp.Load (stays in RenderTarget state).
	/// Creates an ordering dependency without transitioning to ShaderRead.
	ReadRenderTarget,
	/// Depth/stencil content read via LoadOp.Load (stays in DepthStencilWrite state).
	ReadDepthStencilLoad,
	/// Render target (color attachment) write.
	WriteRenderTarget,
	/// Depth/stencil write.
	WriteDepthStencil,
	/// Storage image/buffer write (UAV).
	WriteStorage,
	/// Copy destination.
	WriteCopyDst,
	/// Read-write storage (UAV) — simultaneous read and write within a single pass.
	ReadWriteStorage,
}

/// A single resource access declaration from a pass.
struct RGResourceAccess
{
	public RGResource Resource;
	public RGAccessType AccessType;
	public ShaderStage Stages;
	/// Render target slot index (only meaningful for WriteRenderTarget).
	public uint32 Slot;

	/// Whether this access is a read operation.
	public bool IsRead => !IsWrite || AccessType == .ReadWriteStorage;

	/// Whether this access is a write operation.
	public bool IsWrite => AccessType == .WriteRenderTarget ||
		AccessType == .WriteDepthStencil ||
		AccessType == .WriteStorage ||
		AccessType == .WriteCopyDst ||
		AccessType == .ReadWriteStorage;

	/// Maps this access type to the corresponding ResourceState for barrier insertion.
	public ResourceState ToResourceState()
	{
		switch (AccessType)
		{
		case .ReadTexture:           return .ShaderRead;
		case .ReadUniformBuffer:     return .UniformBuffer;
		case .ReadStorageBuffer:     return .ShaderRead;
		case .ReadDepthStencil:      return .DepthStencilRead;
		case .ReadCopySrc:           return .CopySrc;
		case .ReadRenderTarget:      return .RenderTarget;
		case .ReadDepthStencilLoad:  return .DepthStencilWrite;
		case .WriteRenderTarget:     return .RenderTarget;
		case .WriteDepthStencil:  return .DepthStencilWrite;
		case .WriteStorage:       return .ShaderWrite;
		case .WriteCopyDst:       return .CopyDst;
		case .ReadWriteStorage:   return .ShaderWrite; // UAV read-write maps to ShaderWrite state
		}
	}
}
