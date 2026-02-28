namespace Sedulous.RHI;

using System;

/// A set of GPU queries that can be used to measure GPU timing, occlusion, or pipeline statistics.
interface IQuerySet : IDisposable
{
	/// The type of queries in this set.
	QueryType Type { get; }

	/// The number of queries in this set.
	uint32 Count { get; }

	/// Reads query results into a buffer.
	/// Returns true if all requested queries are available, false if some are still pending.
	/// For Timestamp queries: results are uint64 GPU ticks.
	/// For Occlusion queries: results are uint64 sample counts.
	/// For PipelineStatistics queries: results are PipelineStatistics structs.
	///
	/// @param firstQuery The index of the first query to read.
	/// @param queryCount The number of queries to read.
	/// @param destination The buffer to write results to. Must be large enough for queryCount results.
	/// @param wait If true, waits for queries to complete. If false, returns false if not ready.
	bool GetResults(uint32 firstQuery, uint32 queryCount, Span<uint8> destination, bool wait = true);
}
