namespace Sedulous.RendererNG;

using System;
using System.Collections;

/// A draw command representing a single renderable item.
struct DrawCommand : IHashable
{
	/// Sort key (lower = rendered first).
	/// Composed of: [depth(16)] [pipeline(16)] [material(16)] [mesh(16)]
	public uint64 SortKey;

	/// Index into the proxy pool.
	public uint32 ProxyIndex;

	/// View index this draw belongs to.
	public uint16 ViewIndex;

	/// Layer for sorting (opaque=0, transparent=1, overlay=2).
	public uint8 Layer;

	/// Flags.
	public uint8 Flags;

	public int GetHashCode() => (int)SortKey;

	/// Creates a sort key for opaque objects (front-to-back by distance).
	public static uint64 MakeOpaqueKey(uint16 pipelineId, uint16 materialId, uint16 meshId, float depth)
	{
		// Opaque: sort front-to-back (lower depth first) to maximize early-Z rejection
		uint16 depthKey = (uint16)(Math.Clamp(depth, 0, 1) * 65535);
		return ((uint64)depthKey << 48) | ((uint64)pipelineId << 32) | ((uint64)materialId << 16) | (uint64)meshId;
	}

	/// Creates a sort key for transparent objects (back-to-front by distance).
	public static uint64 MakeTransparentKey(uint16 pipelineId, uint16 materialId, uint16 meshId, float depth)
	{
		// Transparent: sort back-to-front (higher depth first) for correct blending
		uint16 depthKey = (uint16)((1.0f - Math.Clamp(depth, 0, 1)) * 65535);
		return ((uint64)depthKey << 48) | ((uint64)pipelineId << 32) | ((uint64)materialId << 16) | (uint64)meshId;
	}

	/// Creates a sort key minimizing state changes (pipeline > material > mesh).
	public static uint64 MakeStateKey(uint16 pipelineId, uint16 materialId, uint16 meshId)
	{
		return ((uint64)pipelineId << 32) | ((uint64)materialId << 16) | (uint64)meshId;
	}
}

/// A batch of draw commands that share the same pipeline and material.
struct DrawBatch
{
	/// Pipeline handle for this batch.
	public uint16 PipelineId;

	/// Material handle for this batch.
	public uint16 MaterialId;

	/// First command index in the sorted command list.
	public uint32 FirstCommand;

	/// Number of commands in this batch.
	public uint32 CommandCount;

	/// Total instance count for this batch.
	public uint32 InstanceCount;
}

/// Collects and sorts draw commands for optimal rendering.
class DrawBatcher
{
	// Command storage
	private List<DrawCommand> mCommands = new .() ~ delete _;
	private List<DrawCommand> mSortedCommands = new .() ~ delete _;

	// Batch storage
	private List<DrawBatch> mOpaqueBatches = new .() ~ delete _;
	private List<DrawBatch> mTransparentBatches = new .() ~ delete _;

	// Statistics
	public int32 CommandCount => (int32)mCommands.Count;
	public int32 OpaqueBatchCount => (int32)mOpaqueBatches.Count;
	public int32 TransparentBatchCount => (int32)mTransparentBatches.Count;

	/// Clears all commands and batches for a new frame.
	public void Clear()
	{
		mCommands.Clear();
		mSortedCommands.Clear();
		mOpaqueBatches.Clear();
		mTransparentBatches.Clear();
	}

	/// Adds an opaque draw command.
	public void AddOpaque(uint32 proxyIndex, uint16 viewIndex, uint16 pipelineId, uint16 materialId, uint16 meshId, float depth)
	{
		DrawCommand cmd;
		cmd.SortKey = DrawCommand.MakeOpaqueKey(pipelineId, materialId, meshId, depth);
		cmd.ProxyIndex = proxyIndex;
		cmd.ViewIndex = viewIndex;
		cmd.Layer = 0;
		cmd.Flags = 0;
		mCommands.Add(cmd);
	}

	/// Adds a transparent draw command.
	public void AddTransparent(uint32 proxyIndex, uint16 viewIndex, uint16 pipelineId, uint16 materialId, uint16 meshId, float depth)
	{
		DrawCommand cmd;
		cmd.SortKey = DrawCommand.MakeTransparentKey(pipelineId, materialId, meshId, depth);
		cmd.ProxyIndex = proxyIndex;
		cmd.ViewIndex = viewIndex;
		cmd.Layer = 1;
		cmd.Flags = 0;
		mCommands.Add(cmd);
	}

