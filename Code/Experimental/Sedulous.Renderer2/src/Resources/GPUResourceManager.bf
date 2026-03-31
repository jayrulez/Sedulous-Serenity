namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Geometry;
using Sedulous.Core.Mathematics;
using Sedulous.Profiler;
using Sedulous.Textures;

/// Pending deletion entry for deferred GPU resource cleanup.
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
	public IBuffer Buffer;
	public uint16 BoneCount;
	public uint64 Size;
	public int32 RefCount;
	public uint32 Generation;
	public bool IsActive;

	public void Release(IDevice device)
	{
		if (device != null)
			device.DestroyBuffer(ref Buffer);
		IsActive = false;
	}
}

/// Manages GPU resources (meshes, textures, bone buffers) with reference counting and deferred deletion.
/// Owned by RenderSystem — all features share this single instance.
/// Init-time uploads go through the shared TransferBatch for batching.
public class GPUResourceManager : IDisposable
{
	private IDevice mDevice;
	private IQueue mQueue;

	/// Optional transfer batch for batching GPU uploads during initialization.
	public ITransferBatch TransferBatch;

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

	public IDevice Device => mDevice;

	public Result<void> Initialize(IDevice device, IQueue graphicsQueue)
	{
		using (SProfiler.Begin("Renderer.GPUResourceManager"))
		{
			mDevice = device;
			mQueue = graphicsQueue;
		}
		return .Ok;
	}

	// ========================================================================
	// Mesh API
	// ========================================================================

