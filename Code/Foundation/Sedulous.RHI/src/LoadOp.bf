namespace Sedulous.RHI;

/// Operation to perform when loading a render target attachment.
enum LoadOp
{
	/// Clear the attachment to a specified value.
	Clear,
	/// Load the existing contents of the attachment.
	Load,
	/// Contents are undefined (may be faster if you'll overwrite everything).
	DontCare,
}
