namespace Sedulous.Renderer;

using Sedulous.RHI;

/// Environment configuration for a render world.
/// Encapsulates sky, IBL, and ambient settings.
/// The world carries this data; SkyFeature reads and interprets it.
class EnvironmentSettings
{
	/// HDRI equirectangular texture view for sky rendering. Not owned.
	public ITextureView HdriTexture;
	/// BRDF LUT texture view for IBL split-sum. Not owned.
	public ITextureView BrdfLutTexture;
	/// Sky brightness multiplier.
	public float SkyExposure = 1.0f;
	/// IBL ambient intensity multiplier.
	public float AmbientIntensity = 1.0f;
	// Future: SkyMode (HDRI/Procedural/SolidColor), procedural params, etc.
}
