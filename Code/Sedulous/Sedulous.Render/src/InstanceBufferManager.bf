namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;
using Sedulous.Materials;

/// Per-instance data for GPU instancing.
/// Just the raw matrix - same memory layout as Matrix [CRepr].
[CRepr]
public struct InstanceData
{
	public Matrix WorldMatrix;

	/// Size in bytes.
	public const uint64 Size = 64; // 4x4 floats = 64 bytes

	/// Creates instance data from a world matrix.
	public static Self FromMatrix(Matrix worldMatrix)
	{
		return .() { WorldMatrix = worldMatrix };
	}
}

/// Manages instance buffers for GPU instancing.
/// Allocates per-frame buffers and handles data upload.
public class InstanceBufferManager
{
	/// Per-frame instance buffers.
	private IBuffer[RenderConfig.FrameBufferCount] mInstanceBuffers;

	/// Maximum instances per frame.
	private int32 mMaxInstances;

	/// Whether buffers are initialized.
	private bool mInitialized = false;

	/// Device reference for buffer creation.
	private IDevice mDevice;

	/// Gets the instance buffer for a frame.
	public IBuffer GetBuffer(int32 frameIndex) => mInstanceBuffers[frameIndex];

	/// Gets whether the manager is initialized.
	public bool IsInitialized => mInitialized;

	/// Initializes instance buffers.
	public Result<void> Initialize(IDevice device, int32 maxInstances = RenderConfig.MaxInstancesPerFrame)
	{
		mDevice = device;
		mMaxInstances = maxInstances;

		let bufferSize = (uint64)(maxInstances * (int32)InstanceData.Size);

		for (int32 i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			BufferDescriptor bufDesc = .()
			{
				Size = bufferSize,
				Usage = .Vertex,
				MemoryAccess = .Upload, // CPU-writable for fast updates
				Label = "InstanceBuffer"
			};

			switch (device.CreateBuffer(&bufDesc))
			{
			case .Ok(let buffer): mInstanceBuffers[i] = buffer;
			case .Err: return .Err;
			}
		}

		mInitialized = true;
		return .Ok;
	}

	/// Shuts down and releases buffers.
	public void Shutdown()
	{
		for (int32 i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			if (mInstanceBuffers[i] != null)
			{
				delete mInstanceBuffers[i];
				mInstanceBuffers[i] = null;
			}
		}
		mInitialized = false;
	}

	/// Uploads instance data for the current frame.
	/// Returns the number of instances uploaded.
	public int32 UploadInstanceData(int32 frameIndex, DrawBatcher batcher)
	{
		if (!mInitialized)
			return 0;

		let buffer = mInstanceBuffers[frameIndex];
		if (buffer == null)
			return 0;

		// Map buffer
		void* bufferPtr = buffer.Map();
		if (bufferPtr == null)
			return 0;

		defer buffer.Unmap();

		let commands = batcher.DrawCommands;
		int32 instanceIndex = 0;

		// Upload instance data for opaque instance groups
		for (let group in batcher.OpaqueInstanceGroups)
		{
			if (instanceIndex + group.InstanceCount > mMaxInstances)
				break;

			for (int32 i = 0; i < group.InstanceCount; i++)
			{
				let cmd = commands[group.CommandStart + i];
				var instanceData = InstanceData.FromMatrix(cmd.WorldMatrix);
				let offset = (instanceIndex + i) * (int32)InstanceData.Size;
				Internal.MemCpy((uint8*)bufferPtr + offset, &instanceData, InstanceData.Size);
			}

			instanceIndex += group.InstanceCount;
		}

		// Upload instance data for transparent instance groups
		for (let group in batcher.TransparentInstanceGroups)
		{
			if (instanceIndex + group.InstanceCount > mMaxInstances)
				break;

			for (int32 i = 0; i < group.InstanceCount; i++)
			{
				let cmd = commands[group.CommandStart + i];
				var instanceData = InstanceData.FromMatrix(cmd.WorldMatrix);
				let offset = (instanceIndex + i) * (int32)InstanceData.Size;
				Internal.MemCpy((uint8*)bufferPtr + offset, &instanceData, InstanceData.Size);
			}

			instanceIndex += group.InstanceCount;
		}

		return instanceIndex;
	}

	/// Gets the byte stride for instance data.
	public uint64 Stride => InstanceData.Size;
}
