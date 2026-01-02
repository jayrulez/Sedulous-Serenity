namespace Sedulous.RHI;

/// Operation to perform when storing a render target attachment.
enum StoreOp
{
	/// Store the contents for later use.
	Store,
	/// Contents may be discarded (may be faster if you don't need the results).
	Discard,
}
