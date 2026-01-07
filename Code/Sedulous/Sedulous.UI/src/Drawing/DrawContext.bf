using System;
using System.Collections;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// Drawing context for rendering UI elements.
class DrawContext
{
	private DrawBatch mBatch;
	private List<uint16> mClipStack = new .() ~ delete _;
	private uint16 mCurrentClipIndex = uint16.MaxValue;

	/// Creates a draw context with a new batch.
	public this()
	{
		mBatch = new DrawBatch();
	}

	/// Creates a draw context with an existing batch.
	public this(DrawBatch batch)
	{
		mBatch = batch;
	}

	/// Disposes the draw context.
	public ~this()
	{
		delete mBatch;
	}

	/// Gets the underlying draw batch.
	public DrawBatch Batch => mBatch;

	// ============ Filled Primitives ============

	/// Fills a rectangle.
	public void FillRect(RectangleF rect, Color color)
	{
		var cmd = DrawCommand();
		cmd.Type = .FillRect;
		cmd.Bounds = rect;
		cmd.Color = color;
		cmd.ClipRectIndex = mCurrentClipIndex;
		mBatch.Commands.Add(cmd);
	}

	/// Fills a rounded rectangle.
	public void FillRoundedRect(RectangleF rect, CornerRadius radius, Color color)
	{
		var cmd = DrawCommand();
		cmd.Type = .FillRoundedRect;
		cmd.Bounds = rect;
		cmd.Color = color;
		cmd.CornerRadius = radius;
		cmd.ClipRectIndex = mCurrentClipIndex;
		mBatch.Commands.Add(cmd);
	}

	/// Fills a circle.
	public void FillCircle(Vector2 center, float radius, Color color)
	{
		var cmd = DrawCommand();
		cmd.Type = .FillCircle;
		cmd.Bounds = RectangleF(center.X - radius, center.Y - radius, radius * 2, radius * 2);
		cmd.Color = color;
		cmd.ClipRectIndex = mCurrentClipIndex;
		mBatch.Commands.Add(cmd);
	}

	/// Fills a polygon/path.
	public void FillPath(Span<Vector2> points, Color color)
	{
		if (points.Length < 3)
			return;

		// Add vertices
		var verts = scope UIVertex[points.Length];
		for (int i < points.Length)
			verts[i] = UIVertex(points[i], .Zero, color);

		let vertOffset = mBatch.AddVertices(verts);

		// Triangulate (simple fan triangulation)
		let indexCount = (points.Length - 2) * 3;
		var indices = scope uint16[indexCount];
		for (int i < points.Length - 2)
		{
			indices[i * 3 + 0] = 0;
			indices[i * 3 + 1] = (uint16)(i + 1);
			indices[i * 3 + 2] = (uint16)(i + 2);
		}
		let indexOffset = mBatch.AddIndices(indices);

		var cmd = DrawCommand();
		cmd.Type = .FillPath;
		cmd.Color = color;
		cmd.VertexOffset = vertOffset;
		cmd.VertexCount = (uint32)points.Length;
		cmd.IndexOffset = indexOffset;
		cmd.IndexCount = (uint32)indexCount;
		cmd.ClipRectIndex = mCurrentClipIndex;
		mBatch.Commands.Add(cmd);
	}

	// ============ Stroked Primitives ============

	/// Draws a rectangle outline.
	public void DrawRect(RectangleF rect, Color color, float thickness = 1)
	{
		var cmd = DrawCommand();
		cmd.Type = .DrawRect;
		cmd.Bounds = rect;
		cmd.Color = color;
		cmd.StrokeWidth = thickness;
		cmd.ClipRectIndex = mCurrentClipIndex;
		mBatch.Commands.Add(cmd);
	}

	/// Draws a rounded rectangle outline.
	public void DrawRoundedRect(RectangleF rect, CornerRadius radius, Color color, float thickness = 1)
	{
		var cmd = DrawCommand();
		cmd.Type = .DrawRoundedRect;
		cmd.Bounds = rect;
		cmd.Color = color;
		cmd.CornerRadius = radius;
		cmd.StrokeWidth = thickness;
		cmd.ClipRectIndex = mCurrentClipIndex;
		mBatch.Commands.Add(cmd);
	}

	/// Draws a circle outline.
	public void DrawCircle(Vector2 center, float radius, Color color, float thickness = 1)
	{
		var cmd = DrawCommand();
		cmd.Type = .DrawCircle;
		cmd.Bounds = RectangleF(center.X - radius, center.Y - radius, radius * 2, radius * 2);
		cmd.Color = color;
		cmd.StrokeWidth = thickness;
		cmd.ClipRectIndex = mCurrentClipIndex;
		mBatch.Commands.Add(cmd);
	}

	/// Draws a line.
	public void DrawLine(Vector2 start, Vector2 end, Color color, float thickness = 1)
	{
		var cmd = DrawCommand();
		cmd.Type = .DrawLine;
		cmd.Bounds = RectangleF(
			Math.Min(start.X, end.X),
			Math.Min(start.Y, end.Y),
			Math.Abs(end.X - start.X),
			Math.Abs(end.Y - start.Y)
		);
		cmd.Color = color;
		cmd.StrokeWidth = thickness;
		cmd.ClipRectIndex = mCurrentClipIndex;

		// Store endpoints in vertices
		UIVertex[2] verts = .(
			UIVertex(start, .Zero, color),
			UIVertex(end, .Zero, color)
		);
		cmd.VertexOffset = mBatch.AddVertices(verts);
		cmd.VertexCount = 2;

		mBatch.Commands.Add(cmd);
	}

