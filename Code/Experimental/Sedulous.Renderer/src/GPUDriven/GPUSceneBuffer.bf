namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Core.Mathematics;

using internal Sedulous.Renderer;

/// Tracks per-draw-group command range in the indirect buffer.
struct DrawGroupRange
{
	public MaterialInstanceHandle MaterialHandle;
	public GPUMeshHandle MeshHandle;
	public uint32 SubMeshIndex;
	public uint32 CommandOffset;  // first command index in indirect buffer
	public uint32 CommandCount;   // number of commands in this group
}

/// Per-object GPU data uploaded to the scene buffer each frame.
/// Must match the layout read by gpu_cull.hlsl and all vertex shaders.
/// Uses ByteAddressBuffer on GPU — loaded via manual byte offsets (256 bytes per object).
[CRepr]
public struct GPUObjectData
{
	public Matrix WorldMatrix;         // offset 0,   64 bytes
	public Matrix PrevWorldMatrix;     // offset 64,  64 bytes
	public Matrix NormalMatrix;        // offset 128, 64 bytes
	public Vector3 BoundsMin;          // offset 192, 12 bytes
	public uint32 ObjectID;            // offset 204, 4 bytes
	public Vector3 BoundsMax;          // offset 208, 12 bytes
	public uint32 MaterialSlot;        // offset 220, 4 bytes
	public uint32 MeshIndex;           // offset 224, 4 bytes
	public uint32 SubMeshIndex;        // offset 228, 4 bytes
	public uint32 Flags;               // offset 232, 4 bytes (StaticMeshFlags packed)
	public uint32 DrawGroupIndex;      // offset 236, 4 bytes (index into indirect command array)
	public uint32 _pad1;               // offset 240, 4 bytes
	public uint32 _pad2;               // offset 244, 4 bytes
	public uint32 _pad3;               // offset 248, 4 bytes
	public uint32 _pad4;               // offset 252, 4 bytes
	// Total: 256 bytes

	public const int Stride = 256;
}

/// Manages the GPU-side scene buffer containing all object data.
/// CPU uploads all active static mesh proxies each frame via staging→GPU copy.
/// The GPU culling compute shader reads this buffer to test visibility.
/// Vertex shaders read per-object transforms from this buffer via instance mapping.
class GPUSceneBuffer
{
	private IDevice mDevice;

	// Per-frame staging + GPU buffers
	private IBuffer[RenderConfig.FrameBufferCount] mStagingBuffers;
	private IBuffer[RenderConfig.FrameBufferCount] mGPUBuffers;
	private void*[RenderConfig.FrameBufferCount] mMappedPtrs;
	private bool[RenderConfig.FrameBufferCount] mHasBeenUsed;

	private uint32 mMaxObjects;
	private uint64 mBufferSize;
	private int[RenderConfig.FrameBufferCount] mObjectCounts;

	/// Maps ProxyHandle.Index → GPUSceneBuffer objectIndex for the current frame.
	/// Allows features to look up the GPU object index for a given proxy.
	private Dictionary<uint32, uint32> mProxyToObjectIndex = new .() ~ delete _;

	/// Draw group ranges for indirect draw submission.
	private List<DrawGroupRange> mDrawGroupRanges = new .() ~ delete _;

	/// Staging data for sorting objects by draw group before upload.
	private struct StagingEntry
	{
		public GPUObjectData ObjectData;
		public ProxyHandle Handle;
		public GPUMeshHandle MeshHandle;
		public MaterialInstanceHandle MaterialHandle;
		public uint32 SubMeshIndex;
	}
	private List<StagingEntry> mStagingEntries = new .() ~ delete _;

	/// Number of objects uploaded this frame.
	public int ObjectCount(int frameIndex) => mObjectCounts[frameIndex];

	/// Draw group ranges for indirect draw submission.
	public List<DrawGroupRange> DrawGroupRanges => mDrawGroupRanges;

	/// Gets the GPU object index for a proxy handle. Returns uint32.MaxValue if not found.
	public uint32 GetObjectIndex(ProxyHandle handle)
	{
		if (mProxyToObjectIndex.TryGetValue(handle.Index, let idx))
			return idx;
		return uint32.MaxValue;
	}

