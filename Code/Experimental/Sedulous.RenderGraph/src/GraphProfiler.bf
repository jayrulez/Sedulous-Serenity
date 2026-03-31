namespace Sedulous.RenderGraph;

using System;
using System.Collections;
using Sedulous.RHI;

/// Per-pass GPU timing result.
struct PassTiming
{
	public String PassName;
	public QueueType Queue;
	/// GPU time in milliseconds.
	public float GpuTimeMs;
}

/// Optional GPU profiler that inserts timestamp queries around each pass.
/// Attach to a RenderGraph to collect per-pass GPU timing data.
class GraphProfiler
{
	private IDevice mDevice;
	private IQuerySet mQuerySet;
	private IBuffer mReadbackBuffer;
	private int32 mMaxPasses;
	private float mTimestampPeriod; // nanoseconds per tick
	private List<PassTiming> mTimings = new .() ~ {
		for (var t in _) delete t.PassName;
		delete _;
	};
	private bool mEnabled;

	/// Maximum number of passes that can be profiled.
	public int32 MaxPasses => mMaxPasses;

	/// Whether profiling is currently enabled.
	public bool Enabled
	{
		get => mEnabled;
		set => mEnabled = value;
	}

	/// Per-pass timing results from the last completed frame.
	public List<PassTiming> Timings => mTimings;

	/// Creates a profiler that can handle up to maxPasses per frame.
	/// Each pass uses 2 timestamp queries (begin + end).
	public this(int32 maxPasses = 64)
	{
		mMaxPasses = maxPasses;
	}

	/// Initializes GPU resources for profiling. Must be called with a valid device.
	public Result<void> Init(IDevice device, QueueType queue)
	{
		mDevice = device;

		// 2 timestamps per pass (begin + end)
		let queryCount = (uint32)(mMaxPasses * 2);

		switch (device.CreateQuerySet(.() { Type = .Timestamp, Count = queryCount, Label = "RenderGraph_Profiler" }))
		{
		case .Ok(let qs):
			mQuerySet = qs;
		case .Err:
			return .Err;
		}

		// Readback buffer: 8 bytes per timestamp (uint64)
		let bufferSize = (uint64)(queryCount * 8);
		switch (device.CreateBuffer(.()
		{
			Size = bufferSize,
			Usage = .CopyDst,
			Memory = .GpuToCpu,
			Label = "RenderGraph_TimestampReadback"
		}))
		{
		case .Ok(let buf):
			mReadbackBuffer = buf;
		case .Err:
			device.DestroyQuerySet(ref mQuerySet);
			return .Err;
		}

		// Get timestamp period from the queue
		let q = device.GetQueue(queue);
		mTimestampPeriod = q.TimestampPeriod;

		mEnabled = true;
		return .Ok;
	}

	/// Inserts a begin-timestamp for the given pass.
	/// Call before the pass executes.
	public void BeginPass(ICommandEncoder encoder, int32 passIndex)
	{
		if (!mEnabled || mQuerySet == null || passIndex >= mMaxPasses)
			return;

		let queryIndex = (uint32)(passIndex * 2);
		encoder.WriteTimestamp(mQuerySet, queryIndex);
	}

	/// Inserts an end-timestamp for the given pass.
	/// Call after the pass executes.
	public void EndPass(ICommandEncoder encoder, int32 passIndex)
	{
		if (!mEnabled || mQuerySet == null || passIndex >= mMaxPasses)
			return;

		let queryIndex = (uint32)(passIndex * 2 + 1);
		encoder.WriteTimestamp(mQuerySet, queryIndex);
	}

	/// Resolves timestamp queries to the readback buffer.
	/// Call after all passes have been recorded, before Finish().
	public void Resolve(ICommandEncoder encoder, int32 passCount)
	{
		if (!mEnabled || mQuerySet == null)
			return;

		let queryCount = (uint32)(Math.Min(passCount, mMaxPasses) * 2);
		encoder.ResetQuerySet(mQuerySet, 0, queryCount);
		encoder.ResolveQuerySet(mQuerySet, 0, queryCount, mReadbackBuffer, 0);
	}

	/// Reads back timestamp data and computes per-pass GPU time.
	/// Call after the GPU has finished executing (fence wait).
	/// Pass names are copied from the graph's scheduled passes.
	public void ReadResults(RenderGraph graph)
	{
		// Clear previous timings
		for (var t in mTimings) delete t.PassName;
		mTimings.Clear();

		if (!mEnabled || mReadbackBuffer == null)
			return;

		// Map the readback buffer
		let mappedPtr = mReadbackBuffer.Map();
		if (mappedPtr == null)
			return;

		let timestamps = (uint64*)mappedPtr;
		let passCount = Math.Min(graph.ScheduledPassCount, (int)mMaxPasses);

		for (int i = 0; i < passCount; i++)
		{
			let pass = graph.GetScheduledPass(i);
			let beginTs = timestamps[i * 2];
			let endTs = timestamps[i * 2 + 1];

			// Convert ticks to milliseconds
			let deltaTicks = (endTs > beginTs) ? (endTs - beginTs) : 0;
			let gpuTimeNs = (float)deltaTicks * mTimestampPeriod;
			let gpuTimeMs = gpuTimeNs / 1000000.0f;

			mTimings.Add(.()
			{
				PassName = new String(pass.Name),
				Queue = pass.QueueType,
				GpuTimeMs = gpuTimeMs
			});
		}

		mReadbackBuffer.Unmap();
	}

	/// Formats timing results as a text report.
	public void FormatReport(String outText)
	{
		if (mTimings.Count == 0)
		{
			outText.Append("No GPU timing data available.\n");
			return;
		}

		float totalMs = 0;
		for (let t in mTimings)
			totalMs += t.GpuTimeMs;

		outText.Append("=== GPU Pass Timings ===\n");
		outText.Append("Pass                           Queue  Time (ms)\n");
		outText.Append("----                           -----  ---------\n");

		for (let t in mTimings)
		{
			let queueLabel = GetQueueLabel(t.Queue);
			outText.AppendF(scope $"{t.PassName} ({queueLabel}) — {t.GpuTimeMs:F3} ms\n");
		}

		outText.Append("---\n");
		outText.AppendF(scope $"Total: {totalMs:F3} ms\n");
	}

	/// Cleans up GPU resources.
	public void Destroy()
	{
		if (mDevice != null)
		{
			if (mQuerySet != null)
				mDevice.DestroyQuerySet(ref mQuerySet);
			if (mReadbackBuffer != null)
				mDevice.DestroyBuffer(ref mReadbackBuffer);
		}
	}

	private static StringView GetQueueLabel(QueueType queue)
	{
		switch (queue)
		{
		case .Graphics: return "GFX";
		case .Compute:  return "CMP";
		case .Transfer: return "XFR";
		}
	}
}
