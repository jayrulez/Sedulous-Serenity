namespace Sedulous.Render;

/// Anti-aliasing mode for the renderer.
enum AAMode
{
	/// No anti-aliasing.
	None,
	/// Fast Approximate Anti-Aliasing (spatial, single frame).
	FXAA,
	/// Temporal Anti-Aliasing (multi-frame accumulation with motion vectors).
	TAA
}
