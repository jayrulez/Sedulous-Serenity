using System;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// Types of drawing primitives.
enum PrimitiveType
{
	/// Filled rectangle.
	FillRect,
	/// Filled rounded rectangle.
	FillRoundedRect,
	/// Filled circle.
	FillCircle,
	/// Filled path/polygon.
	FillPath,
	/// Stroked rectangle.
	DrawRect,
	/// Stroked rounded rectangle.
	DrawRoundedRect,
	/// Stroked circle.
	DrawCircle,
	/// Line segment.
	DrawLine,
	/// Stroked path/polyline.
	DrawPath,
	/// Textured image.
	Image,
	/// Nine-slice image.
	NineSlice,
	/// Text string.
	Text
}

/// A single draw command for batched rendering.
struct DrawCommand
{
	/// The primitive type to draw.
	public PrimitiveType Type;
	/// Bounds for the primitive.
	public RectangleF Bounds;
	/// Fill or stroke color.
	public Color Color;
	/// Border/stroke color (for stroked primitives).
	public Color BorderColor;
	/// Stroke/border thickness.
	public float StrokeWidth;
	/// Corner radius for rounded primitives.
	public CornerRadius CornerRadius;
	/// Texture handle for images.
	public TextureHandle Texture;
	/// Source rectangle in texture (UV coordinates 0-1 or pixel coords).
	public RectangleF SourceRect;
	/// Clip rectangle index.
	public uint16 ClipRectIndex;
	/// Font handle for text.
	public FontHandle Font;
	/// Font size for text.
	public float FontSize;
	/// Vertex offset in batch (for path/polygon commands).
	public uint32 VertexOffset;
	/// Vertex count (for path/polygon commands).
	public uint32 VertexCount;
	/// Index offset in batch.
	public uint32 IndexOffset;
	/// Index count.
	public uint32 IndexCount;
	/// Text string offset in text buffer.
	public uint32 TextOffset;
	/// Text string length.
	public uint32 TextLength;
}

/// Clip rectangle for scissoring.
struct ClipRect
{
	/// The clipping bounds.
	public RectangleF Bounds;
	/// Parent clip rect index (-1 for none).
	public int32 ParentIndex;

	/// Creates a clip rectangle.
	public this(RectangleF bounds, int32 parentIndex = -1)
	{
		Bounds = bounds;
		ParentIndex = parentIndex;
	}
}
