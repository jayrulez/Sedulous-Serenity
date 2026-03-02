namespace Sedulous.Render;

/// Tonemapping operator selection.
enum TonemapOperator
{
	/// ACES filmic curve (Narkowicz approximation). Vibrant, cinematic.
	ACES,
	/// Reinhard operator. Simple, preserves color ratios.
	Reinhard,
	/// Uncharted 2 filmic curve. Good shadow detail, filmic rolloff.
	Uncharted2
}
