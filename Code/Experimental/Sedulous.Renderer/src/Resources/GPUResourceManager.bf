namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Core.Mathematics;
using Sedulous.Geometry;

/// Pending deletion entry.
struct PendingDeletion
{
	public enum Type { Mesh, Texture, BoneBuffer }
	public Type ResourceType;
	public uint32 Index;
	public uint64 FrameNumber;
}

/// Manages GPU resources (meshes, textures, bone buffers) with reference counting
/// and deferred deletion. Upload methods accept an optional ITransferBatch for
/// async init-time uploads or immediate runtime uploads.
public class GPUResourceManager
{
	private IDevice mDevice;
	private IQueue mGraphicsQueue;

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

	// Frames to wait before actually deleting
	private const uint64 DeletionDelay = RenderConfig.FrameBufferCount + 1;

	// Built-in fallback texture handles
	private GPUTextureHandle mWhiteTexture;
	private GPUTextureHandle mBlackTexture;
	private GPUTextureHandle mFlatNormalTexture;

	/// Gets the device.
	public IDevice Device => mDevice;

	/// 1x1 white fallback texture.
	public GPUTextureHandle WhiteTexture => mWhiteTexture;
	/// 1x1 black fallback texture.
	public GPUTextureHandle BlackTexture => mBlackTexture;
	/// 1x1 flat normal (0.5, 0.5, 1.0) fallback texture.
	public GPUTextureHandle FlatNormalTexture => mFlatNormalTexture;

	/// Initializes the manager and creates fallback textures.
	public Result<void> Initialize(IDevice device, IQueue graphicsQueue, ITransferBatch transferBatch = null)
	{
		mDevice = device;
		mGraphicsQueue = graphicsQueue;

		// Create fallback textures
		uint8[4] white = .(255, 255, 255, 255);
		if (UploadTexture2D(&white, .RGBA8Unorm, 1, 1, transferBatch) case .Ok(let hWhite))
			mWhiteTexture = hWhite;
		else
			return .Err;

		uint8[4] black = .(0, 0, 0, 255);
		if (UploadTexture2D(&black, .RGBA8Unorm, 1, 1, transferBatch) case .Ok(let hBlack))
			mBlackTexture = hBlack;
		else
			return .Err;

		uint8[4] flatNormal = .(128, 128, 255, 255);
		if (UploadTexture2D(&flatNormal, .RGBA8Unorm, 1, 1, transferBatch) case .Ok(let hNormal))
			mFlatNormalTexture = hNormal;
		else
			return .Err;

		return .Ok;
	}

	// ========================================================================
	// Mesh API
	// ========================================================================

