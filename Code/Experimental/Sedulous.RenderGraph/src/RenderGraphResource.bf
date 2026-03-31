namespace Sedulous.RenderGraph;

using System;
using Sedulous.RHI;

/// Internal metadata for a resource tracked by the render graph.
class RenderGraphResource
{
	/// Unique index in the resource table.
	public uint32 Index;

	/// Current version (incremented on each write).
	public uint32 Version = 1;

	/// Human-readable name for debugging.
	public String Name ~ delete _;

	/// Whether this resource was imported (externally owned) or is transient (graph-managed).
	public bool IsImported;

	/// True if this is a texture resource, false if buffer.
	public bool IsTexture;

	// --- Transient texture descriptor (only valid for transient textures) ---
	public RGTextureDesc TextureDesc;

	// --- Transient buffer descriptor (only valid for transient buffers) ---
	public RGBufferDesc BufferDesc;

	// --- Imported resource state ---

	/// Concrete GPU texture (set for imported textures, or after allocation for transients).
	public ITexture ImportedTexture;

	/// Concrete GPU texture view (set for imported textures).
	public ITextureView ImportedTextureView;

	/// Concrete GPU buffer (set for imported buffers, or after allocation for transients).
	public IBuffer ImportedBuffer;

	/// The resource state this resource is in when first encountered by the graph.
	/// For imported resources, this is provided by the caller.
	/// For transient resources, this starts as Undefined.
	public ResourceState InitialState;

	// --- Lifetime tracking (set during scheduling) ---

	/// First pass index that uses this resource.
	public int32 FirstUsePass = -1;

	/// Last pass index that uses this resource.
	public int32 LastUsePass = -1;

	/// The pass that first writes this resource (producer).
	public int32 WriterPass = -1;

	public this(uint32 index, StringView name, bool isTexture)
	{
		Index = index;
		Name = new String(name);
		IsTexture = isTexture;
	}

	/// Gets an RGTexture handle for this resource at the current version.
	public RGTexture AsTexture() => .(.(Index, Version));

	/// Gets an RGBuffer handle for this resource at the current version.
	public RGBuffer AsBuffer() => .(.(Index, Version));

	/// Increments version and returns the new versioned handle.
	public RGResource NextVersion()
	{
		Version++;
		return .(Index, Version);
	}
}
