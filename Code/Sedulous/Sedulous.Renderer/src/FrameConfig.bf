namespace Sedulous.Renderer;

/// Central frame configuration. All renderer systems should use these constants
/// instead of defining their own MAX_FRAMES or MAX_FRAMES_IN_FLIGHT.
static class FrameConfig
{
	/// Maximum frames in flight (double buffering).
	/// This is the number of frames that can be processed simultaneously
	/// by CPU and GPU to maximize throughput.
	public const int32 MAX_FRAMES_IN_FLIGHT = 2;

	/// Frames to defer deletion to ensure GPU has finished using resources.
	/// Resources queued for deletion will be held for this many frames
	/// before actually being deleted.
	public const int32 DELETION_DEFER_FRAMES = MAX_FRAMES_IN_FLIGHT + 1;
}