	/// Gets the GPU storage buffer for the given frame (for shader binding).
	public IBuffer GetBuffer(int frameIndex) => mGPUBuffers[frameIndex];

	public Result<void> Initialize(IDevice device, uint32 maxObjects = (uint32)RenderConfig.MaxOpaqueObjects)
	{
		mDevice = device;
		mMaxObjects = maxObjects;
		mBufferSize = (uint64)(maxObjects * GPUObjectData.Stride);

		for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			// GPU storage buffer (shader reads)
			let gpuResult = device.CreateBuffer(BufferDesc()
			{
				Size = mBufferSize,
				Usage = .Storage | .CopyDst,
				Memory = .GpuOnly,
				Label = "GPUSceneBuffer"
			});
			if (gpuResult case .Err)
				return .Err;
			mGPUBuffers[i] = gpuResult.Value;

			// Staging buffer (CPU writes)
			let stagingResult = device.CreateBuffer(BufferDesc()
			{
				Size = mBufferSize,
				Usage = .CopySrc,
				Memory = .CpuToGpu,
				Label = "GPUSceneBuffer_Staging"
			});
			if (stagingResult case .Err)
				return .Err;
			mStagingBuffers[i] = stagingResult.Value;
			mMappedPtrs[i] = mStagingBuffers[i].Map();
		}