	public Result<GPUMeshHandle> UploadMesh(StaticMesh mesh)
	{
		if (mesh == null || mesh.Vertices == null || mesh.VertexCount == 0)
			return .Err;

		using (SProfiler.Begin("GPUResources.UploadStaticMesh"))
		{
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
			let vertexDataSize = (uint64)(mesh.VertexCount * mesh.VertexSize);
			if (mDevice.CreateBuffer(BufferDesc()
			{
				Label = "Static Mesh Vertices",
				Size = vertexDataSize,
				Usage = .Vertex | .CopyDst
			}) case .Ok(let vb))
			{
				gpuMesh.VertexBuffer = vb;
				let vbData = Span<uint8>(mesh.GetVertexData(), (int)vertexDataSize);
				if (TransferBatch != null)
					TransferBatch.WriteBuffer(vb, 0, vbData);
				else
					TransferHelper.WriteStagedBufferSync(mQueue, mDevice, vb, 0, vbData);
			}
			else
				return .Err;

			// Create index buffer
			let indices = mesh.Indices;
			let hasIndices = indices != null && indices.IndexCount > 0;

			if (hasIndices)
			{
				let indexSize = indices.Format == .UInt16 ? 2 : 4;
				let indexDataSize = (uint64)(indices.IndexCount * indexSize);
				if (mDevice.CreateBuffer(BufferDesc()
				{
					Label = "Static Mesh Indices",
					Size = indexDataSize,
					Usage = .Index | .CopyDst
				}) case .Ok(let ib))
				{
					gpuMesh.IndexBuffer = ib;
					let ibData = Span<uint8>(indices.GetRawData(), (int)indexDataSize);
					if (TransferBatch != null)
						TransferBatch.WriteBuffer(ib, 0, ibData);
					else
						TransferHelper.WriteStagedBufferSync(mQueue, mDevice, ib, 0, ibData);
				}
				else
				{
					mDevice.DestroyBuffer(ref gpuMesh.VertexBuffer);
					return .Err;
				}
			}

			// Set mesh properties
			gpuMesh.VertexCount = (uint32)mesh.VertexCount;
			gpuMesh.IndexCount = hasIndices ? (uint32)indices.IndexCount : 0;
			gpuMesh.VertexStride = (uint32)mesh.VertexSize;
			gpuMesh.IndexFormat = hasIndices && indices.Format == .UInt16 ? .UInt16 : .UInt32;
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
	}

	public Result<GPUMeshHandle> UploadMesh(SkinnedMesh mesh)
	{
		if (mesh == null || mesh.Vertices == null || mesh.VertexCount == 0)
			return .Err;

		using (SProfiler.Begin("GPUResources.UploadSkinnedMesh"))
		{
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

			// Vertex buffer with Storage for GPU skinning compute shader
			let vertexDataSize = (uint64)(mesh.VertexCount * mesh.VertexSize);
			if (mDevice.CreateBuffer(BufferDesc()
			{
				Label = "Skinned Mesh Vertices",
				Size = vertexDataSize,
				Usage = .Vertex | .Storage | .CopyDst
			}) case .Ok(let vb))
			{
				gpuMesh.VertexBuffer = vb;
				let vbData = Span<uint8>(mesh.GetVertexData(), (int)vertexDataSize);
				if (TransferBatch != null)
					TransferBatch.WriteBuffer(vb, 0, vbData);
				else
					TransferHelper.WriteStagedBufferSync(mQueue, mDevice, vb, 0, vbData);
			}
			else
				return .Err;

			let indices = mesh.Indices;
			let hasIndices = indices != null && indices.IndexCount > 0;

			if (hasIndices)
			{
				let indexSize = indices.Format == .UInt16 ? 2 : 4;
				let indexDataSize = (uint64)(indices.IndexCount * indexSize);
				if (mDevice.CreateBuffer(BufferDesc()
				{
					Label = "Skinned Mesh Indices",
					Size = indexDataSize,
					Usage = .Index | .CopyDst
				}) case .Ok(let ib))
				{
					gpuMesh.IndexBuffer = ib;
					let ibData = Span<uint8>(mesh.GetIndexData(), (int)indexDataSize);
					if (TransferBatch != null)
						TransferBatch.WriteBuffer(ib, 0, ibData);
					else
						TransferHelper.WriteStagedBufferSync(mQueue, mDevice, ib, 0, ibData);
				}
				else
				{
					mDevice.DestroyBuffer(ref gpuMesh.VertexBuffer);
					return .Err;
				}
			}

			gpuMesh.VertexCount = (uint32)mesh.VertexCount;
			gpuMesh.IndexCount = hasIndices ? (uint32)indices.IndexCount : 0;
			gpuMesh.VertexStride = (uint32)mesh.VertexSize;
			gpuMesh.IndexFormat = hasIndices && indices.Format == .UInt16 ? .UInt16 : .UInt32;
			gpuMesh.Bounds = mesh.Bounds;
			gpuMesh.RefCount = 1;
			gpuMesh.Generation = generation;
			gpuMesh.IsActive = true;
			gpuMesh.IsSkinned = true;

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
	}

	public GPUMesh GetMesh(GPUMeshHandle handle)
	{
		if (!handle.IsValid || handle.Index >= mMeshes.Count)
			return null;
		let mesh = mMeshes[(int)handle.Index];
		if (!mesh.IsActive || mesh.Generation != handle.Generation)
			return null;
		return mesh;
	}

	public void AddMeshRef(GPUMeshHandle handle)
	{
		if (let mesh = GetMesh(handle))
			mesh.RefCount++;
	}

	public void ReleaseMesh(GPUMeshHandle handle, uint64 frameNumber)
	{
		if (let mesh = GetMesh(handle))
		{
			mesh.RefCount--;
			if (mesh.RefCount <= 0)
				mPendingDeletions.Add(.() { ResourceType = .Mesh, Index = handle.Index, FrameNumber = frameNumber });
		}
	}

	// ========================================================================
	// Bone Buffer API
	// ========================================================================

	public Result<GPUBoneBufferHandle> CreateBoneBuffer(uint16 boneCount)
	{
		if (boneCount == 0 || boneCount > RenderConfig.MaxBonesPerMesh)
			return .Err;

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

		let bufferSize = BoneTransforms.GetSizeForBoneCount((int32)boneCount);

		if (mDevice.CreateBuffer(BufferDesc()
		{
			Label = "Bone Transforms",
			Size = bufferSize,
			Usage = .Storage,
			Memory = .CpuToGpu
		}) case .Ok(let buffer))
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

	public GPUBoneBuffer GetBoneBuffer(GPUBoneBufferHandle handle)
	{
		if (!handle.IsValid || handle.Index >= mBoneBuffers.Count)
			return null;
		let buffer = mBoneBuffers[(int)handle.Index];
		if (!buffer.IsActive || buffer.Generation != handle.Generation)
			return null;
		return buffer;
	}

	public void UpdateBoneBuffer(GPUBoneBufferHandle handle, Matrix* currentBones, Matrix* prevBones, uint16 boneCount)
	{
		if (let buffer = GetBoneBuffer(handle))
		{
			var actualBoneCount = boneCount;
			if (actualBoneCount > buffer.BoneCount)
				actualBoneCount = buffer.BoneCount;

			let matrixSize = (uint64)(sizeof(Matrix) * actualBoneCount);
			TransferHelper.WriteMappedBuffer(buffer.Buffer, 0, Span<uint8>((uint8*)currentBones, (int)matrixSize));

			let prevOffset = (uint64)(sizeof(Matrix) * buffer.BoneCount);
			TransferHelper.WriteMappedBuffer(buffer.Buffer, prevOffset, Span<uint8>((uint8*)prevBones, (int)matrixSize));
		}
	}

	public void AddBoneBufferRef(GPUBoneBufferHandle handle)
	{
		if (let buffer = GetBoneBuffer(handle))
			buffer.RefCount++;
	}

	public void ReleaseBoneBuffer(GPUBoneBufferHandle handle, uint64 frameNumber)
	{
		if (let buffer = GetBoneBuffer(handle))
		{
			buffer.RefCount--;
			if (buffer.RefCount <= 0)
				mPendingDeletions.Add(.() { ResourceType = .BoneBuffer, Index = handle.Index, FrameNumber = frameNumber });
		}
	}

	// ========================================================================
	// Texture API
	// ========================================================================

	public Result<GPUTextureHandle> UploadTexture(TextureData data)
	{
		if (data.Pixels == null || data.Size == 0)
			return .Err;

		using (SProfiler.Begin("GPUResources.UploadTexture"))
		{
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

			if (mDevice.CreateTexture(TextureDesc()
			{
				Label = "Uploaded Texture",
				Width = data.Width,
				Height = data.Height,
				Depth = 1,
				ArrayLayerCount = data.DepthOrArrayLayers,
				MipLevelCount = data.MipLevels,
				Format = data.Format,
				Usage = .Sampled | .CopyDst,
				Dimension = data.Dimension,
				SampleCount = 1
			}) case .Ok(let tex))
			{
				gpuTexture.Texture = tex;

				let bpp = TextureData.GetBytesPerPixel(data.Format);
				var bytesPerRow = data.BytesPerRow;
				if (bytesPerRow == 0)
					bytesPerRow = data.Width * bpp;

				var rowsPerImage = data.RowsPerImage;
				if (rowsPerImage == 0)
					rowsPerImage = data.Height;

				let texData = Span<uint8>(data.Pixels, (int)data.Size);
				if (TransferBatch != null)
					TransferBatch.WriteTexture(tex, texData, TextureDataLayout() { BytesPerRow = bytesPerRow, RowsPerImage = rowsPerImage },
						Extent3D(data.Width, data.Height, data.DepthOrArrayLayers));
				else
					TransferHelper.WriteTextureSync(mQueue, mDevice, tex, texData,
						TextureDataLayout() { BytesPerRow = bytesPerRow, RowsPerImage = rowsPerImage },
						Extent3D(data.Width, data.Height, data.DepthOrArrayLayers));

				if (mDevice.CreateTextureView(tex, TextureViewDesc()
				{
					Format = data.Format,
					Dimension = data.DepthOrArrayLayers == 6 ? .TextureCube : .Texture2D,
					MipLevelCount = data.MipLevels,
					ArrayLayerCount = data.DepthOrArrayLayers
				}) case .Ok(let view))
					gpuTexture.DefaultView = view;
				else
				{
					var texRef = tex;
					mDevice.DestroyTexture(ref texRef);
					return .Err;
				}
			}
			else
				return .Err;

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
	}

	public Result<GPUTextureHandle> CreateRenderTarget(uint32 width, uint32 height, TextureFormat format, TextureUsage usage = .RenderTarget | .Sampled)
	{
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

		if (mDevice.CreateTexture(TextureDesc()
		{
			Label = "Render Target",
			Width = width, Height = height,
			Format = format, Usage = usage
		}) case .Ok(let tex))
		{
			gpuTexture.Texture = tex;
			if (mDevice.CreateTextureView(tex, TextureViewDesc() { Format = format }) case .Ok(let view))
				gpuTexture.DefaultView = view;
			else
			{
				var texRef = tex;
				mDevice.DestroyTexture(ref texRef);
				return .Err;
			}
		}
		else
			return .Err;

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

	public GPUTexture GetTexture(GPUTextureHandle handle)
	{
		if (!handle.IsValid || handle.Index >= mTextures.Count)
			return null;
		let tex = mTextures[(int)handle.Index];
		if (!tex.IsActive || tex.Generation != handle.Generation)
			return null;
		return tex;
	}

	public ITextureView GetTextureView(GPUTextureHandle handle)
	{
		if (let tex = GetTexture(handle))
			return tex.DefaultView;
		return null;
	}

	public void AddTextureRef(GPUTextureHandle handle)
	{
		if (let tex = GetTexture(handle))
			tex.RefCount++;
	}

	public void ReleaseTexture(GPUTextureHandle handle, uint64 frameNumber)
	{
		if (let tex = GetTexture(handle))
		{
			tex.RefCount--;
			if (tex.RefCount <= 0)
				mPendingDeletions.Add(.() { ResourceType = .Texture, Index = handle.Index, FrameNumber = frameNumber });
		}
	}

	// ========================================================================
	// Maintenance
	// ========================================================================

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
					mMeshes[(int)pending.Index].Release(mDevice);
					mFreeMeshSlots.Add((int32)pending.Index);
				case .Texture:
					mTextures[(int)pending.Index].Release(mDevice);
					mFreeTextureSlots.Add((int32)pending.Index);
				case .BoneBuffer:
					mBoneBuffers[(int)pending.Index].Release(mDevice);
					mFreeBoneBufferSlots.Add((int32)pending.Index);
				}
				mPendingDeletions.RemoveAtFast(i);
			}
		}
	}

	public void Dispose()
	{
		for (let mesh in mMeshes)
			mesh.Release(mDevice);
		for (let tex in mTextures)
			tex.Release(mDevice);
		for (let buffer in mBoneBuffers)
			buffer.Release(mDevice);
		mPendingDeletions.Clear();
	}
}
