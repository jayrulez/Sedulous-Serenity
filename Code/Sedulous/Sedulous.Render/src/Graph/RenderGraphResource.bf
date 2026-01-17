namespace Sedulous.Render;

using System;
using Sedulous.RHI;

/// Handle to a render graph resource.
public struct RGResourceHandle : IHashable
{
	public uint32 Index;
	public uint32 Generation;

	public static Self Invalid = .() { Index = uint32.MaxValue, Generation = 0 };

	public bool IsValid => Index != uint32.MaxValue;

	public int GetHashCode() => (int)(Index ^ (Generation << 16));

	public static bool operator ==(Self lhs, Self rhs)
	{
		return lhs.Index == rhs.Index && lhs.Generation == rhs.Generation;
	}

	public static bool operator !=(Self lhs, Self rhs)
	{
		return !(lhs == rhs);
	}
}

/// Handle to a render pass.
public struct PassHandle : IHashable
{
	public uint32 Index;

	public static Self Invalid = .() { Index = uint32.MaxValue };

	public bool IsValid => Index != uint32.MaxValue;

	public int GetHashCode() => (int)Index;

	public static bool operator ==(Self lhs, Self rhs) => lhs.Index == rhs.Index;
	public static bool operator !=(Self lhs, Self rhs) => lhs.Index != rhs.Index;
}

/// Resource type.
public enum RGResourceType : uint8
{
	Texture,
	Buffer
}

/// Descriptor for transient texture resources.
public struct TextureResourceDesc
{
	public uint32 Width;
	public uint32 Height;
	public uint32 DepthOrArrayLayers = 1;
	public TextureFormat Format;
	public TextureUsage Usage;
	public uint32 MipLevels = 1;
	public uint32 SampleCount = 1;

	public this(uint32 width, uint32 height, TextureFormat format, TextureUsage usage = .RenderTarget | .Sampled)
	{
		Width = width;
		Height = height;
		DepthOrArrayLayers = 1;
		Format = format;
		Usage = usage;
		MipLevels = 1;
		SampleCount = 1;
	}
}

/// Descriptor for transient buffer resources.
public struct BufferResourceDesc
{
	public uint64 Size;
	public BufferUsage Usage;

	public this(uint64 size, BufferUsage usage)
	{
		Size = size;
		Usage = usage;
	}
}

/// A resource managed by the render graph.
public class RenderGraphResource
{
	public ~this()
	{
		ReleaseTransient();
	}

	/// Resource name for debugging.
	public String Name = new .() ~ delete _;

	/// Resource type.
	public RGResourceType Type;

	/// Whether this is a transient (graph-managed) resource.
	public bool IsTransient;

	/// Generation counter for handle validation.
	public uint32 Generation;

	/// Reference count (number of passes that use this resource).
	public int32 RefCount;

	/// Handle to the pass that first writes to this resource.
	public PassHandle FirstWriter = .Invalid;

	/// Handle to the pass that last reads from this resource.
	public PassHandle LastReader = .Invalid;

	// Texture data
	public TextureResourceDesc TextureDesc;
	public ITexture Texture;
	public ITextureView TextureView;

	// Buffer data
	public BufferResourceDesc BufferDesc;
	public IBuffer Buffer;

	/// Creates a transient texture resource.
	public static RenderGraphResource CreateTexture(StringView name, TextureResourceDesc desc)
	{
		let resource = new RenderGraphResource();
		resource.Name.Set(name);
		resource.Type = .Texture;
		resource.IsTransient = true;
		resource.Generation = 1;
		resource.TextureDesc = desc;
		return resource;
	}

	/// Creates a transient buffer resource.
	public static RenderGraphResource CreateBuffer(StringView name, BufferResourceDesc desc)
	{
		let resource = new RenderGraphResource();
		resource.Name.Set(name);
		resource.Type = .Buffer;
		resource.IsTransient = true;
		resource.Generation = 1;
		resource.BufferDesc = desc;
		return resource;
	}

	/// Imports an external texture.
	public static RenderGraphResource ImportTexture(StringView name, ITexture texture, ITextureView view)
	{
		let resource = new RenderGraphResource();
		resource.Name.Set(name);
		resource.Type = .Texture;
		resource.IsTransient = false;
		resource.Generation = 1;
		resource.Texture = texture;
		resource.TextureView = view;
		return resource;
	}

	/// Imports an external buffer.
	public static RenderGraphResource ImportBuffer(StringView name, IBuffer buffer)
	{
		let resource = new RenderGraphResource();
		resource.Name.Set(name);
		resource.Type = .Buffer;
		resource.IsTransient = false;
		resource.Generation = 1;
		resource.Buffer = buffer;
		return resource;
	}

	/// Allocates the underlying GPU resource.
	public Result<void> Allocate(IDevice device)
	{
		if (!IsTransient)
			return .Ok; // Already have the resource

		if (Type == .Texture)
		{
			if (Texture != null)
				return .Ok; // Already allocated

			var desc = TextureDescriptor()
			{
				Width = TextureDesc.Width,
				Height = TextureDesc.Height,
				Depth = 1,
				ArrayLayerCount = TextureDesc.DepthOrArrayLayers,
				Format = TextureDesc.Format,
				Usage = TextureDesc.Usage,
				MipLevelCount = TextureDesc.MipLevels,
				SampleCount = TextureDesc.SampleCount,
				Dimension = .Texture2D,
				Label = "RGAllocated"
			};

			if (device.CreateTexture(&desc) case .Ok(let tex))
			{
				Texture = tex;

				// Create default view
				var viewDesc = TextureViewDescriptor()
				{
					Format = TextureDesc.Format,
					Dimension = .Texture2D,
					BaseMipLevel = 0,
					MipLevelCount = TextureDesc.MipLevels,
					BaseArrayLayer = 0,
					ArrayLayerCount = TextureDesc.DepthOrArrayLayers,
					Label = "RGAllocatedView"
				};

				if (device.CreateTextureView(tex, &viewDesc) case .Ok(let view))
					TextureView = view;
				else
					return .Err;
			}
			else
				return .Err;
		}
		else if (Type == .Buffer)
		{
			if (Buffer != null)
				return .Ok;

			var desc = BufferDescriptor()
			{
				Size = BufferDesc.Size,
				Usage = BufferDesc.Usage
			};

			if (device.CreateBuffer(&desc) case .Ok(let buf))
				Buffer = buf;
			else
				return .Err;
		}

		return .Ok;
	}

	/// Releases transient resources.
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
