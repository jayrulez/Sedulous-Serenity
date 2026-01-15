namespace Sedulous.RHI;

/// Central frame configuration. All systems using multi-buffered GPU resources
/// should use these constants instead of defining their own MAX_FRAMES constants.
///
/// This is placed in Sedulous.RHI (the base rendering layer) so that all higher-level
/// modules (Renderer, AppFramework, Engine.Runtime, etc.) can reference it.
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
