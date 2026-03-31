namespace Sedulous.UI;

/// Layout parameters that a child View provides to its parent ViewGroup.
/// Describes how the child wants to be laid out (size requests and margins).
/// ViewGroup subclasses may create their own LayoutParams subclasses with
/// additional parameters (e.g., weight, gravity, grid position).
public class LayoutParams
{
	/// Special value: child wants to be as big as its parent (minus padding/margins).
	public const float MatchParent = -1;
	/// Special value: child wants to be just big enough to fit its content.
	public const float WrapContent = -2;

	/// Requested width. Can be a pixel value, MatchParent, or WrapContent.
	public float Width = WrapContent;

	/// Requested height. Can be a pixel value, MatchParent, or WrapContent.
	public float Height = WrapContent;

	/// Margins around this child.
	public Thickness Margin;

	public this()
	{
	}

	public this(float width, float height)
	{
		Width = width;
		Height = height;
	}
}