		return .Ok;
	}

	/// Uploads all active static mesh proxies to the staging buffer.
	/// Objects are sorted by draw group (material+mesh+submesh) for indirect draw submission.
	/// Call once per frame before RecordUpload.
	public void Update(RenderWorld world, GPUResourceManager resources, int frameIndex)
	{
		mObjectCounts[frameIndex] = 0;
		mProxyToObjectIndex.Clear();
		mDrawGroupRanges.Clear();
		mStagingEntries.Clear();
		if (world == null) return;

		let ptr = (GPUObjectData*)mMappedPtrs[frameIndex];
		if (ptr == null) return;

		// Phase 1: Collect all objects
		world.StaticMeshes.ForEach(scope [&] (handle, proxy) =>
		{
			if (mStagingEntries.Count >= (int)mMaxObjects) return;
			if (!proxy.MeshHandle.IsValid) return;

			let mesh = resources.GetMesh(proxy.MeshHandle);
			if (mesh == null) return;

			let worldBounds = FrustumCuller.TransformAABB(proxy.LocalBounds, proxy.Transform);

			for (uint32 si = 0; si < (uint32)mesh.SubMeshes.Count; si++)
			{
				if (mStagingEntries.Count >= (int)mMaxObjects) break;

				let subMesh = mesh.SubMeshes[si];
				let matSlot = subMesh.MaterialSlot;
				let materialHandle = (matSlot < proxy.MaterialCount)
					? proxy.Materials[matSlot]
					: MaterialInstanceHandle.Invalid;

				var objData = GPUObjectData();
				objData.WorldMatrix = proxy.Transform;
				objData.PrevWorldMatrix = proxy.Transform;
				Matrix.Invert(proxy.Transform, out objData.NormalMatrix);
				objData.NormalMatrix = Matrix.Transpose(objData.NormalMatrix);
				objData.BoundsMin = worldBounds.Min;
				objData.BoundsMax = worldBounds.Max;
				objData.ObjectID = handle.Index;
				objData.MaterialSlot = materialHandle.Index;
				objData.MeshIndex = proxy.MeshHandle.Index;
				objData.SubMeshIndex = si;
				objData.Flags = (uint32)proxy.Flags;

				mStagingEntries.Add(.()
				{
					ObjectData = objData,
					Handle = handle,
					MeshHandle = proxy.MeshHandle,
					MaterialHandle = materialHandle,
					SubMeshIndex = si
				});
			}
		});

		if (mStagingEntries.Count == 0) return;

		// Phase 2: Sort by draw group key (material, mesh, submesh)
		let count = mStagingEntries.Count;
		let sortKeys = scope uint64[count];
		for (int i = 0; i < count; i++)
		{
			let e = mStagingEntries[i];
			sortKeys[i] = ((uint64)e.MaterialHandle.Index << 32) |
						   ((uint64)e.MeshHandle.Index << 16) |
						   (uint64)e.SubMeshIndex;
		}

		let indices = scope int[count];
		for (int i = 0; i < count; i++)
			indices[i] = i;

		for (int i = 1; i < count; i++)
		{
			let key = sortKeys[indices[i]];
			let idx = indices[i];
			var j = i - 1;
			while (j >= 0 && sortKeys[indices[j]] > key)
			{
				indices[j + 1] = indices[j];
				j--;
			}
			indices[j + 1] = idx;
		}

		// Phase 3: Write sorted objects and build draw group ranges
		uint64 prevKey = uint64.MaxValue;
		int groupStart = 0;

		for (int i = 0; i < count; i++)
		{
			let srcIdx = indices[i];
			let entry = mStagingEntries[srcIdx];
			var objData = entry.ObjectData;
			let curKey = sortKeys[srcIdx];

			if (curKey != prevKey)
			{
				if (i > 0)
				{
					var prevRange = mDrawGroupRanges[mDrawGroupRanges.Count - 1];
					prevRange.CommandCount = (uint32)(i - groupStart);
					mDrawGroupRanges[mDrawGroupRanges.Count - 1] = prevRange;
				}

				mDrawGroupRanges.Add(DrawGroupRange()
				{
					MaterialHandle = entry.MaterialHandle,
					MeshHandle = entry.MeshHandle,
					SubMeshIndex = entry.SubMeshIndex,
					CommandOffset = (uint32)i,
					CommandCount = 0
				});
				groupStart = i;
				prevKey = curKey;
			}

			objData.DrawGroupIndex = (uint32)i;
			ptr[i] = objData;
			mProxyToObjectIndex[entry.Handle.Index] = (uint32)i;
		}

		if (mDrawGroupRanges.Count > 0)
		{
			var lastRange = mDrawGroupRanges[mDrawGroupRanges.Count - 1];
			lastRange.CommandCount = (uint32)(count - groupStart);
			mDrawGroupRanges[mDrawGroupRanges.Count - 1] = lastRange;
		}

		mObjectCounts[frameIndex] = count;
	}

	/// Records the staging→GPU copy. Call on the frame's command encoder.
	public void RecordUpload(ICommandEncoder encoder, int frameIndex)
	{
		let count = mObjectCounts[frameIndex];
		if (count == 0) return;

		let copySize = (uint64)(count * GPUObjectData.Stride);

		// Barrier: GPU buffer → CopyDst (first use: Undefined)
		BufferBarrier[1] preBarrier = .(.()
		{
			Buffer = mGPUBuffers[frameIndex],
			OldState = mHasBeenUsed[frameIndex] ? .ShaderRead : .Undefined,
			NewState = .CopyDst
		});
		encoder.Barrier(BarrierGroup()
		{
			BufferBarriers = Span<BufferBarrier>(&preBarrier[0], 1)
		});

		encoder.CopyBufferToBuffer(mStagingBuffers[frameIndex], 0, mGPUBuffers[frameIndex], 0, copySize);

		// Barrier: GPU buffer → ShaderRead (for compute culling + vertex shader)
		BufferBarrier[1] postBarrier = .(.()
		{
			Buffer = mGPUBuffers[frameIndex],
			OldState = .CopyDst,
			NewState = .ShaderRead
		});
		encoder.Barrier(BarrierGroup()
		{
			BufferBarriers = Span<BufferBarrier>(&postBarrier[0], 1)
		});

		mHasBeenUsed[frameIndex] = true;
	}

	public void Shutdown()
	{
		for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			if (mStagingBuffers[i] != null)
			{
				mStagingBuffers[i].Unmap();
				mDevice.DestroyBuffer(ref mStagingBuffers[i]);
			}
			if (mGPUBuffers[i] != null)
				mDevice.DestroyBuffer(ref mGPUBuffers[i]);
		}
	}
}
