namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Geometry;
using Sedulous.Mathematics;

/// Pending deletion entry.
struct PendingDeletion
{
	public enum Type { Mesh, Texture, BoneBuffer }
	public Type ResourceType;
	public uint32 Index;
	public uint64 FrameNumber;
}

/// GPU-side bone buffer for skinned mesh animation.
public class GPUBoneBuffer
{
	/// Storage buffer for bone matrices.
	public IBuffer Buffer;

	/// Number of bones this buffer supports.
	public uint16 BoneCount;

	/// Size in bytes.
	public uint64 Size;

	/// Reference count.
	public int32 RefCount;

	/// Generation for handle validation.
	public uint32 Generation;

	/// Whether this slot is in use.
	public bool IsActive;

	/// Frees GPU resources.
	public void Release()
	{
		if (Buffer != null)
		{
			delete Buffer;
			Buffer = null;
		}
		IsActive = false;
	}
}

/// Manages GPU resources (meshes, textures) with reference counting and deferred deletion.
public class GPUResourceManager : IDisposable
{
	private IDevice mDevice;

	// Mesh storage
	private List<GPUMesh> mMeshes = new .() ~ DeleteContainerAndItems!(_);
	private List<int32> mFreeMeshSlots = new .() ~ delete _;

	// Texture storage
	private List<GPUTexture> mTextures = new .() ~ DeleteContainerAndItems!(_);
	private List<int32> mFreeTextureSlots = new .() ~ delete _;

	// Bone buffer storage
	private List<GPUBoneBuffer> mBoneBuffers = new .() ~ DeleteContainerAndItems!(_);
	private List<int32> mFreeBoneBufferSlots = new .() ~ delete _;

	// Pending deletions (deferred to allow GPU to finish using resources)
	private List<PendingDeletion> mPendingDeletions = new .() ~ delete _;

	// Frames to wait before actually deleting (triple buffering)
	private const uint64 DeletionDelay = RenderConfig.FrameBufferCount + 1;

	/// Gets the device.
	public IDevice Device => mDevice;

	/// Initializes the manager.
	public Result<void> Initialize(IDevice device)
	{
		mDevice = device;
		return .Ok;
	}

	// ========================================================================
	// Mesh API
	// ========================================================================

	/// Uploads a static mesh to the GPU.
	public Result<GPUMeshHandle> UploadMesh(StaticMesh mesh)
	{
		if (mesh == null || mesh.Vertices == null || mesh.Indices == null)
			return .Err;

		let vertices = mesh.Vertices;
		let indices = mesh.Indices;

		if (vertices.VertexCount == 0 || indices.IndexCount == 0)
			return .Err;

		// Allocate slot
		GPUMesh gpuMesh;
		uint32 index;
		uint32 generation;

		if (mFreeMeshSlots.Count > 0)
		{
			index = (uint32)mFreeMeshSlots.PopBack();
			gpuMesh = mMeshes[(int)index];
			generation = gpuMesh.Generation + 1;
		}
		else
		{
			index = (uint32)mMeshes.Count;
			gpuMesh = new GPUMesh();
			mMeshes.Add(gpuMesh);
			generation = 1;
		}

		// Create vertex buffer
		let vertexDataSize = (uint64)(vertices.VertexCount * vertices.VertexSize);
		var vbDesc = BufferDescriptor()
		{
			Size = vertexDataSize,
			Usage = .Vertex | .CopyDst
		};

		if (mDevice.CreateBuffer(&vbDesc) case .Ok(let vb))
		{
			gpuMesh.VertexBuffer = vb;
			mDevice.Queue.WriteBuffer(vb, 0, Span<uint8>(vertices.GetRawData(), (int)vertexDataSize));
		}
		else
		{
			return .Err;
		}

		// Create index buffer
		let indexSize = indices.Format == .UInt16 ? 2 : 4;
		let indexDataSize = (uint64)(indices.IndexCount * indexSize);
		var ibDesc = BufferDescriptor()
		{
			Size = indexDataSize,
			Usage = .Index | .CopyDst
		};

		if (mDevice.CreateBuffer(&ibDesc) case .Ok(let ib))
		{
			gpuMesh.IndexBuffer = ib;
			mDevice.Queue.WriteBuffer(ib, 0, Span<uint8>(indices.GetRawData(), (int)indexDataSize));
		}
		else
		{
			delete gpuMesh.VertexBuffer;
			gpuMesh.VertexBuffer = null;
			return .Err;
		}

		// Set mesh properties
		gpuMesh.VertexCount = (uint32)vertices.VertexCount;
		gpuMesh.IndexCount = (uint32)indices.IndexCount;
		gpuMesh.VertexStride = (uint32)vertices.VertexSize;
		gpuMesh.IndexFormat = indices.Format == .UInt16 ? .UInt16 : .UInt32;
		gpuMesh.Bounds = mesh.GetBounds();
		gpuMesh.RefCount = 1;
		gpuMesh.Generation = generation;
		gpuMesh.IsActive = true;

		// Copy submeshes
		if (mesh.SubMeshes != null && mesh.SubMeshes.Count > 0)
		{
			gpuMesh.SubMeshes = new GPUSubMesh[mesh.SubMeshes.Count];
			for (int i = 0; i < mesh.SubMeshes.Count; i++)
			{
				let sub = mesh.SubMeshes[i];
				gpuMesh.SubMeshes[i] = .()
				{
					IndexStart = (uint32)sub.startIndex,
					IndexCount = (uint32)sub.indexCount,
					BaseVertex = 0,
					MaterialSlot = (uint32)sub.materialIndex
				};
			}
		}
		else
		{
			// Single submesh for entire mesh
			gpuMesh.SubMeshes = new GPUSubMesh[1];
			gpuMesh.SubMeshes[0] = .()
			{
				IndexStart = 0,
				IndexCount = gpuMesh.IndexCount,
				BaseVertex = 0,
				MaterialSlot = 0
			};
		}

		return .Ok(.() { Index = index, Generation = generation });
	}

