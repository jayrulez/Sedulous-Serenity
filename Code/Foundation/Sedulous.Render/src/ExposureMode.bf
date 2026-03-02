namespace Sedulous.Render;

/// Exposure mode for the renderer.
enum ExposureMode
{
	/// Manual exposure set via RenderWorld.Exposure.
	Manual,
	/// Automatic exposure computed from scene luminance histogram.
	Auto
}
