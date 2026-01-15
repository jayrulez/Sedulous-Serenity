namespace Sedulous.RendererNG;

using System;
using Sedulous.RHI;
using Sedulous.Mathematics;

/// Handle to a resource in the render graph.
struct RGResourceHandle : IHashable, IEquatable<RGResourceHandle>
{
	public uint32 Index;
	public uint32 Generation;

	public static Self Invalid => .() { Index = uint32.MaxValue, Generation = 0 };

	public bool IsValid => Index != uint32.MaxValue;

	public int GetHashCode() => (int)(Index ^ (Generation << 16));

	public bool Equals(RGResourceHandle other) => Index == other.Index && Generation == other.Generation;

	public static bool operator ==(RGResourceHandle a, RGResourceHandle b) => a.Index == b.Index && a.Generation == b.Generation;
	public static bool operator !=(RGResourceHandle a, RGResourceHandle b) => !(a == b);
}

/// Handle to a render pass in the graph.
struct PassHandle : IHashable, IEquatable<PassHandle>
{
	public uint32 Index;

	public static Self Invalid => .() { Index = uint32.MaxValue };

	public bool IsValid => Index != uint32.MaxValue;

	public int GetHashCode() => (int)Index;

	public bool Equals(PassHandle other) => Index == other.Index;

	public static bool operator ==(PassHandle a, PassHandle b) => a.Index == b.Index;
	public static bool operator !=(PassHandle a, PassHandle b) => !(a == b);
}

/// Type of resource in the render graph.
enum ResourceType : uint8
{
	Texture,
	Buffer
}

/// How a resource is used in a pass.
enum ResourceUsage : uint8
{
	/// Not used
	None,
	/// Read as shader resource
	ShaderRead,
	/// Write as render target
	RenderTarget,
	/// Write as depth-stencil
	DepthStencil,
	/// Read/write as UAV
	UnorderedAccess,
	/// Copy source
	CopySource,
	/// Copy destination
	CopyDest,
	/// Present to swapchain
	Present
}

/// Type of render pass.
enum PassType : uint8
{
	/// Graphics pass with render targets
	Graphics,
	/// Compute pass
	Compute,
	/// Copy/transfer pass
	Copy
}

/// Flags for pass execution.
enum PassFlags : uint32
{
	None = 0,
	/// Pass should not be culled even if outputs unused
	NeverCull = 1 << 0,
	/// Pass is async compute
	AsyncCompute = 1 << 1
}

/// Descriptor for a texture resource.
struct TextureResourceDesc
{
	public uint32 Width;
	public uint32 Height;
	public uint32 Depth;
	public uint32 MipLevels;
	public uint32 ArrayLayers;
	public TextureFormat Format;
	public TextureUsage Usage;
	public uint32 SampleCount;

	public static Self RenderTarget(uint32 width, uint32 height, TextureFormat format) => .()
	{
		Width = width,
		Height = height,
		Depth = 1,
		MipLevels = 1,
		ArrayLayers = 1,
		Format = format,
		Usage = .RenderTarget | .Sampled,
		SampleCount = 1
	};

	public static Self DepthStencil(uint32 width, uint32 height, TextureFormat format) => .()
	{
		Width = width,
		Height = height,
		Depth = 1,
		MipLevels = 1,
		ArrayLayers = 1,
		Format = format,
		Usage = .DepthStencil | .Sampled,
		SampleCount = 1
	};
}

/// Descriptor for a buffer resource.
struct BufferResourceDesc
{
	public uint64 Size;
	public BufferUsage Usage;
}

/// Color attachment configuration.
struct ColorAttachment
{
	public RGResourceHandle Handle;
	public LoadOp LoadOp;
	public StoreOp StoreOp;
	public Color ClearColor;
	public uint32 MipLevel;
	public uint32 ArrayLayer;

	public static Self Default(RGResourceHandle handle) => .()
	{
		Handle = handle,
		LoadOp = .Clear,
		StoreOp = .Store,
		ClearColor = .Black,
		MipLevel = 0,
		ArrayLayer = 0
	};
}

/// Depth-stencil attachment configuration.
struct DepthStencilAttachment
{
	public RGResourceHandle Handle;
	public LoadOp DepthLoadOp;
	public StoreOp DepthStoreOp;
	public LoadOp StencilLoadOp;
	public StoreOp StencilStoreOp;
	public float ClearDepth;
	public uint8 ClearStencil;
	public bool ReadOnly;

	public static Self Default(RGResourceHandle handle) => .()
	{
		Handle = handle,
		DepthLoadOp = .Clear,
		DepthStoreOp = .Store,
		StencilLoadOp = .DontCare,
		StencilStoreOp = .Discard,
		ClearDepth = 1.0f,
		ClearStencil = 0,
		ReadOnly = false
	};
}

/// Resource read dependency.
struct ResourceRead
{
	public RGResourceHandle Handle;
	public ResourceUsage Usage;
}

/// Resource write dependency.
struct ResourceWrite
{
	public RGResourceHandle Handle;
	public ResourceUsage Usage;
}

/// Execution callback for a render pass.
delegate void PassExecuteCallback(IRenderPassEncoder encoder);

/// Execution callback for a compute pass.
delegate void ComputePassExecuteCallback(IComputePassEncoder encoder);
