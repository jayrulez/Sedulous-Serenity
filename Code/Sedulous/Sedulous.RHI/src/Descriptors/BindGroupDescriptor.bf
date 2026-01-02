namespace Sedulous.RHI;

using System;

/// Describes a resource binding within a bind group.
struct BindGroupEntry
{
	/// Binding index (must match layout).
	public uint32 Binding;
	/// Buffer to bind (for buffer bindings).
	public IBuffer Buffer;
	/// Offset into buffer.
	public uint64 BufferOffset;
	/// Size of buffer range (0 = entire buffer from offset).
	public uint64 BufferSize;
	/// Texture view to bind (for texture bindings).
	public ITextureView TextureView;
	/// Sampler to bind (for sampler bindings).
	public ISampler Sampler;

	public this()
	{
		Binding = 0;
		Buffer = null;
		BufferOffset = 0;
		BufferSize = 0;
		TextureView = null;
		Sampler = null;
	}

	/// Creates a buffer binding entry.
	public static Self Buffer(uint32 binding, IBuffer buffer, uint64 offset = 0, uint64 size = 0)
	{
		Self entry = .();
		entry.Binding = binding;
		entry.Buffer = buffer;
		entry.BufferOffset = offset;
		entry.BufferSize = size;
		return entry;
	}

	/// Creates a texture view binding entry.
	public static Self Texture(uint32 binding, ITextureView textureView)
	{
		Self entry = .();
		entry.Binding = binding;
		entry.TextureView = textureView;
		return entry;
	}

	/// Creates a sampler binding entry.
	public static Self Sampler(uint32 binding, ISampler sampler)
	{
		Self entry = .();
		entry.Binding = binding;
		entry.Sampler = sampler;
		return entry;
	}
}

/// Describes a bind group.
struct BindGroupDescriptor
{
	/// The layout this bind group conforms to.
	public IBindGroupLayout Layout;
	/// Resource binding entries.
	public Span<BindGroupEntry> Entries;
	/// Optional label for debugging.
	public StringView Label;

	public this()
	{
		Layout = null;
		Entries = default;
		Label = default;
	}

	public this(IBindGroupLayout layout, Span<BindGroupEntry> entries)
	{
		Layout = layout;
		Entries = entries;
		Label = default;
	}
}