	/// Gets a GPU mesh by handle.
	public GPUMesh GetMesh(GPUMeshHandle handle)
	{
		if (!handle.IsValid || handle.Index >= mMeshes.Count)
			return null;

		let mesh = mMeshes[(int)handle.Index];
		if (!mesh.IsActive || mesh.Generation != handle.Generation)
			return null;

		return mesh;
	}

	/// Adds a reference to a mesh.
	public void AddMeshRef(GPUMeshHandle handle)
	{
		if (let mesh = GetMesh(handle))
			mesh.RefCount++;
	}

	/// Releases a reference to a mesh.
	public void ReleaseMesh(GPUMeshHandle handle, uint64 frameNumber)
	{
		if (let mesh = GetMesh(handle))
		{
			mesh.RefCount--;
			if (mesh.RefCount <= 0)
			{
				// Schedule for deletion
				mPendingDeletions.Add(.()
				{
					ResourceType = .Mesh,
					Index = handle.Index,
					FrameNumber = frameNumber
				});
			}
		}
	}

	/// Uploads a skinned mesh to the GPU.
	/// Supports both indexed and non-indexed meshes.
	public Result<GPUMeshHandle> UploadMesh(SkinnedMesh mesh)
	{
		if (mesh == null || mesh.Vertices == null)
			return .Err;

		if (mesh.VertexCount == 0)
			return .Err;

		// Allocate slot
		GPUMesh gpuMesh;
		uint32 index;
		uint32 generation;

		if (mFreeMeshSlots.Count > 0)
		{
			index = (uint32)mFreeMeshSlots.PopBack();
			gpuMesh = mMeshes[(int)index];
			generation = gpuMesh.Generation + 1;
		}
		else
		{
			index = (uint32)mMeshes.Count;
			gpuMesh = new GPUMesh();
			mMeshes.Add(gpuMesh);
			generation = 1;
		}

		// Create vertex buffer (with Storage for GPU skinning compute shader access)
		let vertexDataSize = (uint64)(mesh.VertexCount * mesh.VertexSize);
		var vbDesc = BufferDescriptor()
		{
			Size = vertexDataSize,
			Usage = .Vertex | .Storage | .CopyDst
		};

		if (mDevice.CreateBuffer(&vbDesc) case .Ok(let vb))
		{
			gpuMesh.VertexBuffer = vb;
			mDevice.Queue.WriteBuffer(vb, 0, Span<uint8>(mesh.GetVertexData(), (int)vertexDataSize));
		}
		else
		{
			return .Err;
		}

		// Create index buffer (if mesh has indices)
		let indices = mesh.Indices;
		let hasIndices = indices != null && indices.IndexCount > 0;

		if (hasIndices)
		{
			let indexSize = indices.Format == .UInt16 ? 2 : 4;
			let indexDataSize = (uint64)(indices.IndexCount * indexSize);
			var ibDesc = BufferDescriptor()
			{
				Size = indexDataSize,
				Usage = .Index | .CopyDst
			};

			if (mDevice.CreateBuffer(&ibDesc) case .Ok(let ib))
			{
				gpuMesh.IndexBuffer = ib;
				mDevice.Queue.WriteBuffer(ib, 0, Span<uint8>(mesh.GetIndexData(), (int)indexDataSize));
			}
			else
			{
				delete gpuMesh.VertexBuffer;
				gpuMesh.VertexBuffer = null;
				return .Err;
			}
		}
		else
		{
			gpuMesh.IndexBuffer = null;
		}

		// Set mesh properties
		gpuMesh.VertexCount = (uint32)mesh.VertexCount;
		gpuMesh.IndexCount = hasIndices ? (uint32)indices.IndexCount : 0;
		gpuMesh.VertexStride = (uint32)mesh.VertexSize;
		gpuMesh.IndexFormat = hasIndices && indices.Format == .UInt16 ? .UInt16 : .UInt32;
		gpuMesh.Bounds = mesh.Bounds;
		gpuMesh.RefCount = 1;
		gpuMesh.Generation = generation;
		gpuMesh.IsActive = true;
		gpuMesh.IsSkinned = true;

		// Copy submeshes
		if (mesh.SubMeshes != null && mesh.SubMeshes.Count > 0)
		{
			gpuMesh.SubMeshes = new GPUSubMesh[mesh.SubMeshes.Count];
			for (int i = 0; i < mesh.SubMeshes.Count; i++)
			{
				let sub = mesh.SubMeshes[i];
				gpuMesh.SubMeshes[i] = .()
				{
					IndexStart = (uint32)sub.startIndex,
					IndexCount = (uint32)sub.indexCount,
					BaseVertex = 0,
					MaterialSlot = (uint32)sub.materialIndex
				};
			}
		}
		else
		{
			// Single submesh for entire mesh - use vertex count for non-indexed meshes
			gpuMesh.SubMeshes = new GPUSubMesh[1];
			gpuMesh.SubMeshes[0] = .()
			{
				IndexStart = 0,
				IndexCount = hasIndices ? gpuMesh.IndexCount : gpuMesh.VertexCount,
				BaseVertex = 0,
				MaterialSlot = 0
			};
		}

		return .Ok(.() { Index = index, Generation = generation });
	}

