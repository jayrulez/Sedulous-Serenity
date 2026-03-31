namespace Sedulous.Renderer;

/// Tonemapping operator.
public enum TonemapOperator : uint8
{
	None,
	Reinhard,
	ACES,
	Uncharted2,
	Filmic
}

/// Exposure mode.
public enum ExposureMode : uint8
{
	Manual,
	Auto
}

/// Anti-aliasing mode.
public enum AAMode : uint8
{
	None,
	FXAA,
	TAA
}
