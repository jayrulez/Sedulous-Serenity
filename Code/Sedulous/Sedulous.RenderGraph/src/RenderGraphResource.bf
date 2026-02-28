using System;
using Sedulous.RHI;

namespace Sedulous.RenderGraph;

/// Distinguishes texture resources from buffer resources.
public enum ResourceType
{
	Texture,
	Buffer
}

/// Internal tracking of a resource within the render graph.
///
/// Resources are either imported (externally owned) or transient (created and
/// destroyed within a frame by the graph). The graph tracks their lifetime
/// and layout state for barrier insertion.
///
internal class RenderGraphResource
{
	/// Debug name for this resource.
	public String Name = new .() ~ delete _;

	/// Whether this is a texture or buffer.
	public ResourceType Type;

	/// True if this resource is externally managed (e.g. swap chain image).
	public bool Imported;

	// ===== Imported Resources =====

	/// The imported texture (only valid if Imported && Type == Texture).
	public ITexture ImportedTexture;

	/// The imported texture view (only valid if Imported && Type == Texture).
	public ITextureView ImportedTextureView;

	/// The imported buffer (only valid if Imported && Type == Buffer).
	public IBuffer ImportedBuffer;

	// ===== Transient Resources =====

	/// Descriptor for creating a transient texture.
	public TextureDescriptor TextureDesc;

	/// Descriptor for creating a transient buffer.
	public BufferDescriptor BufferDesc;

	/// The physical texture allocated by the transient pool (null until Compile).
	public ITexture PhysicalTexture;

	/// The physical texture view for the transient texture.
	public ITextureView PhysicalTextureView;

	/// The physical buffer allocated by the transient pool (null until Compile).
	public IBuffer PhysicalBuffer;

	// ===== Lifetime Tracking =====

	/// Index of the first pass that uses this resource (set during compilation).
	public int32 FirstPassIndex = -1;

	/// Index of the last pass that uses this resource (set during compilation).
	public int32 LastPassIndex = -1;

	/// Current version (incremented on each write).
	public uint16 CurrentVersion = 0;

	/// Current texture layout (tracked for barrier insertion).
	public TextureLayout CurrentLayout = .Undefined;

	// ===== Accessors =====

	/// Gets the actual texture (imported or allocated transient).
	public ITexture Texture => Imported ? ImportedTexture : PhysicalTexture;

	/// Gets the actual texture view (imported or allocated transient).
	public ITextureView TextureView => Imported ? ImportedTextureView : PhysicalTextureView;

	/// Gets the actual buffer (imported or allocated transient).
	public IBuffer Buffer => Imported ? ImportedBuffer : PhysicalBuffer;
}