	// ========================================================================
	// Bone Buffer API
	// ========================================================================

	/// Creates a bone buffer for a skinned mesh.
	public Result<GPUBoneBufferHandle> CreateBoneBuffer(uint16 boneCount)
	{
		if (boneCount == 0 || boneCount > RenderConfig.MaxBonesPerMesh)
			return .Err;

		// Allocate slot
		GPUBoneBuffer boneBuffer;
		uint32 index;
		uint32 generation;

		if (mFreeBoneBufferSlots.Count > 0)
		{
			index = (uint32)mFreeBoneBufferSlots.PopBack();
			boneBuffer = mBoneBuffers[(int)index];
			generation = boneBuffer.Generation + 1;
		}
		else
		{
			index = (uint32)mBoneBuffers.Count;
			boneBuffer = new GPUBoneBuffer();
			mBoneBuffers.Add(boneBuffer);
			generation = 1;
		}

		// Size: current + previous frame matrices for each bone
		let bufferSize = BoneTransforms.GetSizeForBoneCount((int32)boneCount);

		var bufDesc = BufferDescriptor()
		{
			Size = bufferSize,
			Usage = .Storage,
			MemoryAccess = .Upload
		};

		if (mDevice.CreateBuffer(&bufDesc) case .Ok(let buffer))
		{
			boneBuffer.Buffer = buffer;
			boneBuffer.BoneCount = boneCount;
			boneBuffer.Size = bufferSize;
			boneBuffer.RefCount = 1;
			boneBuffer.Generation = generation;
			boneBuffer.IsActive = true;

			return .Ok(.() { Index = index, Generation = generation });
		}

		return .Err;
	}

	/// Gets a bone buffer by handle.
	public GPUBoneBuffer GetBoneBuffer(GPUBoneBufferHandle handle)
	{
		if (!handle.IsValid || handle.Index >= mBoneBuffers.Count)
			return null;

		let buffer = mBoneBuffers[(int)handle.Index];
		if (!buffer.IsActive || buffer.Generation != handle.Generation)
			return null;

		return buffer;
	}

