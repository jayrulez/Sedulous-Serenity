namespace Sedulous.RendererNext;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Geometry;
using Sedulous.Mathematics;

/// Manages GPU resources (meshes, textures) and their lifetimes.
/// Provides handle-based access with generation tracking for safe resource reuse.
class GPUResourceManager
{
	private IDevice mDevice;

	// Static mesh storage
	private List<GPUStaticMesh> mStaticMeshes = new .() ~ DeleteContainerAndItems!(_);
	private List<uint32> mStaticMeshGenerations = new .() ~ delete _;
	private List<uint32> mFreeStaticMeshSlots = new .() ~ delete _;

	// Skinned mesh storage
	private List<GPUSkinnedMesh> mSkinnedMeshes = new .() ~ DeleteContainerAndItems!(_);
	private List<uint32> mSkinnedMeshGenerations = new .() ~ delete _;
	private List<uint32> mFreeSkinnedMeshSlots = new .() ~ delete _;

	// Texture storage
	private List<GPUTexture> mTextures = new .() ~ DeleteContainerAndItems!(_);
	private List<uint32> mTextureGenerations = new .() ~ delete _;
	private List<uint32> mFreeTextureSlots = new .() ~ delete _;

	/// Gets the device.
	public IDevice Device => mDevice;

	public this(IDevice device)
	{
		mDevice = device;
	}

	// ===== Static Mesh Management =====