	/// Uploads a mesh to the GPU.
	/// If transferBatch is provided, the upload is queued (async). Otherwise it's immediate.
	public Result<GPUMeshHandle> UploadMesh(
		Span<uint8> vertexData, uint32 vertexCount, uint32 vertexStride,
		Span<uint8> indexData, uint32 indexCount, IndexFormat indexFormat,
		Span<GPUSubMesh> subMeshes, Span<GPUMeshLOD> lods,
		BoundingBox bounds, bool isSkinned = false,
		ITransferBatch transferBatch = null)
	{
		if (vertexData.IsEmpty || vertexCount == 0)
			return .Err;

		// Allocate slot
		GPUMesh gpuMesh;
		uint32 index;
		uint32 generation;
		AllocateMeshSlot(out gpuMesh, out index, out generation);

		// Create vertex buffer
		var vbUsage = BufferUsage.Vertex | .CopyDst;
		if (isSkinned)
			vbUsage |= .Storage; // For GPU skinning compute

		let vbResult = mDevice.CreateBuffer(BufferDesc()
		{
			Size = (uint64)vertexData.Length,
			Usage = vbUsage,
			Label = "MeshVB"
		});
		if (vbResult case .Err)
			return .Err;
		gpuMesh.VertexBuffer = vbResult.Value;

		// Upload vertex data
		if (UploadBufferData(gpuMesh.VertexBuffer, vertexData, transferBatch) case .Err)
		{
			mDevice.DestroyBuffer(ref gpuMesh.VertexBuffer);
			return .Err;
		}

		// Create index buffer (if provided)
		if (!indexData.IsEmpty && indexCount > 0)
		{
			let ibResult = mDevice.CreateBuffer(BufferDesc()
			{
				Size = (uint64)indexData.Length,
				Usage = .Index | .CopyDst,
				Label = "MeshIB"
			});
			if (ibResult case .Err)
			{
				mDevice.DestroyBuffer(ref gpuMesh.VertexBuffer);
				return .Err;
			}
			gpuMesh.IndexBuffer = ibResult.Value;

			if (UploadBufferData(gpuMesh.IndexBuffer, indexData, transferBatch) case .Err)
			{
				mDevice.DestroyBuffer(ref gpuMesh.VertexBuffer);
				mDevice.DestroyBuffer(ref gpuMesh.IndexBuffer);
				return .Err;
			}
		}

		// Set mesh properties
		gpuMesh.VertexCount = vertexCount;
		gpuMesh.IndexCount = indexCount;
		gpuMesh.VertexStride = vertexStride;
		gpuMesh.IndexFormat = indexFormat;
		gpuMesh.Bounds = bounds;
		gpuMesh.IsSkinned = isSkinned;
		gpuMesh.RefCount = 1;
		gpuMesh.Generation = generation;
		gpuMesh.IsActive = true;

		// Copy submeshes
		if (!subMeshes.IsEmpty)
		{
			gpuMesh.SubMeshes = new GPUSubMesh[subMeshes.Length];
			for (int i = 0; i < subMeshes.Length; i++)
				gpuMesh.SubMeshes[i] = subMeshes[i];
		}
		else
		{
			// Single submesh for entire mesh
			gpuMesh.SubMeshes = new GPUSubMesh[1];
			gpuMesh.SubMeshes[0] = .()
			{
				IndexStart = 0,
				IndexCount = indexCount > 0 ? indexCount : vertexCount,
				BaseVertex = 0,
				MaterialSlot = 0
			};
		}

		// Copy LODs
		if (!lods.IsEmpty)
		{
			gpuMesh.LODLevels = new GPUMeshLOD[lods.Length];
			for (int i = 0; i < lods.Length; i++)
				gpuMesh.LODLevels[i] = lods[i];
			gpuMesh.LODCount = (uint32)lods.Length;
		}

		return .Ok(.() { Index = index, Generation = generation });
	}

	/// Uploads a StaticMesh (from Sedulous.Geometry) to the GPU.
	public Result<GPUMeshHandle> UploadMesh(StaticMesh mesh, ITransferBatch transferBatch = null)
	{
		let vertexData = mesh.GetVertexData();
		let indexData = mesh.GetIndexData();

		if (vertexData == null)
			return .Err;

		let vertexBytes = (int)(mesh.VertexCount * mesh.VertexSize);
		let indexBytes = mesh.Indices != null ? (int)mesh.Indices.GetDataSize() : 0;
		let indexCount = mesh.Indices != null ? (uint32)mesh.IndexCount : (uint32)0;
		let indexFormat = (mesh.Indices != null && mesh.Indices.Format == .UInt16)
			? IndexFormat.UInt16 : IndexFormat.UInt32;

		// Convert Geometry SubMeshes to GPU SubMeshes
		let subMeshCount = mesh.SubMeshes.Count;
		let gpuSubMeshes = scope GPUSubMesh[subMeshCount];
		for (int i = 0; i < subMeshCount; i++)
		{
			let sm = mesh.SubMeshes[i];
			gpuSubMeshes[i] = .()
			{
				IndexStart = (uint32)sm.startIndex,
				IndexCount = (uint32)sm.indexCount,
				BaseVertex = 0,
				MaterialSlot = (uint32)sm.materialIndex
			};
		}

		return UploadMesh(
			Span<uint8>(vertexData, vertexBytes),
			(uint32)mesh.VertexCount,
			(uint32)mesh.VertexSize,
			indexData != null ? Span<uint8>(indexData, indexBytes) : Span<uint8>(),
			indexCount,
			indexFormat,
			gpuSubMeshes,
			Span<GPUMeshLOD>(),
			mesh.GetBounds(),
			false,
			transferBatch);
	}

