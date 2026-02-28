using Sedulous.Core.Mathematics;
namespace UISandbox;

/// Wrapper class for Color to allow storing in DragData.
class ColorBox
{
	public Color Value;
	public this(Color color) { Value = color; }
}