	/// Adds a draw command with custom sort key.
	public void AddCommand(DrawCommand cmd)
	{
		mCommands.Add(cmd);
	}

	/// Sorts commands and builds batches.
	public void BuildBatches()
	{
		if (mCommands.Count == 0)
			return;

		// Copy to sorted list
		mSortedCommands.Clear();
		mSortedCommands.AddRange(mCommands);

		// Sort by layer first, then by sort key
		mSortedCommands.Sort(scope (a, b) =>
		{
			if (a.Layer != b.Layer)
				return a.Layer <=> b.Layer;
			return a.SortKey <=> b.SortKey;
		});

		// Build batches for each layer
		BuildLayerBatches(0, mOpaqueBatches);
		BuildLayerBatches(1, mTransparentBatches);
	}

	/// Builds batches for a specific layer.
	private void BuildLayerBatches(uint8 layer, List<DrawBatch> batches)
	{
		batches.Clear();

		int firstIndex = -1;
		uint16 currentPipeline = uint16.MaxValue;
		uint16 currentMaterial = uint16.MaxValue;

		for (int i = 0; i < mSortedCommands.Count; i++)
		{
			let cmd = ref mSortedCommands[i];
			if (cmd.Layer != layer)
				continue;

			// Extract pipeline and material from sort key
			uint16 pipelineId = (uint16)((cmd.SortKey >> 32) & 0xFFFF);
			uint16 materialId = (uint16)((cmd.SortKey >> 16) & 0xFFFF);

			// Check if we need to start a new batch
			if (pipelineId != currentPipeline || materialId != currentMaterial)
			{
				// Finalize previous batch
				if (firstIndex >= 0)
				{
					FinalizeBatch(batches, currentPipeline, currentMaterial, (uint32)firstIndex, (uint32)(i - firstIndex));
				}

				// Start new batch
				firstIndex = i;
				currentPipeline = pipelineId;
				currentMaterial = materialId;
			}
		}

		// Finalize last batch
		if (firstIndex >= 0)
		{
			int lastIndex = 0;
			for (int i = mSortedCommands.Count - 1; i >= 0; i--)
			{
				if (mSortedCommands[i].Layer == layer)
				{
					lastIndex = i + 1;
					break;
				}
			}
			FinalizeBatch(batches, currentPipeline, currentMaterial, (uint32)firstIndex, (uint32)(lastIndex - firstIndex));
		}
	}

	/// Finalizes a batch.
	private void FinalizeBatch(List<DrawBatch> batches, uint16 pipelineId, uint16 materialId, uint32 firstCommand, uint32 commandCount)
	{
		if (commandCount == 0)
			return;

		DrawBatch batch;
		batch.PipelineId = pipelineId;
		batch.MaterialId = materialId;
		batch.FirstCommand = firstCommand;
		batch.CommandCount = commandCount;
		batch.InstanceCount = commandCount; // 1:1 for now, can be optimized for instancing
		batches.Add(batch);
	}

	/// Gets the opaque batches.
	public Span<DrawBatch> OpaqueBatches => mOpaqueBatches;

	/// Gets the transparent batches.
	public Span<DrawBatch> TransparentBatches => mTransparentBatches;

	/// Gets a sorted command by index.
	public DrawCommand GetCommand(int index) => mSortedCommands[index];

	/// Gets all sorted commands.
	public Span<DrawCommand> SortedCommands => mSortedCommands;

	/// Iterates commands in a batch.
	public void ForEachInBatch(DrawBatch batch, delegate void(DrawCommand cmd) callback)
	{
		for (uint32 i = 0; i < batch.CommandCount; i++)
		{
			callback(mSortedCommands[(int)(batch.FirstCommand + i)]);
		}
	}

	/// Gets statistics string.
	public void GetStats(String outStr)
	{
		outStr.AppendF("Draw Batcher Stats:\n");
		outStr.AppendF("  Total Commands: {0}\n", mCommands.Count);
		outStr.AppendF("  Opaque Batches: {0}\n", mOpaqueBatches.Count);
		outStr.AppendF("  Transparent Batches: {0}\n", mTransparentBatches.Count);

		int opaqueCommands = 0;
		for (let batch in mOpaqueBatches)
			opaqueCommands += (int)batch.CommandCount;

		int transparentCommands = 0;
		for (let batch in mTransparentBatches)
			transparentCommands += (int)batch.CommandCount;

		outStr.AppendF("  Opaque Commands: {0}\n", opaqueCommands);
		outStr.AppendF("  Transparent Commands: {0}\n", transparentCommands);
	}
}