	/// Uploads a SkinnedMesh (from Sedulous.Geometry) to the GPU.
	/// The vertex buffer gets Storage usage for compute skinning reads.
	public Result<GPUMeshHandle> UploadMesh(SkinnedMesh mesh, ITransferBatch transferBatch = null)
	{
		let vertexData = mesh.GetVertexData();
		let indexData = mesh.GetIndexData();

		if (vertexData == null)
			return .Err;

		let vertexBytes = (int)(mesh.VertexCount * mesh.VertexSize);
		let indexBytes = mesh.Indices != null ? (int)mesh.Indices.GetDataSize() : 0;
		let indexCount = mesh.Indices != null ? (uint32)mesh.IndexCount : (uint32)0;
		let indexFormat = (mesh.Indices != null && mesh.Indices.Format == .UInt16)
			? IndexFormat.UInt16 : IndexFormat.UInt32;

		let subMeshCount = mesh.SubMeshes.Count;
		let gpuSubMeshes = scope GPUSubMesh[subMeshCount];
		for (int i = 0; i < subMeshCount; i++)
		{
			let sm = mesh.SubMeshes[i];
			gpuSubMeshes[i] = .()
			{
				IndexStart = (uint32)sm.startIndex,
				IndexCount = (uint32)sm.indexCount,
				BaseVertex = 0,
				MaterialSlot = (uint32)sm.materialIndex
			};
		}

		return UploadMesh(
			Span<uint8>(vertexData, vertexBytes),
			(uint32)mesh.VertexCount,
			(uint32)mesh.VertexSize,
			indexData != null ? Span<uint8>(indexData, indexBytes) : Span<uint8>(),
			indexCount,
			indexFormat,
			gpuSubMeshes,
			Span<GPUMeshLOD>(),
			mesh.Bounds,
			true,
			transferBatch);
	}

	/// Gets a GPU mesh by handle. Returns null if invalid.
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

	/// Releases a reference to a mesh. Schedules deferred deletion when RefCount hits 0.
	public void ReleaseMesh(GPUMeshHandle handle, uint64 frameNumber)
	{
		if (let mesh = GetMesh(handle))
		{
			mesh.RefCount--;
			if (mesh.RefCount <= 0)
			{
				mPendingDeletions.Add(.()
				{
					ResourceType = .Mesh,
					Index = handle.Index,
					FrameNumber = frameNumber
				});
			}
		}
	}

	// ========================================================================
	// Texture API
	// ========================================================================

	/// Uploads a 2D texture to the GPU.
	public Result<GPUTextureHandle> UploadTexture2D(
		void* pixelData, TextureFormat format, uint32 width, uint32 height,
		ITransferBatch transferBatch = null,
		uint32 mipLevels = 1, uint32 bytesPerRow = 0)
	{
		if (pixelData == null || width == 0 || height == 0)
			return .Err;

		return UploadTextureInternal(pixelData, format, width, height, 1, .Texture2D,
			mipLevels, bytesPerRow, transferBatch);
	}

	/// Uploads a cube map texture to the GPU (6 array layers).
	public Result<GPUTextureHandle> UploadTextureCube(
		void* pixelData, TextureFormat format, uint32 width, uint32 height,
		ITransferBatch transferBatch = null,
		uint32 mipLevels = 1, uint32 bytesPerRow = 0)
	{
		if (pixelData == null || width == 0 || height == 0)
			return .Err;

		return UploadTextureInternal(pixelData, format, width, height, 6, .Texture2D,
			mipLevels, bytesPerRow, transferBatch);
	}

