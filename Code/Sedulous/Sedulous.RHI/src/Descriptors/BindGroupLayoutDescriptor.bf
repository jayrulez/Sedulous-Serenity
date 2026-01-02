namespace Sedulous.RHI;

using System;

/// Describes a single binding within a bind group layout.
struct BindGroupLayoutEntry
{
	/// Binding index (matches shader binding).
	public uint32 Binding;
	/// Shader stages that can access this binding.
	public ShaderStage Visibility;
	/// Type of resource being bound.
	public BindingType Type;
	/// For buffers: has dynamic offset.
	public bool HasDynamicOffset;
	/// For buffers: minimum binding size (0 = no minimum).
	public uint64 MinBufferBindingSize;
	/// For textures: sample type (matches texture format).
	public TextureViewDimension TextureViewDimension;
	/// For textures: multisampled.
	public bool TextureMultisampled;
	/// For storage textures: format.
	public TextureFormat StorageTextureFormat;

	public this()
	{
		Binding = 0;
		Visibility = .Vertex | .Fragment;
		Type = .UniformBuffer;
		HasDynamicOffset = false;
		MinBufferBindingSize = 0;
		TextureViewDimension = .Texture2D;
		TextureMultisampled = false;
		StorageTextureFormat = .RGBA8Unorm;
	}

	/// Creates a uniform buffer binding entry.
	public static Self UniformBuffer(uint32 binding, ShaderStage visibility, bool dynamicOffset = false)
	{
		Self entry = .();
		entry.Binding = binding;
		entry.Visibility = visibility;
		entry.Type = .UniformBuffer;
		entry.HasDynamicOffset = dynamicOffset;
		return entry;
	}

	/// Creates a sampled texture binding entry.
	public static Self SampledTexture(uint32 binding, ShaderStage visibility, TextureViewDimension dimension = .Texture2D)
	{
		Self entry = .();
		entry.Binding = binding;
		entry.Visibility = visibility;
		entry.Type = .SampledTexture;
		entry.TextureViewDimension = dimension;
		return entry;
	}

	/// Creates a sampler binding entry.
	public static Self Sampler(uint32 binding, ShaderStage visibility)
	{
		Self entry = .();
		entry.Binding = binding;
		entry.Visibility = visibility;
		entry.Type = .Sampler;
		return entry;
	}
}

/// Describes a bind group layout.
struct BindGroupLayoutDescriptor
{
	/// Binding entries in this layout.
	public Span<BindGroupLayoutEntry> Entries;
	/// Optional label for debugging.
	public StringView Label;

	public this()
	{
		Entries = default;
		Label = default;
	}

	public this(Span<BindGroupLayoutEntry> entries)
	{
		Entries = entries;
		Label = default;
	}
}
