namespace Sedulous.RendererNG;

using System;
using Sedulous.RHI;

/// A resource managed by the render graph.
class RenderGraphResource
{
	/// Resource name for debugging.
	public String Name ~ delete _;

	/// Type of resource.
	public ResourceType Type;

	/// Texture descriptor (if Type == Texture).
	public TextureResourceDesc TextureDesc;

	/// Buffer descriptor (if Type == Buffer).
	public BufferResourceDesc BufferDesc;

	/// Whether this is an imported external resource.
	public bool IsImported;

	/// Whether this resource is transient (lifetime managed by graph).
	public bool IsTransient;

	/// The actual texture (may be null until allocated).
	public ITexture Texture;

	/// The texture view for the resource.
	public ITextureView TextureView;

	/// The actual buffer (may be null until allocated).
	public IBuffer Buffer;

	/// Current resource usage state.
	public ResourceUsage CurrentUsage;

	/// Generation counter for handle validation.
	public uint32 Generation;

	/// Reference count (number of passes that use this resource).
	public int32 RefCount;

	/// First pass that writes to this resource.
	public PassHandle FirstWriter;

	/// Last pass that reads from this resource.
	public PassHandle LastReader;

	public this(StringView name, ResourceType type)
	{
		Name = new String(name);
		Type = type;
		IsImported = false;
		IsTransient = true;
		CurrentUsage = .None;
		Generation = 1;
		RefCount = 0;
		FirstWriter = .Invalid;
		LastReader = .Invalid;
	}

	/// Creates a texture resource descriptor.
	public static Self CreateTexture(StringView name, TextureResourceDesc desc)
	{
		let resource = new Self(name, .Texture);
		resource.TextureDesc = desc;
		return resource;
	}

	/// Creates a buffer resource descriptor.
	public static Self CreateBuffer(StringView name, BufferResourceDesc desc)
	{
		let resource = new Self(name, .Buffer);
		resource.BufferDesc = desc;
		return resource;
	}

	/// Creates an imported texture resource.
	public static Self ImportTexture(StringView name, ITexture texture, ITextureView view)
	{
		let resource = new Self(name, .Texture);
		resource.Texture = texture;
		resource.TextureView = view;
		resource.IsImported = true;
		resource.IsTransient = false;
		return resource;
	}

	/// Creates an imported buffer resource.
	public static Self ImportBuffer(StringView name, IBuffer buffer)
	{
		let resource = new Self(name, .Buffer);
		resource.Buffer = buffer;
		resource.IsImported = true;
		resource.IsTransient = false;
		return resource;
	}

	/// Allocates the actual GPU resource if needed.
	public Result<void> Allocate(IDevice device)
	{
		if (IsImported)
			return .Ok; // Already have the resource

		if (Type == .Texture && Texture == null)
		{
			var texDesc = TextureDescriptor();
			texDesc.Width = TextureDesc.Width;
			texDesc.Height = TextureDesc.Height;
			texDesc.Depth = TextureDesc.Depth;
			texDesc.MipLevelCount = TextureDesc.MipLevels;
			texDesc.ArrayLayerCount = TextureDesc.ArrayLayers;
			texDesc.Format = TextureDesc.Format;
			texDesc.Usage = TextureDesc.Usage;
			texDesc.SampleCount = TextureDesc.SampleCount;

			switch (device.CreateTexture(&texDesc))
			{
			case .Ok(let tex): Texture = tex;
			case .Err: return .Err;
			}

			var viewDesc = TextureViewDescriptor();
			viewDesc.Format = TextureDesc.Format;
			switch (device.CreateTextureView(Texture, &viewDesc))
			{
			case .Ok(let view): TextureView = view;
			case .Err: return .Err;
			}
		}
		else if (Type == .Buffer && Buffer == null)
		{
			var bufDesc = BufferDescriptor(BufferDesc.Size, BufferDesc.Usage, .GpuOnly);
			switch (device.CreateBuffer(&bufDesc))
			{
			case .Ok(let buf): Buffer = buf;
			case .Err: return .Err;
			}
		}

		return .Ok;
	}

	/// Releases transient resources (called after frame).
	public void ReleaseTransient()
	{
		if (!IsTransient)
			return;

		if (TextureView != null)
		{
			delete TextureView;
			TextureView = null;
		}
		if (Texture != null)
		{
			delete Texture;
			Texture = null;
		}
		if (Buffer != null)
		{
			delete Buffer;
			Buffer = null;
		}
	}
}
