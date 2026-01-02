namespace Sedulous.RHI;

/// Blend factors for color blending operations.
enum BlendFactor
{
	/// Factor is 0.
	Zero,
	/// Factor is 1.
	One,
	/// Factor is source color.
	Src,
	/// Factor is 1 - source color.
	OneMinusSrc,
	/// Factor is source alpha.
	SrcAlpha,
	/// Factor is 1 - source alpha.
	OneMinusSrcAlpha,
	/// Factor is destination color.
	Dst,
	/// Factor is 1 - destination color.
	OneMinusDst,
	/// Factor is destination alpha.
	DstAlpha,
	/// Factor is 1 - destination alpha.
	OneMinusDstAlpha,
	/// Factor is min(source alpha, 1 - destination alpha).
	SrcAlphaSaturated,
	/// Factor is constant color.
	Constant,
	/// Factor is 1 - constant color.
	OneMinusConstant,
}
