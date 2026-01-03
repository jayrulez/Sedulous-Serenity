namespace Sedulous.Framework.Renderer;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Geometry;
using Sedulous.Imaging;
using Sedulous.Mathematics;

/// Manages GPU resources (meshes, textures) and their lifetimes.
/// Provides caching and reference counting for efficient resource reuse.
class GPUResourceManager
{
	private IDevice mDevice;

	// Mesh storage
	private List<GPUMesh> mMeshes = new .() ~ DeleteContainerAndItems!(_);
	private List<uint32> mMeshGenerations = new .() ~ delete _;
	private List<uint32> mFreeMeshSlots = new .() ~ delete _;

	// Texture storage
	private List<GPUTexture> mTextures = new .() ~ DeleteContainerAndItems!(_);
	private List<uint32> mTextureGenerations = new .() ~ delete _;
	private List<uint32> mFreeTextureSlots = new .() ~ delete _;

	public this(IDevice device)
	{
		mDevice = device;
	}

	// ===== Mesh Management =====

	/// Creates a GPU mesh from a CPU mesh.
	/// Returns a handle to the GPU mesh, or Invalid on failure.
	public GPUMeshHandle CreateMesh(Mesh cpuMesh)
	{
		if (cpuMesh == null || cpuMesh.Vertices == null)
			return .Invalid;

		let gpuMesh = new GPUMesh();

		// Create vertex buffer
		let vertexDataSize = (uint64)cpuMesh.Vertices.GetDataSize();
		if (vertexDataSize > 0)
		{
			BufferDescriptor vertexDesc = .(vertexDataSize, .Vertex, .Upload);
			if (mDevice.CreateBuffer(&vertexDesc) case .Ok(let vb))
			{
				gpuMesh.VertexBuffer = vb;

				// Upload vertex data
				let vertexData = cpuMesh.Vertices.GetRawData();
				if (vertexData != null)
				{
					Span<uint8> data = .(vertexData, (int)vertexDataSize);
					mDevice.Queue.WriteBuffer(vb, 0, data);
				}
			}
			else
			{
				delete gpuMesh;
				return .Invalid;
			}
		}

		// Create index buffer if mesh has indices
		if (cpuMesh.Indices != null && cpuMesh.Indices.IndexCount > 0)
		{
			let indexDataSize = (uint64)cpuMesh.Indices.GetDataSize();
			BufferDescriptor indexDesc = .(indexDataSize, .Index, .Upload);
			if (mDevice.CreateBuffer(&indexDesc) case .Ok(let ib))
			{
				gpuMesh.IndexBuffer = ib;

				// Upload index data
				let indexData = cpuMesh.Indices.GetRawData();
				if (indexData != null)
				{
					Span<uint8> data = .(indexData, (int)indexDataSize);
					mDevice.Queue.WriteBuffer(ib, 0, data);
				}

				gpuMesh.IndexCount = (uint32)cpuMesh.Indices.IndexCount;
				gpuMesh.IndexFormat = cpuMesh.Indices.Format == .UInt16 ? .UInt16 : .UInt32;
			}
		}

		gpuMesh.VertexStride = (uint32)cpuMesh.Vertices.VertexSize;
		gpuMesh.VertexCount = (uint32)cpuMesh.Vertices.VertexCount;
		gpuMesh.Bounds = cpuMesh.GetBounds();

		// Copy sub-meshes
		if (cpuMesh.SubMeshes != null && cpuMesh.SubMeshes.Count > 0)
		{
			gpuMesh.SubMeshes = new SubMesh[cpuMesh.SubMeshes.Count];
			for (int i = 0; i < cpuMesh.SubMeshes.Count; i++)
			{
				gpuMesh.SubMeshes[i] = cpuMesh.SubMeshes[i];
			}
		}

		return AllocateMeshSlot(gpuMesh);
	}

	/// Gets the GPU mesh for a handle. Returns null if invalid.
	public GPUMesh GetMesh(GPUMeshHandle handle)
	{
		if (!handle.IsValid || handle.Index >= mMeshes.Count)
			return null;

		if (mMeshGenerations[(int)handle.Index] != handle.Generation)
			return null;

		return mMeshes[(int)handle.Index];
	}

	/// Releases a mesh handle. Frees the GPU mesh if reference count reaches zero.
	public void ReleaseMesh(GPUMeshHandle handle)
	{
		let mesh = GetMesh(handle);
		if (mesh != null && mesh.Release())
		{
			FreeMeshSlot(handle.Index);
		}
	}