	/// Creates an empty render target texture (no upload needed).
	public Result<GPUTextureHandle> CreateRenderTarget(
		uint32 width, uint32 height, TextureFormat format,
		TextureUsage usage = .RenderTarget | .Sampled)
	{
		GPUTexture gpuTex;
		uint32 index, generation;
		AllocateTextureSlot(out gpuTex, out index, out generation);

		let texResult = mDevice.CreateTexture(TextureDesc.Tex2D(format, width, height, usage));
		if (texResult case .Err)
			return .Err;
		gpuTex.Texture = texResult.Value;

		let viewResult = mDevice.CreateTextureView(gpuTex.Texture, TextureViewDesc()
		{
			Format = format,
			Dimension = .Texture2D,
			MipLevelCount = 1,
			ArrayLayerCount = 1
		});
		if (viewResult case .Err)
		{
			mDevice.DestroyTexture(ref gpuTex.Texture);
			return .Err;
		}
		gpuTex.DefaultView = viewResult.Value;

		gpuTex.Width = width;
		gpuTex.Height = height;
		gpuTex.ArrayLayerCount = 1;
		gpuTex.MipLevels = 1;
		gpuTex.Format = format;
		gpuTex.RefCount = 1;
		gpuTex.Generation = generation;
		gpuTex.IsActive = true;

		return .Ok(.() { Index = index, Generation = generation });
	}

	/// Gets a GPU texture by handle. Returns null if invalid.
	public GPUTexture GetTexture(GPUTextureHandle handle)
	{
		if (!handle.IsValid || handle.Index >= mTextures.Count)
			return null;

		let tex = mTextures[(int)handle.Index];
		if (!tex.IsActive || tex.Generation != handle.Generation)
			return null;

		return tex;
	}

	/// Gets the default texture view for a handle.
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
	// Bone Buffer API
	// ========================================================================

	/// Creates a bone buffer for skinned mesh animation.
	/// Stores current + previous frame bone matrices, double-buffered per frame-in-flight.
	/// Uses staging + GPU copy pattern (DX12 UPLOAD heaps can't have UAV/Storage).
	public Result<GPUBoneBufferHandle> CreateBoneBuffer(uint16 boneCount)
	{
		GPUBoneBuffer boneBuffer;
		uint32 index, generation;
		AllocateBoneBufferSlot(out boneBuffer, out index, out generation);

		// Size: current + previous frame matrices for each bone
		let bufferSize = (uint64)(sizeof(Matrix) * boneCount * 2);

		for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			// GPU buffer: shader reads via StructuredBuffer (Storage + CopyDst)
			let gpuResult = mDevice.CreateBuffer(BufferDesc()
			{
				Size = bufferSize,
				Usage = .Storage | .CopyDst,
				Memory = .GpuOnly,
				Label = "BoneBuffer"
			});
			if (gpuResult case .Err)
				return .Err;
			boneBuffer.Buffers[i] = gpuResult.Value;

			// Staging buffer: CPU writes here (CpuToGpu + CopySrc)
			let stagingResult = mDevice.CreateBuffer(BufferDesc()
			{
				Size = bufferSize,
				Usage = .CopySrc,
				Memory = .CpuToGpu,
				Label = "BoneBuffer_Staging"
			});
			if (stagingResult case .Err)
				return .Err;
			boneBuffer.StagingBuffers[i] = stagingResult.Value;
			boneBuffer.MappedPtrs[i] = boneBuffer.StagingBuffers[i].Map();
		}

		boneBuffer.BoneCount = boneCount;
		boneBuffer.Size = bufferSize;
		boneBuffer.RefCount = 1;
		boneBuffer.Generation = generation;
		boneBuffer.IsActive = true;

