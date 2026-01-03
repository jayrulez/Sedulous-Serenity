namespace Sedulous.RHI;

/// Texture layout for pipeline barriers.
enum TextureLayout
{
	/// Undefined - contents may be discarded.
	Undefined,
	/// General layout - can be used for any operation but not optimal.
	General,
	/// Optimal for use as a color attachment in a render pass.
	ColorAttachment,
	/// Optimal for use as a depth/stencil attachment.
	DepthStencilAttachment,
	/// Optimal for reading in a shader (sampled image).
	ShaderReadOnly,
	/// Optimal for use as transfer source.
	TransferSrc,
	/// Optimal for use as transfer destination.
	TransferDst,
	/// Optimal for presentation.
	Present
}

/// Encodes commands to be submitted to the GPU.
interface ICommandEncoder
{
	/// Begins a render pass.
	IRenderPassEncoder BeginRenderPass(RenderPassDescriptor* descriptor);

	/// Begins a compute pass.
	IComputePassEncoder BeginComputePass();

	/// Copies data from one buffer to another.
	void CopyBufferToBuffer(IBuffer source, uint64 sourceOffset, IBuffer destination, uint64 destinationOffset, uint64 size);

	/// Copies data from a buffer to a texture.
	void CopyBufferToTexture(IBuffer source, ITexture destination, BufferTextureCopyInfo* copyInfo);

	/// Copies data from a texture to a buffer.
	void CopyTextureToBuffer(ITexture source, IBuffer destination, BufferTextureCopyInfo* copyInfo);

	/// Copies data from one texture to another.
	void CopyTextureToTexture(ITexture source, ITexture destination, TextureCopyInfo* copyInfo);

	/// Inserts a texture barrier to transition the texture layout.
	/// This should be called between passes when a texture's usage changes
	/// (e.g., from render target to shader input).
	void TextureBarrier(ITexture texture, TextureLayout oldLayout, TextureLayout newLayout);

	/// Generates mipmaps for a texture by successively downsampling from mip level 0.
	/// The texture must have been created with CopySrc and CopyDst usage flags,
	/// and must have more than 1 mip level.
	/// After this call, all mip levels will contain downsampled versions of level 0.
	void GenerateMipmaps(ITexture texture);

	// ===== Queries =====

	/// Resets a range of queries in a query set.
	/// Must be called before writing new query results.
	void ResetQuerySet(IQuerySet querySet, uint32 firstQuery, uint32 queryCount);

	/// Writes a timestamp to the query set at the specified index.
	/// Only valid for timestamp query sets.
	void WriteTimestamp(IQuerySet querySet, uint32 queryIndex);

	/// Begins an occlusion or pipeline statistics query.
	/// Must be paired with EndQuery. Not valid for timestamp queries.
	void BeginQuery(IQuerySet querySet, uint32 queryIndex);

	/// Ends an occlusion or pipeline statistics query.
	/// Must be paired with BeginQuery. Not valid for timestamp queries.
	void EndQuery(IQuerySet querySet, uint32 queryIndex);

	/// Resolves query results to a buffer for readback.
	/// This copies query results from GPU memory to a buffer that can be mapped.
	void ResolveQuerySet(IQuerySet querySet, uint32 firstQuery, uint32 queryCount, IBuffer destination, uint64 destinationOffset);

	/// Resolves a multisampled texture to a non-multisampled texture.
	/// Both textures must have compatible formats. The source must be multisampled,
	/// and the destination must be single-sampled.
	void ResolveTexture(ITexture source, ITexture destination);

	/// Blits (copies with potential format conversion and scaling) from one texture to another.
	/// Unlike CopyTextureToTexture, this supports format conversion and filtering for scaling.
	/// Uses linear filtering when the source and destination sizes differ.
	void Blit(ITexture source, ITexture destination);

	/// Finishes recording and returns an immutable command buffer.
	ICommandBuffer Finish();
}