	/// Adds a reference to a mesh.
	public void AddMeshRef(GPUMeshHandle handle)
	{
		let mesh = GetMesh(handle);
		if (mesh != null)
			mesh.AddRef();
	}

	// ===== Texture Management =====

	/// Creates a GPU texture from a CPU image.
	/// Returns a handle to the GPU texture, or Invalid on failure.
	public GPUTextureHandle CreateTexture(Image cpuImage, bool generateMips = false)
	{
		if (cpuImage == null)
			return .Invalid;

		let gpuTexture = new GPUTexture();
		gpuTexture.Width = cpuImage.Width;
		gpuTexture.Height = cpuImage.Height;
		gpuTexture.Format = ConvertPixelFormat(cpuImage.Format);

		// Calculate mip levels
		uint32 mipLevels = 1;
		if (generateMips)
		{
			mipLevels = CalculateMipLevels(cpuImage.Width, cpuImage.Height);
		}
		gpuTexture.MipLevels = mipLevels;

		// Create texture
		TextureDescriptor texDesc = .Texture2D(
			cpuImage.Width,
			cpuImage.Height,
			gpuTexture.Format,
			.Sampled | .CopyDst,
			mipLevels
		);

		if (mDevice.CreateTexture(&texDesc) case .Ok(let texture))
		{
			gpuTexture.Texture = texture;

			// Upload texture data
			let imageData = cpuImage.Data;
			if (imageData.Length > 0)
			{
				// Calculate bytes per row with proper alignment
				uint32 bytesPerPixel = (uint32)Image.GetBytesPerPixel(cpuImage.Format);
				uint32 bytesPerRow = cpuImage.Width * bytesPerPixel;

				TextureDataLayout layout = .()
				{
					Offset = 0,
					BytesPerRow = bytesPerRow,
					RowsPerImage = cpuImage.Height
				};

				Extent3D size = .(cpuImage.Width, cpuImage.Height, 1);

				mDevice.Queue.WriteTexture(texture, imageData, &layout, &size);
			}

			// Create default view
			TextureViewDescriptor viewDesc = .();
			if (mDevice.CreateTextureView(texture, &viewDesc) case .Ok(let view))
			{
				gpuTexture.View = view;
			}
			else
			{
				delete gpuTexture;
				return .Invalid;
			}
		}
		else
		{
			delete gpuTexture;
			return .Invalid;
		}

		return AllocateTextureSlot(gpuTexture);
	}

	/// Creates a GPU texture from raw data.
	public GPUTextureHandle CreateTextureFromData(uint32 width, uint32 height, TextureFormat format, Span<uint8> data)
	{
		let gpuTexture = new GPUTexture();
		gpuTexture.Width = width;
		gpuTexture.Height = height;
		gpuTexture.Format = format;
		gpuTexture.MipLevels = 1;

		TextureDescriptor texDesc = .Texture2D(width, height, format, .Sampled | .CopyDst, 1);

		if (mDevice.CreateTexture(&texDesc) case .Ok(let texture))
		{
			gpuTexture.Texture = texture;

			if (data.Length > 0)
			{
				uint32 bytesPerPixel = GetBytesPerPixel(format);
				uint32 bytesPerRow = width * bytesPerPixel;

				TextureDataLayout layout = .()
				{
					Offset = 0,
					BytesPerRow = bytesPerRow,
					RowsPerImage = height
				};

				Extent3D size = .(width, height, 1);
				mDevice.Queue.WriteTexture(texture, data, &layout, &size);
			}

			TextureViewDescriptor viewDesc = .();
			if (mDevice.CreateTextureView(texture, &viewDesc) case .Ok(let view))
			{
				gpuTexture.View = view;
			}
			else
			{
				delete gpuTexture;
				return .Invalid;
			}
		}
		else
		{
			delete gpuTexture;
			return .Invalid;
		}

		return AllocateTextureSlot(gpuTexture);
	}

	/// Gets the GPU texture for a handle. Returns null if invalid.
	public GPUTexture GetTexture(GPUTextureHandle handle)
	{
		if (!handle.IsValid || handle.Index >= mTextures.Count)
			return null;

		if (mTextureGenerations[(int)handle.Index] != handle.Generation)
			return null;

		return mTextures[(int)handle.Index];
	}

	/// Releases a texture handle. Frees the GPU texture if reference count reaches zero.
	public void ReleaseTexture(GPUTextureHandle handle)
	{
		let texture = GetTexture(handle);
		if (texture != null && texture.Release())
		{
			FreeTextureSlot(handle.Index);
		}
	}