	/// Creates a GPU static mesh from a CPU mesh.
	public GPUStaticMeshHandle CreateStaticMesh(StaticMesh cpuMesh)
	{
		if (cpuMesh == null || cpuMesh.Vertices == null)
			return .Invalid;

		let gpuMesh = new GPUStaticMesh();

		// Create vertex buffer
		let vertexDataSize = (uint64)cpuMesh.Vertices.GetDataSize();
		if (vertexDataSize > 0)
		{
			BufferDescriptor vertexDesc = .(vertexDataSize, .Vertex, .Upload);
			if (mDevice.CreateBuffer(&vertexDesc) case .Ok(let vb))
			{
				gpuMesh.VertexBuffer = vb;

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

		return AllocateStaticMeshSlot(gpuMesh);
	}

	/// Creates a GPU static mesh from raw vertex/index data.
	public GPUStaticMeshHandle CreateStaticMeshFromData(
		Span<uint8> vertexData, uint32 vertexStride, uint32 vertexCount,
		Span<uint8> indexData = default, IndexFormat indexFormat = .UInt32,
		BoundingBox bounds = default)
	{
		let gpuMesh = new GPUStaticMesh();

		// Create vertex buffer
		if (vertexData.Length > 0)
		{
			BufferDescriptor vertexDesc = .((uint64)vertexData.Length, .Vertex, .Upload);
			if (mDevice.CreateBuffer(&vertexDesc) case .Ok(let vb))
			{
				gpuMesh.VertexBuffer = vb;
				mDevice.Queue.WriteBuffer(vb, 0, vertexData);
			}
			else
			{
				delete gpuMesh;
				return .Invalid;
			}
		}

		// Create index buffer if provided
		if (indexData.Length > 0)
		{
			BufferDescriptor indexDesc = .((uint64)indexData.Length, .Index, .Upload);
			if (mDevice.CreateBuffer(&indexDesc) case .Ok(let ib))
			{
				gpuMesh.IndexBuffer = ib;
				mDevice.Queue.WriteBuffer(ib, 0, indexData);

				let indexSize = indexFormat == .UInt16 ? 2 : 4;
				gpuMesh.IndexCount = (uint32)(indexData.Length / indexSize);
				gpuMesh.IndexFormat = indexFormat;
			}
		}

		gpuMesh.VertexStride = vertexStride;
		gpuMesh.VertexCount = vertexCount;
		gpuMesh.Bounds = bounds;

		return AllocateStaticMeshSlot(gpuMesh);
	}

	/// Gets the GPU static mesh for a handle. Returns null if invalid.
	public GPUStaticMesh GetStaticMesh(GPUStaticMeshHandle handle)
	{
		if (!handle.IsValid || handle.Index >= mStaticMeshes.Count)
			return null;

		if (mStaticMeshGenerations[(int)handle.Index] != handle.Generation)
			return null;

		return mStaticMeshes[(int)handle.Index];
	}

	/// Releases a static mesh handle. Frees if reference count reaches zero.
	public void ReleaseStaticMesh(GPUStaticMeshHandle handle)
	{
		let mesh = GetStaticMesh(handle);
		if (mesh != null && mesh.Release())
		{
			FreeStaticMeshSlot(handle.Index);
		}
	}

	/// Adds a reference to a static mesh.
	public void AddStaticMeshRef(GPUStaticMeshHandle handle)
	{
		let mesh = GetStaticMesh(handle);
		if (mesh != null)
			mesh.AddRef();
	}

	// ===== Skinned Mesh Management =====

	/// Creates a GPU skinned mesh from a CPU skinned mesh.
	public GPUSkinnedMeshHandle CreateSkinnedMesh(SkinnedMesh cpuMesh)
	{
		if (cpuMesh == null || cpuMesh.VertexCount == 0)
			return .Invalid;

		let gpuMesh = new GPUSkinnedMesh();

		// Create vertex buffer
		let vertexDataSize = (uint64)(cpuMesh.VertexCount * cpuMesh.VertexSize);
		if (vertexDataSize > 0)
		{
			BufferDescriptor vertexDesc = .(vertexDataSize, .Vertex, .Upload);
			if (mDevice.CreateBuffer(&vertexDesc) case .Ok(let vb))
			{
				gpuMesh.VertexBuffer = vb;

				let vertexData = cpuMesh.GetVertexData();
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
		if (cpuMesh.IndexCount > 0)
		{
			let indexDataSize = (uint64)(cpuMesh.IndexCount * 4); // UInt32 indices
			BufferDescriptor indexDesc = .(indexDataSize, .Index, .Upload);
			if (mDevice.CreateBuffer(&indexDesc) case .Ok(let ib))
			{
				gpuMesh.IndexBuffer = ib;

				let indexData = cpuMesh.GetIndexData();
				if (indexData != null)
				{
					Span<uint8> data = .(indexData, (int)indexDataSize);
					mDevice.Queue.WriteBuffer(ib, 0, data);
				}

				gpuMesh.IndexCount = (uint32)cpuMesh.IndexCount;
				gpuMesh.IndexFormat = .UInt32;
			}
		}

		gpuMesh.VertexStride = (uint32)cpuMesh.VertexSize;
		gpuMesh.VertexCount = (uint32)cpuMesh.VertexCount;
		gpuMesh.Bounds = cpuMesh.Bounds;

		return AllocateSkinnedMeshSlot(gpuMesh);
	}

	/// Creates a GPU skinned mesh from raw vertex/index data.
	public GPUSkinnedMeshHandle CreateSkinnedMeshFromData(
		Span<uint8> vertexData, uint32 vertexStride, uint32 vertexCount, uint32 boneCount,
		Span<uint8> indexData = default, IndexFormat indexFormat = .UInt32,
		BoundingBox bounds = default)
	{
		let gpuMesh = new GPUSkinnedMesh();

		// Create vertex buffer
		if (vertexData.Length > 0)
		{
			BufferDescriptor vertexDesc = .((uint64)vertexData.Length, .Vertex, .Upload);
			if (mDevice.CreateBuffer(&vertexDesc) case .Ok(let vb))
			{
				gpuMesh.VertexBuffer = vb;
				mDevice.Queue.WriteBuffer(vb, 0, vertexData);
			}
			else
			{
				delete gpuMesh;
				return .Invalid;
			}
		}

		// Create index buffer if provided
		if (indexData.Length > 0)
		{
			BufferDescriptor indexDesc = .((uint64)indexData.Length, .Index, .Upload);
			if (mDevice.CreateBuffer(&indexDesc) case .Ok(let ib))
			{
				gpuMesh.IndexBuffer = ib;
				mDevice.Queue.WriteBuffer(ib, 0, indexData);

				let indexSize = indexFormat == .UInt16 ? 2 : 4;
				gpuMesh.IndexCount = (uint32)(indexData.Length / indexSize);
				gpuMesh.IndexFormat = indexFormat;
			}
		}

		gpuMesh.VertexStride = vertexStride;
		gpuMesh.VertexCount = vertexCount;
		gpuMesh.BoneCount = boneCount;
		gpuMesh.Bounds = bounds;

		return AllocateSkinnedMeshSlot(gpuMesh);
	}

	/// Gets the GPU skinned mesh for a handle. Returns null if invalid.
	public GPUSkinnedMesh GetSkinnedMesh(GPUSkinnedMeshHandle handle)
	{
		if (!handle.IsValid || handle.Index >= mSkinnedMeshes.Count)
			return null;

		if (mSkinnedMeshGenerations[(int)handle.Index] != handle.Generation)
			return null;

		return mSkinnedMeshes[(int)handle.Index];
	}

	/// Releases a skinned mesh handle. Frees if reference count reaches zero.
	public void ReleaseSkinnedMesh(GPUSkinnedMeshHandle handle)
	{
		let mesh = GetSkinnedMesh(handle);
		if (mesh != null && mesh.Release())
		{
			FreeSkinnedMeshSlot(handle.Index);
		}
	}

	/// Adds a reference to a skinned mesh.
	public void AddSkinnedMeshRef(GPUSkinnedMeshHandle handle)
	{
		let mesh = GetSkinnedMesh(handle);
		if (mesh != null)
			mesh.AddRef();
	}

	// ===== Texture Management =====

	/// Creates a GPU texture from raw pixel data.
	public GPUTextureHandle CreateTexture2D(uint32 width, uint32 height, TextureFormat format, Span<uint8> data, bool generateMips = false)
	{
		let gpuTexture = new GPUTexture();
		gpuTexture.Width = width;
		gpuTexture.Height = height;
		gpuTexture.Format = format;
		gpuTexture.Dimension = .Texture2D;

		// Calculate mip levels
		uint32 mipLevels = 1;
		if (generateMips)
		{
			mipLevels = CalculateMipLevels(width, height);
		}
		gpuTexture.MipLevels = mipLevels;

		TextureDescriptor texDesc = .Texture2D(width, height, format, .Sampled | .CopyDst, mipLevels);

		if (mDevice.CreateTexture(&texDesc) case .Ok(let texture))
		{
			gpuTexture.Texture = texture;

			// Upload texture data
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

	/// Creates an empty GPU texture (for render targets, etc.).
	public GPUTextureHandle CreateTexture2DEmpty(uint32 width, uint32 height, TextureFormat format, TextureUsage usage = .Sampled | .RenderTarget)
	{
		let gpuTexture = new GPUTexture();
		gpuTexture.Width = width;
		gpuTexture.Height = height;
		gpuTexture.Format = format;
		gpuTexture.Dimension = .Texture2D;
		gpuTexture.MipLevels = 1;

		TextureDescriptor texDesc = .Texture2D(width, height, format, usage, 1);

		if (mDevice.CreateTexture(&texDesc) case .Ok(let texture))
		{
			gpuTexture.Texture = texture;

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

	/// Releases a texture handle. Frees if reference count reaches zero.
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

	// ===== Slot Management =====

	private GPUStaticMeshHandle AllocateStaticMeshSlot(GPUStaticMesh mesh)
	{
		uint32 index;
		uint32 generation;

		if (mFreeStaticMeshSlots.Count > 0)
		{
			index = mFreeStaticMeshSlots.PopBack();
			generation = mStaticMeshGenerations[(int)index];
			mStaticMeshes[(int)index] = mesh;
		}
		else
		{
			index = (uint32)mStaticMeshes.Count;
			generation = 0;
			mStaticMeshes.Add(mesh);
			mStaticMeshGenerations.Add(generation);
		}

		return .(index, generation);
	}

	private void FreeStaticMeshSlot(uint32 index)
	{
		if (index < mStaticMeshes.Count)
		{
			delete mStaticMeshes[(int)index];
			mStaticMeshes[(int)index] = null;
			mStaticMeshGenerations[(int)index]++;
			mFreeStaticMeshSlots.Add(index);
		}
	}

	private GPUSkinnedMeshHandle AllocateSkinnedMeshSlot(GPUSkinnedMesh mesh)
	{
		uint32 index;
		uint32 generation;

		if (mFreeSkinnedMeshSlots.Count > 0)
		{
			index = mFreeSkinnedMeshSlots.PopBack();
			generation = mSkinnedMeshGenerations[(int)index];
			mSkinnedMeshes[(int)index] = mesh;
		}
		else
		{
			index = (uint32)mSkinnedMeshes.Count;
			generation = 0;
			mSkinnedMeshes.Add(mesh);
			mSkinnedMeshGenerations.Add(generation);
		}

		return .(index, generation);
	}

	private void FreeSkinnedMeshSlot(uint32 index)
	{
		if (index < mSkinnedMeshes.Count)
		{
			delete mSkinnedMeshes[(int)index];
			mSkinnedMeshes[(int)index] = null;
			mSkinnedMeshGenerations[(int)index]++;
			mFreeSkinnedMeshSlots.Add(index);
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

	// ===== Helper Methods =====

	/// Gets bytes per pixel for a texture format.
	public static uint32 GetBytesPerPixel(TextureFormat format)
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
	public static uint32 CalculateMipLevels(uint32 width, uint32 height)
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

	// ===== Statistics =====

	/// Number of static meshes currently allocated.
	public int32 StaticMeshCount => (int32)(mStaticMeshes.Count - mFreeStaticMeshSlots.Count);

	/// Number of skinned meshes currently allocated.
	public int32 SkinnedMeshCount => (int32)(mSkinnedMeshes.Count - mFreeSkinnedMeshSlots.Count);

	/// Number of textures currently allocated.
	public int32 TextureCount => (int32)(mTextures.Count - mFreeTextureSlots.Count);
}
