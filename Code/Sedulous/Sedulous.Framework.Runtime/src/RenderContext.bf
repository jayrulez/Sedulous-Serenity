using Sedulous.RHI;
using Sedulous.Mathematics;

namespace Sedulous.Framework.Runtime;

struct RenderContext
{
	/// Command encoder for recording GPU commands.
	public ICommandEncoder Encoder;

	/// The swap chain for presentation.
	public ISwapChain SwapChain;

	/// View of the current back buffer texture.
	public ITextureView CurrentTextureView;

	/// Depth texture view, or null if depth is disabled.
	public ITextureView DepthTextureView;

	/// Frame timing information.
	public FrameContext Frame;

	/// Clear color for default render pass.
	public Color ClearColor;
}
