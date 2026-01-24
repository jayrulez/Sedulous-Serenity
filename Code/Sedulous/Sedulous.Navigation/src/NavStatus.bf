using System;

namespace Sedulous.Navigation;

/// Represents the result status of a navigation operation.
enum NavStatus : int32
{
	/// The operation completed successfully.
	Success = 0,
	/// The operation failed.
	Failure = 1,
	/// The operation is still in progress (for sliced queries).
	InProgress = 2,
	/// A partial result was returned (e.g., path buffer too small).
	PartialResult = 3,
	/// The specified polygon reference is invalid.
	InvalidParam = 4,
	/// The navmesh data is not initialized or corrupt.
	InvalidData = 5,
	/// The buffer provided is too small to hold the result.
	BufferTooSmall = 6,
	/// No path could be found to the target.
	PathNotFound = 7,
	/// The query ran out of node pool space.
	OutOfNodes = 8
}

extension NavStatus
{
	/// Returns true if the status indicates success or partial result.
	public bool Succeeded => this == .Success || this == .PartialResult;

	/// Returns true if the status indicates a failure.
	public bool Failed => !Succeeded && this != .InProgress;
}
