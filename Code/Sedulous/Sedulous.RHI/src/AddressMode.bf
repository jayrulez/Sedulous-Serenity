namespace Sedulous.RHI;

/// Texture addressing mode for coordinates outside [0, 1].
enum AddressMode
{
	/// Texture coordinates wrap around (tile).
	Repeat,
	/// Texture coordinates mirror at boundaries.
	MirrorRepeat,
	/// Texture coordinates are clamped to edge texels.
	ClampToEdge,
	/// Texture coordinates outside range return border color.
	ClampToBorder,
}