	/// Updates bone transforms in a bone buffer.
	public void UpdateBoneBuffer(GPUBoneBufferHandle handle, Matrix* currentBones, Matrix* prevBones, uint16 boneCount)
	{
		if (let buffer = GetBoneBuffer(handle))
		{
			var actualBoneCount = boneCount;
			if (actualBoneCount > buffer.BoneCount)
				actualBoneCount = buffer.BoneCount;

			let matrixSize = (uint64)(sizeof(Matrix) * actualBoneCount);

			// Upload current frame matrices
			mDevice.Queue.WriteBuffer(buffer.Buffer, 0, Span<uint8>((uint8*)currentBones, (int)matrixSize));

			// Upload previous frame matrices (offset by buffer's bone count, not MaxBones)
			let prevOffset = (uint64)(sizeof(Matrix) * buffer.BoneCount);
			mDevice.Queue.WriteBuffer(buffer.Buffer, prevOffset, Span<uint8>((uint8*)prevBones, (int)matrixSize));
		}
	}

	/// Adds a reference to a bone buffer.
	public void AddBoneBufferRef(GPUBoneBufferHandle handle)
	{
		if (let buffer = GetBoneBuffer(handle))
			buffer.RefCount++;
	}

	/// Releases a reference to a bone buffer.
	public void ReleaseBoneBuffer(GPUBoneBufferHandle handle, uint64 frameNumber)
	{
		if (let buffer = GetBoneBuffer(handle))
		{
			buffer.RefCount--;
			if (buffer.RefCount <= 0)
			{
				mPendingDeletions.Add(.()
				{
					ResourceType = .BoneBuffer,
					Index = handle.Index,
					FrameNumber = frameNumber
				});
			}
		}
	}

	// ========================================================================
	// Texture API
	// ========================================================================

	/// Uploads texture data to the GPU.
	public Result<GPUTextureHandle> UploadTexture(TextureData data)
	{
		if (data.Pixels == null || data.Size == 0)
			return .Err;

		// Allocate slot
		GPUTexture gpuTexture;
		uint32 index;
		uint32 generation;

		if (mFreeTextureSlots.Count > 0)
		{
			index = (uint32)mFreeTextureSlots.PopBack();
			gpuTexture = mTextures[(int)index];
			generation = gpuTexture.Generation + 1;
		}
		else
		{
			index = (uint32)mTextures.Count;
			gpuTexture = new GPUTexture();
			mTextures.Add(gpuTexture);
			generation = 1;
		}

		// Create texture
		var texDesc = TextureDescriptor()
		{
			Width = data.Width,
			Height = data.Height,
			Depth = 1,
			ArrayLayerCount = data.DepthOrArrayLayers,
			MipLevelCount = data.MipLevels,
			Format = data.Format,
			Usage = .Sampled | .CopyDst,
			Dimension = data.Dimension,
			SampleCount = 1
		};

		if (mDevice.CreateTexture(&texDesc) case .Ok(let tex))
		{
			gpuTexture.Texture = tex;

			// Upload pixel data
			let bpp = TextureData.GetBytesPerPixel(data.Format);
			var bytesPerRow = data.BytesPerRow;
			if (bytesPerRow == 0)
				bytesPerRow = data.Width * bpp;

			var rowsPerImage = data.RowsPerImage;
			if (rowsPerImage == 0)
				rowsPerImage = data.Height;

			var dataLayout = TextureDataLayout()
			{
				Offset = 0,
				BytesPerRow = bytesPerRow,
				RowsPerImage = rowsPerImage
			};

			var writeSize = Extent3D(data.Width, data.Height, data.DepthOrArrayLayers);

			mDevice.Queue.WriteTexture(tex, Span<uint8>(data.Pixels, (int)data.Size), &dataLayout, &writeSize, 0, 0);

			// Create default view
			var viewDesc = TextureViewDescriptor()
			{
				Format = data.Format,
				Dimension = data.DepthOrArrayLayers == 6 ? .TextureCube : .Texture2D,
				BaseMipLevel = 0,
				MipLevelCount = data.MipLevels,
				BaseArrayLayer = 0,
				ArrayLayerCount = data.DepthOrArrayLayers
			};

			if (mDevice.CreateTextureView(tex, &viewDesc) case .Ok(let view))
				gpuTexture.DefaultView = view;
			else
			{
				delete tex;
				return .Err;
			}
		}
		else
		{
			return .Err;
		}

		gpuTexture.Width = data.Width;
		gpuTexture.Height = data.Height;
		gpuTexture.DepthOrArrayLayers = data.DepthOrArrayLayers;
		gpuTexture.MipLevels = data.MipLevels;
		gpuTexture.Format = data.Format;
		gpuTexture.RefCount = 1;
		gpuTexture.Generation = generation;
		gpuTexture.IsActive = true;

		return .Ok(.() { Index = index, Generation = generation });
	}