		return .Ok(.() { Index = index, Generation = generation });
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

	/// Updates bone transforms in a bone buffer via staging memory.
	/// frameIndex selects which double-buffered slot to write to.
	/// The staging→GPU copy is performed by SkinningSystem.RecordSkinning.
	public void UpdateBoneBuffer(GPUBoneBufferHandle handle, int frameIndex, Matrix* currentBones, Matrix* prevBones, uint16 boneCount)
	{
		if (let buffer = GetBoneBuffer(handle))
		{
			var actualBoneCount = Math.Min(boneCount, buffer.BoneCount);
			let matrixSize = (int)(sizeof(Matrix) * actualBoneCount);

			let mapped = buffer.MappedPtrs[frameIndex];
			if (mapped != null)
			{
				// Current frame matrices at offset 0
				Internal.MemCpy(mapped, currentBones, matrixSize);
				// Previous frame matrices at offset (boneCount * sizeof(Matrix))
				let prevOffset = (int)(sizeof(Matrix) * buffer.BoneCount);
				Internal.MemCpy((uint8*)mapped + prevOffset, prevBones, matrixSize);
				buffer.NeedsUpload[frameIndex] = true;
			}
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
	// Maintenance
	// ========================================================================

	/// Processes pending deletions that have aged out.
	/// Call once per frame with the current frame number.
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
					mesh.Release(mDevice);
					mFreeMeshSlots.Add((int32)pending.Index);

				case .Texture:
					let tex = mTextures[(int)pending.Index];
					tex.Release(mDevice);
					mFreeTextureSlots.Add((int32)pending.Index);

				case .BoneBuffer:
					let buffer = mBoneBuffers[(int)pending.Index];
					buffer.Release(mDevice);
					mFreeBoneBufferSlots.Add((int32)pending.Index);
				}

				mPendingDeletions.RemoveAtFast(i);
			}
		}
	}

	/// Releases all resources immediately. Call during shutdown after WaitIdle.
	public void Shutdown()
	{
		for (let mesh in mMeshes)
		{
			if (mesh.IsActive)
				mesh.Release(mDevice);
		}

		for (let tex in mTextures)
		{
			if (tex.IsActive)
				tex.Release(mDevice);
		}

		for (let buffer in mBoneBuffers)
		{
			if (buffer.IsActive)
				buffer.Release(mDevice);
		}

		mPendingDeletions.Clear();
	}

	// ========================================================================
	// Internal helpers
	// ========================================================================

	private void AllocateMeshSlot(out GPUMesh gpuMesh, out uint32 index, out uint32 generation)
	{
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
	}

	private void AllocateTextureSlot(out GPUTexture gpuTex, out uint32 index, out uint32 generation)
	{
		if (mFreeTextureSlots.Count > 0)
		{
			index = (uint32)mFreeTextureSlots.PopBack();
			gpuTex = mTextures[(int)index];
			generation = gpuTex.Generation + 1;
		}
		else
		{
			index = (uint32)mTextures.Count;
			gpuTex = new GPUTexture();
			mTextures.Add(gpuTex);
			generation = 1;
		}
	}

	private void AllocateBoneBufferSlot(out GPUBoneBuffer boneBuffer, out uint32 index, out uint32 generation)
	{
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
	}

	/// Uploads data to a buffer. Uses transferBatch if provided, otherwise creates a temporary one.
	private Result<void> UploadBufferData(IBuffer dst, Span<uint8> data, ITransferBatch transferBatch)
	{
		if (transferBatch != null)
		{
			transferBatch.WriteBuffer(dst, 0, data);
			return .Ok;
		}

		// Immediate upload: create temporary batch, submit, wait
		let batchResult = mGraphicsQueue.CreateTransferBatch();
		if (batchResult case .Err)
			return .Err;

		var batch = batchResult.Value;
		batch.WriteBuffer(dst, 0, data);
		let submitResult = batch.Submit();
		mGraphicsQueue.DestroyTransferBatch(ref batch);
		return submitResult;
	}

	/// Internal texture upload shared by 2D and cube uploads.
	private Result<GPUTextureHandle> UploadTextureInternal(
		void* pixelData, TextureFormat format, uint32 width, uint32 height,
		uint32 arrayLayerCount, TextureDimension dimension,
		uint32 mipLevels, uint32 bytesPerRow, ITransferBatch transferBatch)
	{
		GPUTexture gpuTex;
		uint32 index, generation;
		AllocateTextureSlot(out gpuTex, out index, out generation);

		// Create texture
		let texResult = mDevice.CreateTexture(TextureDesc()
		{
			Dimension = dimension,
			Format = format,
			Width = width,
			Height = height,
			ArrayLayerCount = arrayLayerCount,
			MipLevelCount = mipLevels,
			SampleCount = 1,
			Usage = .Sampled | .CopyDst
		});
		if (texResult case .Err)
			return .Err;
		gpuTex.Texture = texResult.Value;

		// Compute data layout
		let bpp = GetBytesPerPixel(format);
		let actualBytesPerRow = bytesPerRow > 0 ? bytesPerRow : width * bpp;
		let dataSize = (int)(actualBytesPerRow * height * arrayLayerCount);

		var dataLayout = TextureDataLayout()
		{
			Offset = 0,
			BytesPerRow = actualBytesPerRow,
			RowsPerImage = height
		};
		var extent = Extent3D(width, height, arrayLayerCount);

		let texData = Span<uint8>((uint8*)pixelData, dataSize);

		// Upload
		if (transferBatch != null)
		{
			transferBatch.WriteTexture(gpuTex.Texture, texData, dataLayout, extent);
		}
		else
		{
			let batchResult = mGraphicsQueue.CreateTransferBatch();
			if (batchResult case .Err)
			{
				mDevice.DestroyTexture(ref gpuTex.Texture);
				return .Err;
			}
			var batch = batchResult.Value;
			batch.WriteTexture(gpuTex.Texture, texData, dataLayout, extent);
			batch.Submit();
			mGraphicsQueue.DestroyTransferBatch(ref batch);
		}

		// Create default view
		let viewDim = arrayLayerCount == 6 ? TextureViewDimension.TextureCube : TextureViewDimension.Texture2D;
		let viewResult = mDevice.CreateTextureView(gpuTex.Texture, TextureViewDesc()
		{
			Format = format,
			Dimension = viewDim,
			MipLevelCount = mipLevels,
			ArrayLayerCount = arrayLayerCount
		});
		if (viewResult case .Err)
		{
			mDevice.DestroyTexture(ref gpuTex.Texture);
			return .Err;
		}
		gpuTex.DefaultView = viewResult.Value;

		gpuTex.Width = width;
		gpuTex.Height = height;
		gpuTex.ArrayLayerCount = arrayLayerCount;
		gpuTex.MipLevels = mipLevels;
		gpuTex.Format = format;
		gpuTex.RefCount = 1;
		gpuTex.Generation = generation;
		gpuTex.IsActive = true;

		return .Ok(.() { Index = index, Generation = generation });
	}

	/// Returns bytes per pixel for common formats.
	private static uint32 GetBytesPerPixel(TextureFormat format)
	{
		switch (format)
		{
		case .R8Unorm: return 1;
		case .RG8Unorm: return 2;
		case .RGBA8Unorm, .RGBA8UnormSrgb, .BGRA8Unorm, .BGRA8UnormSrgb: return 4;
		case .RGBA16Float: return 8;
		case .RGBA32Float: return 16;
		case .RG16Float: return 4;
		case .R16Float: return 2;
		case .R32Float: return 4;
		case .RG32Float: return 8;
		case .Depth32Float: return 4;
		case .Depth24Plus: return 4;
		default: return 4;
		}
	}
}