	/// Draws a path/polyline.
	public void DrawPath(Span<Vector2> points, Color color, float thickness = 1, bool closed = false)
	{
		if (points.Length < 2)
			return;

		// Add vertices
		var verts = scope UIVertex[points.Length];
		for (int i < points.Length)
			verts[i] = UIVertex(points[i], .Zero, color);

		let vertOffset = mBatch.AddVertices(verts);

		var cmd = DrawCommand();
		cmd.Type = .DrawPath;
		cmd.Color = color;
		cmd.StrokeWidth = thickness;
		cmd.VertexOffset = vertOffset;
		cmd.VertexCount = (uint32)points.Length;
		// Use IndexCount = 1 to indicate closed path
		cmd.IndexCount = closed ? 1 : 0;
		cmd.ClipRectIndex = mCurrentClipIndex;
		mBatch.Commands.Add(cmd);
	}

	// ============ Images ============

	/// Draws an image.
	public void DrawImage(TextureHandle texture, RectangleF destRect, Color tint = .White)
	{
		DrawImage(texture, destRect, RectangleF(0, 0, 1, 1), tint);
	}

	/// Draws an image with source rectangle.
	public void DrawImage(TextureHandle texture, RectangleF destRect, RectangleF sourceRect, Color tint = .White)
	{
		var cmd = DrawCommand();
		cmd.Type = .Image;
		cmd.Bounds = destRect;
		cmd.Color = tint;
		cmd.Texture = texture;
		cmd.SourceRect = sourceRect;
		cmd.ClipRectIndex = mCurrentClipIndex;
		mBatch.Commands.Add(cmd);
	}

	/// Draws a nine-slice image.
	public void DrawNineSlice(TextureHandle texture, RectangleF destRect, Thickness slices, Color tint = .White)
	{
		var cmd = DrawCommand();
		cmd.Type = .NineSlice;
		cmd.Bounds = destRect;
		cmd.Color = tint;
		cmd.Texture = texture;
		// Store slices in SourceRect (creative reuse)
		cmd.SourceRect = RectangleF(slices.Left, slices.Top, slices.Right, slices.Bottom);
		cmd.ClipRectIndex = mCurrentClipIndex;
		mBatch.Commands.Add(cmd);
	}

	// ============ Text ============

	/// Draws text at a position.
	public void DrawText(StringView text, FontHandle font, float size, Vector2 position, Color color)
	{
		if (text.IsEmpty)
			return;

		let textOffset = mBatch.AddText(text);

		var cmd = DrawCommand();
		cmd.Type = .Text;
		cmd.Bounds = RectangleF(position.X, position.Y, 0, 0);
		cmd.Color = color;
		cmd.Font = font;
		cmd.FontSize = size;
		cmd.TextOffset = textOffset;
		cmd.TextLength = (uint32)text.Length;
		cmd.ClipRectIndex = mCurrentClipIndex;
		mBatch.Commands.Add(cmd);
	}

	/// Draws text within bounds with alignment.
	public void DrawText(StringView text, FontHandle font, float size, RectangleF bounds, Color color,
		TextAlignment hAlign = .Start, TextAlignment vAlign = .Start, bool wrap = false)
	{
		if (text.IsEmpty)
			return;

		let textOffset = mBatch.AddText(text);

		var cmd = DrawCommand();
		cmd.Type = .Text;
		cmd.Bounds = bounds;
		cmd.Color = color;
		cmd.Font = font;
		cmd.FontSize = size;
		cmd.TextOffset = textOffset;
		cmd.TextLength = (uint32)text.Length;
		// Encode alignment in SourceRect
		cmd.SourceRect = RectangleF((float)hAlign, (float)vAlign, wrap ? 1 : 0, 0);
		cmd.ClipRectIndex = mCurrentClipIndex;
		mBatch.Commands.Add(cmd);
	}

	// ============ Clipping ============

	/// Pushes a clip rectangle.
	public void PushClip(RectangleF clipRect)
	{
		// Intersect with current clip
		var finalRect = clipRect;
		if (mCurrentClipIndex != uint16.MaxValue && mCurrentClipIndex < mBatch.ClipRects.Count)
		{
			let current = mBatch.ClipRects[mCurrentClipIndex];
			finalRect = RectangleF.Intersect(finalRect, current.Bounds);
		}

		let newIndex = mBatch.AddClipRect(finalRect, (int32)mCurrentClipIndex);
		mClipStack.Add(mCurrentClipIndex);
		mCurrentClipIndex = newIndex;
	}

	/// Pops the current clip rectangle.
	public void PopClip()
	{
		if (mClipStack.Count > 0)
		{
			mCurrentClipIndex = mClipStack.PopBack();
		}
		else
		{
			mCurrentClipIndex = uint16.MaxValue;
		}
	}

	// ============ Utilities ============

	/// Clears the batch and resets state.
	public void Clear()
	{
		mBatch.Clear();
		mClipStack.Clear();
		mCurrentClipIndex = uint16.MaxValue;
	}

	/// Finishes drawing and returns the batch.
	public DrawBatch Finish()
	{
		let batch = mBatch;
		mBatch = new DrawBatch();
		mClipStack.Clear();
		mCurrentClipIndex = uint16.MaxValue;
		return batch;
	}
}
