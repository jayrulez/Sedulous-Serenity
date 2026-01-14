namespace Sedulous.RendererNext;

/// Centralized frame configuration constants for the renderer.
/// All multi-buffering and frame-related constants should be defined here.
static class FrameConfig
{
	/// Number of frames that can be in flight simultaneously.
	/// This determines the size of per-frame resource arrays.
	public const int32 MAX_FRAMES_IN_FLIGHT = 2;

	/// Number of frames to defer resource deletion.
	/// Must be >= MAX_FRAMES_IN_FLIGHT to ensure GPU is done with resources.
	public const int32 DELETION_DEFER_FRAMES = MAX_FRAMES_IN_FLIGHT + 1;
}
