namespace Sedulous.RHI;

/// Flags describing how a texture will be used.
//[Flags]
enum TextureUsage
{
	None = 0,
	/// Texture can be used as source for copy operations.
	CopySrc = 1 << 0,
	/// Texture can be used as destination for copy operations.
	CopyDst = 1 << 1,
	/// Texture can be sampled in shaders.
	Sampled = 1 << 2,
	/// Texture can be used as storage texture in shaders.
	Storage = 1 << 3,
	/// Texture can be used as a color attachment in render passes.
	RenderTarget = 1 << 4,
	/// Texture can be used as a depth/stencil attachment in render passes.
	DepthStencil = 1 << 5,
}