	/// Adds a reference to a texture.
	public void AddTextureRef(GPUTextureHandle handle)
	{
		let texture = GetTexture(handle);
		if (texture != null)
			texture.AddRef();
	}

	// ===== Helper Methods =====

	private GPUMeshHandle AllocateMeshSlot(GPUMesh mesh)
	{
		uint32 index;
		uint32 generation;

		if (mFreeMeshSlots.Count > 0)
		{
			index = mFreeMeshSlots.PopBack();
			generation = mMeshGenerations[(int)index];
			mMeshes[(int)index] = mesh;
		}
		else
		{
			index = (uint32)mMeshes.Count;
			generation = 0;
			mMeshes.Add(mesh);
			mMeshGenerations.Add(generation);
		}

		return .(index, generation);
	}

	private void FreeMeshSlot(uint32 index)
	{
		if (index < mMeshes.Count)
		{
			delete mMeshes[(int)index];
			mMeshes[(int)index] = null;
			mMeshGenerations[(int)index]++;
			mFreeMeshSlots.Add(index);
		}
	}

	private GPUTextureHandle AllocateTextureSlot(GPUTexture texture)
	{
		uint32 index;
		uint32 generation;

		if (mFreeTextureSlots.Count > 0)
		{
			index = mFreeTextureSlots.PopBack();
			generation = mTextureGenerations[(int)index];
			mTextures[(int)index] = texture;
		}
		else
		{
			index = (uint32)mTextures.Count;
			generation = 0;
			mTextures.Add(texture);
			mTextureGenerations.Add(generation);
		}

		return .(index, generation);
	}

	private void FreeTextureSlot(uint32 index)
	{
		if (index < mTextures.Count)
		{
			delete mTextures[(int)index];
			mTextures[(int)index] = null;
			mTextureGenerations[(int)index]++;
			mFreeTextureSlots.Add(index);
		}
	}

	/// Converts Image.PixelFormat to RHI TextureFormat.
	private static TextureFormat ConvertPixelFormat(Image.PixelFormat format)
	{
		switch (format)
		{
		case .R8:       return .R8Unorm;
		case .RG8:      return .RG8Unorm;
		case .RGB8:     return .RGBA8Unorm; // Note: Most GPUs don't support RGB8, use RGBA8
		case .RGBA8:    return .RGBA8Unorm;
		case .BGR8:     return .BGRA8Unorm; // Note: Most GPUs don't support BGR8, use BGRA8
		case .BGRA8:    return .BGRA8Unorm;
		case .R16F:     return .R16Float;
		case .RG16F:    return .RG16Float;
		case .RGB16F:   return .RGBA16Float; // Note: Most GPUs don't support RGB16F
		case .RGBA16F:  return .RGBA16Float;
		case .R32F:     return .R32Float;
		case .RG32F:    return .RG32Float;
		case .RGB32F:   return .RGBA32Float; // Note: Most GPUs don't support RGB32F
		case .RGBA32F:  return .RGBA32Float;
		default:        return .RGBA8Unorm;
		}
	}

	/// Gets bytes per pixel for a texture format.
	private static uint32 GetBytesPerPixel(TextureFormat format)
	{
		switch (format)
		{
		case .R8Unorm, .R8Snorm, .R8Uint, .R8Sint:
			return 1;
		case .R16Uint, .R16Sint, .R16Float, .RG8Unorm, .RG8Snorm, .RG8Uint, .RG8Sint:
			return 2;
		case .R32Uint, .R32Sint, .R32Float, .RG16Uint, .RG16Sint, .RG16Float,
			 .RGBA8Unorm, .RGBA8UnormSrgb, .RGBA8Snorm, .RGBA8Uint, .RGBA8Sint,
			 .BGRA8Unorm, .BGRA8UnormSrgb, .RGB10A2Unorm, .RG11B10Float:
			return 4;
		case .RG32Uint, .RG32Sint, .RG32Float, .RGBA16Uint, .RGBA16Sint, .RGBA16Float:
			return 8;
		case .RGBA32Uint, .RGBA32Sint, .RGBA32Float:
			return 16;
		default:
			return 4;
		}
	}

	/// Calculates the number of mip levels for a texture.
	private static uint32 CalculateMipLevels(uint32 width, uint32 height)
	{
		uint32 maxDim = Math.Max(width, height);
		uint32 levels = 1;
		while (maxDim > 1)
		{
			maxDim >>= 1;
			levels++;
		}
		return levels;
	}
}