	/// Creates an empty render target texture.
	public Result<GPUTextureHandle> CreateRenderTarget(uint32 width, uint32 height, TextureFormat format, TextureUsage usage = .RenderTarget | .Sampled)
	{
		// Allocate slot
		GPUTexture gpuTexture;
		uint32 index;
		uint32 generation;

		if (mFreeTextureSlots.Count > 0)
		{
			index = (uint32)mFreeTextureSlots.PopBack();
			gpuTexture = mTextures[(int)index];
			generation = gpuTexture.Generation + 1;
		}
		else
		{
			index = (uint32)mTextures.Count;
			gpuTexture = new GPUTexture();
			mTextures.Add(gpuTexture);
			generation = 1;
		}

		var texDesc = TextureDescriptor()
		{
			Width = width,
			Height = height,
			Depth = 1,
			ArrayLayerCount = 1,
			MipLevelCount = 1,
			Format = format,
			Usage = usage,
			Dimension = .Texture2D,
			SampleCount = 1
		};

		if (mDevice.CreateTexture(&texDesc) case .Ok(let tex))
		{
			gpuTexture.Texture = tex;

			var viewDesc = TextureViewDescriptor()
			{
				Format = format,
				Dimension = .Texture2D,
				BaseMipLevel = 0,
				MipLevelCount = 1,
				BaseArrayLayer = 0,
				ArrayLayerCount = 1
			};

			if (mDevice.CreateTextureView(tex, &viewDesc) case .Ok(let view))
				gpuTexture.DefaultView = view;
			else
			{
				delete tex;
				return .Err;
			}
		}
		else
		{
			return .Err;
		}

		gpuTexture.Width = width;
		gpuTexture.Height = height;
		gpuTexture.DepthOrArrayLayers = 1;
		gpuTexture.MipLevels = 1;
		gpuTexture.Format = format;
		gpuTexture.RefCount = 1;
		gpuTexture.Generation = generation;
		gpuTexture.IsActive = true;

		return .Ok(.() { Index = index, Generation = generation });
	}

	/// Gets a GPU texture by handle.
	public GPUTexture GetTexture(GPUTextureHandle handle)
	{
		if (!handle.IsValid || handle.Index >= mTextures.Count)
			return null;

		let tex = mTextures[(int)handle.Index];
		if (!tex.IsActive || tex.Generation != handle.Generation)
			return null;

		return tex;
	}

	/// Gets the texture view for a handle.
	public ITextureView GetTextureView(GPUTextureHandle handle)
	{
		if (let tex = GetTexture(handle))
			return tex.DefaultView;
		return null;
	}

	/// Adds a reference to a texture.
	public void AddTextureRef(GPUTextureHandle handle)
	{
		if (let tex = GetTexture(handle))
			tex.RefCount++;
	}

	/// Releases a reference to a texture.
	public void ReleaseTexture(GPUTextureHandle handle, uint64 frameNumber)
	{
		if (let tex = GetTexture(handle))
		{
			tex.RefCount--;
			if (tex.RefCount <= 0)
			{
				mPendingDeletions.Add(.()
				{
					ResourceType = .Texture,
					Index = handle.Index,
					FrameNumber = frameNumber
				});
			}
		}
	}

	// ========================================================================
	// Maintenance
	// ========================================================================

	/// Processes pending deletions that have aged out.
	public void ProcessDeletions(uint64 currentFrame)
	{
		for (int i = mPendingDeletions.Count - 1; i >= 0; i--)
		{
			let pending = mPendingDeletions[i];
			if (currentFrame >= pending.FrameNumber + DeletionDelay)
			{
				switch (pending.ResourceType)
				{
				case .Mesh:
					let mesh = mMeshes[(int)pending.Index];
					mesh.Release();
					mFreeMeshSlots.Add((int32)pending.Index);

				case .Texture:
					let tex = mTextures[(int)pending.Index];
					tex.Release();
					mFreeTextureSlots.Add((int32)pending.Index);

				case .BoneBuffer:
					let buffer = mBoneBuffers[(int)pending.Index];
					buffer.Release();
					mFreeBoneBufferSlots.Add((int32)pending.Index);
				}

				mPendingDeletions.RemoveAtFast(i);
			}
		}
	}

	public void Dispose()
	{
		// Release all resources immediately
		for (let mesh in mMeshes)
			mesh.Release();

		for (let tex in mTextures)
			tex.Release();

		for (let buffer in mBoneBuffers)
			buffer.Release();

		mPendingDeletions.Clear();
	}
}
