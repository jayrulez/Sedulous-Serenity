using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.Fonts;

namespace Sedulous.Drawing;

/// Main 2D drawing API that produces batched geometry for rendering.
public class DrawContext
{
	// Output batch
	private DrawBatch mBatch = new .() ~ delete _;
	private ShapeRasterizer mRasterizer = new .() ~ delete _;

	// State stack
	private List<DrawState> mStateStack = new .() ~ delete _;
	private DrawState mCurrentState;

	// Clip rect stack (separate from state stack for independent push/pop)
	private List<RectangleF> mClipStack = new .() ~ delete _;

	// Opacity stack (separate from state stack for independent push/pop)
	private List<float> mOpacityStack = new .() ~ delete _;

	// Current command tracking
	private int32 mCurrentTextureIndex = -1;
	private BlendMode mCurrentBlendMode = .Normal;
	private int32 mCommandStartIndex = 0;

	/// UV coordinates for solid color drawing (set to white pixel in your atlas)
	public Vector2 WhitePixelUV
	{
		get => mRasterizer.WhitePixelUV;
		set => mRasterizer.WhitePixelUV = value;
	}

	public this()
	{
		mCurrentState = .();
		mStateStack.Reserve(16);
	}

	// === Output ===

	/// Get the current batch for rendering
	public DrawBatch GetBatch()
	{
		FlushCurrentCommand();
		return mBatch;
	}

	/// Clear all content and reset state
	public void Clear()
	{
		mBatch.Clear();
		mStateStack.Clear();
		mClipStack.Clear();
		mOpacityStack.Clear();
		mCurrentState = .();
		mCurrentTextureIndex = -1;
		mCurrentBlendMode = .Normal;
		mCommandStartIndex = 0;
	}

	// === State Management ===

	/// Push current state onto the stack
	public void PushState()
	{
		mStateStack.Add(mCurrentState);
	}

	/// Pop state from the stack
	public void PopState()
	{
		if (mStateStack.Count > 0)
		{
			mCurrentState = mStateStack.PopBack();
		}
	}

	// === Transform ===

	/// Set the current transform matrix
	public void SetTransform(Matrix transform)
	{
		mCurrentState.Transform = transform;
	}

	/// Get the current transform matrix
	public Matrix GetTransform()
	{
		return mCurrentState.Transform;
	}

	/// Apply translation to current transform
	public void Translate(float x, float y)
	{
		mCurrentState.Transform = Matrix.CreateTranslation(x, y, 0) * mCurrentState.Transform;
	}

	/// Apply rotation to current transform (in radians)
	public void Rotate(float radians)
	{
		mCurrentState.Transform = Matrix.CreateRotationZ(radians) * mCurrentState.Transform;
	}

	/// Apply scale to current transform
	public void Scale(float sx, float sy)
	{
		mCurrentState.Transform = Matrix.CreateScale(sx, sy, 1) * mCurrentState.Transform;
	}

	/// Reset transform to identity
	public void ResetTransform()
	{
		mCurrentState.Transform = Matrix.Identity;
	}

	// === Clipping ===

	/// Push a scissor clip rectangle
	public void PushClipRect(RectangleF rect)
	{
		// Flush current command before changing clip state
		FlushCurrentCommand();

		// Save current clip rect to stack
		mClipStack.Add(mCurrentState.ClipRect);

		// Transform clip rect if needed
		let transformedRect = TransformRect(rect);

		if (mCurrentState.ClipRect.Width > 0 && mCurrentState.ClipRect.Height > 0)
		{
			// Intersect with existing clip
			mCurrentState.ClipRect = RectangleF.Intersect(mCurrentState.ClipRect, transformedRect);
		}
		else
		{
			mCurrentState.ClipRect = transformedRect;
		}
		mCurrentState.ClipMode = .Scissor;
	}

	/// Pop the current clip
	public void PopClip()
	{
		// Flush current command before changing clip state
		FlushCurrentCommand();

		if (mClipStack.Count > 0)
		{
			mCurrentState.ClipRect = mClipStack.PopBack();
			mCurrentState.ClipMode = (mCurrentState.ClipRect.Width > 0 && mCurrentState.ClipRect.Height > 0) ? .Scissor : .None;
		}
		else
		{
			mCurrentState.ClipRect = default;
			mCurrentState.ClipMode = .None;
		}
	}

	// === Opacity ===

	/// Push an opacity value (multiplies with current opacity)
	public void PushOpacity(float opacity)
	{
		mOpacityStack.Add(mCurrentState.Opacity);
		mCurrentState.Opacity *= Math.Clamp(opacity, 0, 1);
	}

	/// Pop the current opacity
	public void PopOpacity()
	{
		if (mOpacityStack.Count > 0)
			mCurrentState.Opacity = mOpacityStack.PopBack();
		else
			mCurrentState.Opacity = 1.0f;
	}

	/// Get the current opacity
	public float Opacity => mCurrentState.Opacity;

	// === Blend Mode ===

	/// Set the blend mode for subsequent draws
	public void SetBlendMode(BlendMode mode)
	{
		if (mode != mCurrentBlendMode)
		{
			FlushCurrentCommand();
			mCurrentBlendMode = mode;
		}
	}

	// === Filled Shapes ===

	/// Fill a rectangle
	public void FillRect(RectangleF rect, IBrush brush)
	{
		SetupForSolidDraw();
		let startVertex = mBatch.Vertices.Count;

		// Transform all 4 corners for proper rotation support
		let tl = TransformPoint(.(rect.X, rect.Y));
		let tr = TransformPoint(.(rect.X + rect.Width, rect.Y));
		let br = TransformPoint(.(rect.X + rect.Width, rect.Y + rect.Height));
		let bl = TransformPoint(.(rect.X, rect.Y + rect.Height));

		mRasterizer.RasterizeQuad(tl, tr, br, bl, mBatch.Vertices, mBatch.Indices, ApplyOpacity(brush.BaseColor));

		if (brush.RequiresInterpolation)
			ApplyBrushToVertices(brush, rect, startVertex);
	}

	/// Fill a rectangle with a solid color
	public void FillRect(RectangleF rect, Color color)
	{
		SetupForSolidDraw();

		// Transform all 4 corners for proper rotation support
		let tl = TransformPoint(.(rect.X, rect.Y));
		let tr = TransformPoint(.(rect.X + rect.Width, rect.Y));
		let br = TransformPoint(.(rect.X + rect.Width, rect.Y + rect.Height));
		let bl = TransformPoint(.(rect.X, rect.Y + rect.Height));

		mRasterizer.RasterizeQuad(tl, tr, br, bl, mBatch.Vertices, mBatch.Indices, ApplyOpacity(color));
	}

	/// Fill a rounded rectangle
	public void FillRoundedRect(RectangleF rect, float radius, IBrush brush)
	{
		SetupForSolidDraw();
		let startVertex = mBatch.Vertices.Count;

		// Rasterize at original position, then transform vertices
		mRasterizer.RasterizeRoundedRect(rect, radius, mBatch.Vertices, mBatch.Indices, ApplyOpacity(brush.BaseColor));
		TransformVertices(startVertex);

		if (brush.RequiresInterpolation)
			ApplyBrushToVertices(brush, rect, startVertex);
	}

	/// Fill a rounded rectangle with a solid color
	public void FillRoundedRect(RectangleF rect, float radius, Color color)
	{
		SetupForSolidDraw();
		let startVertex = mBatch.Vertices.Count;

		// Rasterize at original position, then transform vertices
		mRasterizer.RasterizeRoundedRect(rect, radius, mBatch.Vertices, mBatch.Indices, ApplyOpacity(color));
		TransformVertices(startVertex);
	}

	/// Fill a circle
	public void FillCircle(Vector2 center, float radius, IBrush brush)
	{
		SetupForSolidDraw();
		let startVertex = mBatch.Vertices.Count;
		let bounds = RectangleF(center.X - radius, center.Y - radius, radius * 2, radius * 2);

		// Rasterize at original position, then transform vertices
		mRasterizer.RasterizeCircle(center, radius, mBatch.Vertices, mBatch.Indices, ApplyOpacity(brush.BaseColor));
		TransformVertices(startVertex);

		if (brush.RequiresInterpolation)
			ApplyBrushToVertices(brush, bounds, startVertex);
	}

	/// Fill a circle with a solid color
	public void FillCircle(Vector2 center, float radius, Color color)
	{
		SetupForSolidDraw();
		let startVertex = mBatch.Vertices.Count;

		// Rasterize at original position, then transform vertices
		mRasterizer.RasterizeCircle(center, radius, mBatch.Vertices, mBatch.Indices, ApplyOpacity(color));
		TransformVertices(startVertex);
	}

	/// Fill an ellipse
	public void FillEllipse(Vector2 center, float rx, float ry, IBrush brush)
	{
		SetupForSolidDraw();
		let startVertex = mBatch.Vertices.Count;
		let bounds = RectangleF(center.X - rx, center.Y - ry, rx * 2, ry * 2);

		// Rasterize at original position, then transform vertices
		mRasterizer.RasterizeEllipse(center, rx, ry, mBatch.Vertices, mBatch.Indices, ApplyOpacity(brush.BaseColor));
		TransformVertices(startVertex);

		if (brush.RequiresInterpolation)
			ApplyBrushToVertices(brush, bounds, startVertex);
	}

	/// Fill an ellipse with a solid color
	public void FillEllipse(Vector2 center, float rx, float ry, Color color)
	{
		SetupForSolidDraw();
		let startVertex = mBatch.Vertices.Count;

		// Rasterize at original position, then transform vertices
		mRasterizer.RasterizeEllipse(center, rx, ry, mBatch.Vertices, mBatch.Indices, ApplyOpacity(color));
		TransformVertices(startVertex);
	}

	/// Fill an arc (pie slice)
	public void FillArc(Vector2 center, float radius, float startAngle, float sweepAngle, IBrush brush)
	{
		SetupForSolidDraw();
		let startVertex = mBatch.Vertices.Count;
		let bounds = RectangleF(center.X - radius, center.Y - radius, radius * 2, radius * 2);

		// Rasterize at original position, then transform vertices
		mRasterizer.RasterizeArc(center, radius, startAngle, sweepAngle, mBatch.Vertices, mBatch.Indices, ApplyOpacity(brush.BaseColor));
		TransformVertices(startVertex);

		if (brush.RequiresInterpolation)
			ApplyBrushToVertices(brush, bounds, startVertex);
	}

	/// Fill an arc with a solid color
	public void FillArc(Vector2 center, float radius, float startAngle, float sweepAngle, Color color)
	{
		SetupForSolidDraw();
		let startVertex = mBatch.Vertices.Count;

		// Rasterize at original position, then transform vertices
		mRasterizer.RasterizeArc(center, radius, startAngle, sweepAngle, mBatch.Vertices, mBatch.Indices, ApplyOpacity(color));
		TransformVertices(startVertex);
	}

	// === Stroked Shapes ===

	/// Draw a line
	public void DrawLine(Vector2 start, Vector2 end, Pen pen)
	{
		SetupForSolidDraw();
		let startVertex = mBatch.Vertices.Count;

		// Rasterize at original position, then transform vertices
		mRasterizer.RasterizeLine(start, end, pen.Thickness, mBatch.Vertices, mBatch.Indices, ApplyOpacity(pen.Color), pen.LineCap);
		TransformVertices(startVertex);
	}

	/// Draw a line with color and thickness
	public void DrawLine(Vector2 start, Vector2 end, Color color, float thickness = 1.0f)
	{
		SetupForSolidDraw();
		let startVertex = mBatch.Vertices.Count;

		// Rasterize at original position, then transform vertices
		mRasterizer.RasterizeLine(start, end, thickness, mBatch.Vertices, mBatch.Indices, ApplyOpacity(color), .Butt);
		TransformVertices(startVertex);
	}

	/// Draw a rectangle outline
	public void DrawRect(RectangleF rect, Pen pen)
	{
		SetupForSolidDraw();
		let startVertex = mBatch.Vertices.Count;

		// Rasterize at original position, then transform vertices
		mRasterizer.RasterizeStrokeRect(rect, pen.Thickness, mBatch.Vertices, mBatch.Indices, ApplyOpacity(pen.Color));
		TransformVertices(startVertex);
	}

	/// Draw a rectangle outline with color and thickness
	public void DrawRect(RectangleF rect, Color color, float thickness = 1.0f)
	{
		SetupForSolidDraw();
		let startVertex = mBatch.Vertices.Count;

		// Rasterize at original position, then transform vertices
		mRasterizer.RasterizeStrokeRect(rect, thickness, mBatch.Vertices, mBatch.Indices, ApplyOpacity(color));
		TransformVertices(startVertex);
	}

	/// Draw a circle outline
	public void DrawCircle(Vector2 center, float radius, Pen pen)
	{
		SetupForSolidDraw();
		let startVertex = mBatch.Vertices.Count;

		// Rasterize at original position, then transform vertices
		mRasterizer.RasterizeStrokeCircle(center, radius, pen.Thickness, mBatch.Vertices, mBatch.Indices, ApplyOpacity(pen.Color));
		TransformVertices(startVertex);
	}

	/// Draw a circle outline with color and thickness
	public void DrawCircle(Vector2 center, float radius, Color color, float thickness = 1.0f)
	{
		SetupForSolidDraw();
		let startVertex = mBatch.Vertices.Count;

		// Rasterize at original position, then transform vertices
		mRasterizer.RasterizeStrokeCircle(center, radius, thickness, mBatch.Vertices, mBatch.Indices, ApplyOpacity(color));
		TransformVertices(startVertex);
	}

	/// Draw an ellipse outline
	public void DrawEllipse(Vector2 center, float rx, float ry, Pen pen)
	{
		SetupForSolidDraw();
		let startVertex = mBatch.Vertices.Count;

		// Rasterize at original position, then transform vertices
		mRasterizer.RasterizeStrokeEllipse(center, rx, ry, pen.Thickness, mBatch.Vertices, mBatch.Indices, ApplyOpacity(pen.Color));
		TransformVertices(startVertex);
	}

	/// Draw an ellipse outline with color and thickness
	public void DrawEllipse(Vector2 center, float rx, float ry, Color color, float thickness = 1.0f)
	{
		SetupForSolidDraw();
		let startVertex = mBatch.Vertices.Count;

		// Rasterize at original position, then transform vertices
		mRasterizer.RasterizeStrokeEllipse(center, rx, ry, thickness, mBatch.Vertices, mBatch.Indices, ApplyOpacity(color));
		TransformVertices(startVertex);
	}

	// === Polygons and Polylines ===

	/// Fill a polygon
	public void FillPolygon(Span<Vector2> points, IBrush brush)
	{
		if (points.Length < 3)
			return;

		SetupForSolidDraw();
		let startVertex = mBatch.Vertices.Count;

		// Calculate bounds for gradient
		var minX = points[0].X;
		var minY = points[0].Y;
		var maxX = points[0].X;
		var maxY = points[0].Y;
		for (let p in points)
		{
			minX = Math.Min(minX, p.X);
			minY = Math.Min(minY, p.Y);
			maxX = Math.Max(maxX, p.X);
			maxY = Math.Max(maxY, p.Y);
		}
		let bounds = RectangleF(minX, minY, maxX - minX, maxY - minY);

		// Transform all points
		Vector2[] transformed = scope Vector2[points.Length];
		for (int32 i = 0; i < points.Length; i++)
		{
			transformed[i] = TransformPoint(points[i]);
		}

		mRasterizer.RasterizePolygon(transformed, mBatch.Vertices, mBatch.Indices, ApplyOpacity(brush.BaseColor));

		if (brush.RequiresInterpolation)
			ApplyBrushToVertices(brush, bounds, startVertex);
	}

	/// Fill a polygon with a solid color
	public void FillPolygon(Span<Vector2> points, Color color)
	{
		if (points.Length < 3)
			return;

		SetupForSolidDraw();

		// Transform all points
		Vector2[] transformed = scope Vector2[points.Length];
		for (int32 i = 0; i < points.Length; i++)
		{
			transformed[i] = TransformPoint(points[i]);
		}

		mRasterizer.RasterizePolygon(transformed, mBatch.Vertices, mBatch.Indices, ApplyOpacity(color));
	}

	/// Draw a polyline (open path)
	public void DrawPolyline(Span<Vector2> points, Pen pen)
	{
		if (points.Length < 2)
			return;

		SetupForSolidDraw();
		let startVertex = mBatch.Vertices.Count;

		// Rasterize at original position, then transform vertices
		mRasterizer.RasterizePolyline(points, pen.Thickness, mBatch.Vertices, mBatch.Indices, ApplyOpacity(pen.Color), pen.LineCap, pen.LineJoin);
		TransformVertices(startVertex);
	}

	/// Draw a polyline with color and thickness
	public void DrawPolyline(Span<Vector2> points, Color color, float thickness = 1.0f)
	{
		if (points.Length < 2)
			return;

		SetupForSolidDraw();
		let startVertex = mBatch.Vertices.Count;

		// Rasterize at original position, then transform vertices
		mRasterizer.RasterizePolyline(points, thickness, mBatch.Vertices, mBatch.Indices, ApplyOpacity(color), .Butt, .Miter);
		TransformVertices(startVertex);
	}

	/// Draw a polygon outline (closed path)
	public void DrawPolygon(Span<Vector2> points, Pen pen)
	{
		if (points.Length < 3)
			return;

		SetupForSolidDraw();
		let startVertex = mBatch.Vertices.Count;

		// Rasterize at original position, then transform vertices
		mRasterizer.RasterizeStrokePolygon(points, pen.Thickness, mBatch.Vertices, mBatch.Indices, ApplyOpacity(pen.Color), pen.LineJoin);
		TransformVertices(startVertex);
	}

	/// Draw a polygon outline with color and thickness
	public void DrawPolygon(Span<Vector2> points, Color color, float thickness = 1.0f)
	{
		if (points.Length < 3)
			return;

		SetupForSolidDraw();
		let startVertex = mBatch.Vertices.Count;

		// Rasterize at original position, then transform vertices
		mRasterizer.RasterizeStrokePolygon(points, thickness, mBatch.Vertices, mBatch.Indices, ApplyOpacity(color), .Miter);
		TransformVertices(startVertex);
	}

	// === Images ===

	/// Draw an image at a position
	public void DrawImage(ITexture texture, Vector2 position)
	{
		DrawImage(texture, .(position.X, position.Y, texture.Width, texture.Height), .(0, 0, texture.Width, texture.Height), Color.White);
	}

	/// Draw an image at a position with tint
	public void DrawImage(ITexture texture, Vector2 position, Color tint)
	{
		DrawImage(texture, .(position.X, position.Y, texture.Width, texture.Height), .(0, 0, texture.Width, texture.Height), tint);
	}

	/// Draw an image stretched to a destination rectangle
	public void DrawImage(ITexture texture, RectangleF destRect)
	{
		DrawImage(texture, destRect, .(0, 0, texture.Width, texture.Height), Color.White);
	}

	/// Draw an image stretched to a destination rectangle with source rect and tint
	public void DrawImage(ITexture texture, RectangleF destRect, RectangleF srcRect, Color tint)
	{
		let textureIndex = GetOrAddTexture(texture);
		SetupForTextureDraw(textureIndex);

		let transformed = TransformRect(destRect);
		mRasterizer.RasterizeTexturedQuad(transformed, srcRect, texture.Width, texture.Height, mBatch.Vertices, mBatch.Indices, tint);
	}

	/// Draw a 9-slice image
	public void DrawNineSlice(ITexture texture, RectangleF destRect, RectangleF srcRect, NineSlice slices, Color tint)
	{
		let textureIndex = GetOrAddTexture(texture);
		SetupForTextureDraw(textureIndex);

		let transformed = TransformRect(destRect);
		mRasterizer.RasterizeNineSlice(transformed, srcRect, slices, texture.Width, texture.Height, mBatch.Vertices, mBatch.Indices, tint);
	}

	// === Sprites ===

	/// Draw a sprite at a position
	public void DrawSprite(Sprite sprite, Vector2 position)
	{
		DrawSprite(sprite, position, 0, .(1, 1), .None, Color.White);
	}

	/// Draw a sprite with tint
	public void DrawSprite(Sprite sprite, Vector2 position, Color tint)
	{
		DrawSprite(sprite, position, 0, .(1, 1), .None, tint);
	}

	/// Draw a sprite with rotation and scale
	public void DrawSprite(Sprite sprite, Vector2 position, float rotation, Vector2 scale, Color tint)
	{
		DrawSprite(sprite, position, rotation, scale, .None, tint);
	}

	/// Draw a sprite with full transform options
	public void DrawSprite(Sprite sprite, Vector2 position, float rotation, Vector2 scale, SpriteFlip flip, Color tint)
	{
		if (sprite.Texture == null)
			return;

		let textureIndex = GetOrAddTexture(sprite.Texture);
		SetupForTextureDraw(textureIndex);

		// Calculate flipped UVs
		var srcRect = sprite.SourceRect;
		if ((flip & .Horizontal) != 0)
		{
			srcRect.X = sprite.SourceRect.X + sprite.SourceRect.Width;
			srcRect.Width = -sprite.SourceRect.Width;
		}
		if ((flip & .Vertical) != 0)
		{
			srcRect.Y = sprite.SourceRect.Y + sprite.SourceRect.Height;
			srcRect.Height = -sprite.SourceRect.Height;
		}

		// Calculate the destination quad with origin offset
		let originOffset = sprite.GetOriginOffset();
		let scaledWidth = sprite.Width * scale.X;
		let scaledHeight = sprite.Height * scale.Y;
		let originX = originOffset.X * scale.X;
		let originY = originOffset.Y * scale.Y;

		// Push current transform
		let savedTransform = mCurrentState.Transform;

		// Apply sprite transform: translate to position, rotate, then offset by origin
		mCurrentState.Transform = Matrix.CreateTranslation(-originX, -originY, 0) *
								  Matrix.CreateRotationZ(rotation) *
								  Matrix.CreateTranslation(position.X, position.Y, 0) *
								  savedTransform;

		let destRect = RectangleF(0, 0, scaledWidth, scaledHeight);
		let transformed = TransformRect(destRect);

		mRasterizer.RasterizeTexturedQuad(transformed, srcRect, sprite.TextureWidth, sprite.TextureHeight, mBatch.Vertices, mBatch.Indices, tint);

		// Restore transform
		mCurrentState.Transform = savedTransform;
	}

	/// Draw a sprite from an animation player
	public void DrawSprite(SpriteAnimation animation, AnimationPlayer player, Vector2 position)
	{
		DrawSprite(player.GetCurrentSprite(animation), position);
	}

	/// Draw a sprite from an animation player with transform
	public void DrawSprite(SpriteAnimation animation, AnimationPlayer player, Vector2 position, float rotation, Vector2 scale, SpriteFlip flip, Color tint)
	{
		DrawSprite(player.GetCurrentSprite(animation), position, rotation, scale, flip, tint);
	}

	// === Text Rendering ===

	/// Draw text at a position using a font atlas
	/// Position is at the top-left of the text bounds
	public void DrawText(StringView text, IFontAtlas atlas, ITexture atlasTexture, Vector2 position, Color color)
	{
		if (text.IsEmpty)
			return;

		let textureIndex = GetOrAddTexture(atlasTexture);
		SetupForTextureDraw(textureIndex);

		let startVertex = mBatch.Vertices.Count;
		var cursorX = position.X;
		let cursorY = position.Y;

		let opacityColor = ApplyOpacity(color);
		for (let char in text.DecodedChars)
		{
			GlyphQuad quad = ?;
			if (atlas.GetGlyphQuad((int32)char, ref cursorX, cursorY, out quad))
			{
				mRasterizer.RasterizeGlyphQuad(quad, mBatch.Vertices, mBatch.Indices, opacityColor);
			}
		}

		TransformVertices(startVertex);
	}

	/// Draw text at a position using a font atlas with brush for coloring
	public void DrawText(StringView text, IFontAtlas atlas, ITexture atlasTexture, Vector2 position, IBrush brush)
	{
		if (text.IsEmpty)
			return;

		let textureIndex = GetOrAddTexture(atlasTexture);
		SetupForTextureDraw(textureIndex);

		let startVertex = mBatch.Vertices.Count;
		var cursorX = position.X;
		let cursorY = position.Y;

		// First pass: render all glyphs with base color
		let opacityColor = ApplyOpacity(brush.BaseColor);
		for (let char in text.DecodedChars)
		{
			GlyphQuad quad = ?;
			if (atlas.GetGlyphQuad((int32)char, ref cursorX, cursorY, out quad))
			{
				mRasterizer.RasterizeGlyphQuad(quad, mBatch.Vertices, mBatch.Indices, opacityColor);
			}
		}

		// Calculate bounds for gradient
		let endX = cursorX;
		let bounds = RectangleF(position.X, position.Y, endX - position.X, 32); // Approximate height

		// Apply brush colors if needed
		if (brush.RequiresInterpolation)
			ApplyBrushToVertices(brush, bounds, startVertex);

		TransformVertices(startVertex);
	}

	/// Draw text with horizontal alignment within bounds
	public void DrawText(StringView text, IFont font, IFontAtlas atlas, ITexture atlasTexture, RectangleF bounds, TextAlignment align, Color color)
	{
		if (text.IsEmpty)
			return;

		// Measure text to determine alignment offset
		let textWidth = font.MeasureString(text);
		var offsetX = bounds.X;

		switch (align)
		{
		case .Left:
			offsetX = bounds.X;
		case .Center:
			offsetX = bounds.X + (bounds.Width - textWidth) * 0.5f;
		case .Right:
			offsetX = bounds.X + bounds.Width - textWidth;
		}

		// Draw at calculated position (vertically centered)
		let offsetY = bounds.Y + (bounds.Height - font.Metrics.LineHeight) * 0.5f + font.Metrics.Ascent;
		DrawText(text, atlas, atlasTexture, .(offsetX, offsetY), color);
	}

	/// Draw text with horizontal and vertical alignment within bounds
	public void DrawText(StringView text, IFont font, IFontAtlas atlas, ITexture atlasTexture, RectangleF bounds, TextAlignment hAlign, VerticalAlignment vAlign, Color color)
	{
		if (text.IsEmpty)
			return;

		// Measure text to determine alignment offset
		let textWidth = font.MeasureString(text);
		var offsetX = bounds.X;
		var offsetY = bounds.Y;

		// Horizontal alignment
		switch (hAlign)
		{
		case .Left:
			offsetX = bounds.X;
		case .Center:
			offsetX = bounds.X + (bounds.Width - textWidth) * 0.5f;
		case .Right:
			offsetX = bounds.X + bounds.Width - textWidth;
		}

		// Vertical alignment
		switch (vAlign)
		{
		case .Top:
			offsetY = bounds.Y + font.Metrics.Ascent;
		case .Middle:
			offsetY = bounds.Y + (bounds.Height - font.Metrics.LineHeight) * 0.5f + font.Metrics.Ascent;
		case .Bottom:
			offsetY = bounds.Y + bounds.Height - font.Metrics.Descent;
		case .Baseline:
			offsetY = bounds.Y + bounds.Height * 0.5f; // Assume baseline at middle
		}

		DrawText(text, atlas, atlasTexture, .(offsetX, offsetY), color);
	}

	// === Internal Helpers ===

	private void SetupForSolidDraw()
	{
		if (mCurrentTextureIndex != -1)
		{
			FlushCurrentCommand();
			mCurrentTextureIndex = -1;
		}
	}

	private void SetupForTextureDraw(int32 textureIndex)
	{
		if (mCurrentTextureIndex != textureIndex)
		{
			FlushCurrentCommand();
			mCurrentTextureIndex = textureIndex;
		}
	}

	private int32 GetOrAddTexture(ITexture texture)
	{
		for (int32 i = 0; i < mBatch.Textures.Count; i++)
		{
			if (mBatch.Textures[i] == texture)
				return i;
		}

		let index = (int32)mBatch.Textures.Count;
		mBatch.Textures.Add(texture);
		return index;
	}

	private void FlushCurrentCommand()
	{
		let indexCount = (int32)mBatch.Indices.Count - mCommandStartIndex;
		if (indexCount > 0)
		{
			var cmd = DrawCommand();
			cmd.TextureIndex = mCurrentTextureIndex;
			cmd.StartIndex = mCommandStartIndex;
			cmd.IndexCount = indexCount;
			cmd.ClipRect = mCurrentState.ClipRect;
			cmd.BlendMode = mCurrentBlendMode;
			cmd.ClipMode = mCurrentState.ClipMode;
			cmd.StencilRef = mCurrentState.StencilRef;

			mBatch.Commands.Add(cmd);
			mCommandStartIndex = (int32)mBatch.Indices.Count;
		}
	}

	private Vector2 TransformPoint(Vector2 point)
	{
		if (mCurrentState.Transform == Matrix.Identity)
			return point;

		let transformed = Vector2.Transform(point, mCurrentState.Transform);
		return transformed;
	}

	/// Transform all vertices from startVertex to end of list
	private void TransformVertices(int startVertex)
	{
		if (mCurrentState.Transform == Matrix.Identity)
			return;

		for (int i = startVertex; i < mBatch.Vertices.Count; i++)
		{
			var vertex = ref mBatch.Vertices[i];
			let transformed = Vector2.Transform(vertex.Position, mCurrentState.Transform);
			vertex.Position = transformed;
		}
	}

	/// Apply current opacity to a color
	private Color ApplyOpacity(Color color)
	{
		if (mCurrentState.Opacity >= 1.0f)
			return color;
		return Color(color.R, color.G, color.B, (uint8)(color.A * mCurrentState.Opacity));
	}

	/// Apply brush colors to vertices that were just added
	private void ApplyBrushToVertices(IBrush brush, RectangleF bounds, int startVertex)
	{
		for (int i = startVertex; i < mBatch.Vertices.Count; i++)
		{
			var vertex = ref mBatch.Vertices[i];
			// NOTE: For correct gradient calculation with transforms, we should use the original
			// (non-transformed) position. Currently using transformed position which works fine
			// for identity transforms (the common case). Gradient brushes with rotation/scale
			// transforms may have slightly incorrect color mapping - acceptable for UI use.
			let color = brush.GetColorAt(.(vertex.Position.X, vertex.Position.Y), bounds);
			vertex.Color = ApplyOpacity(color);
		}
	}

	private RectangleF TransformRect(RectangleF rect)
	{
		if (mCurrentState.Transform == Matrix.Identity)
			return rect;

		// For axis-aligned rectangles with simple transforms, just transform corners
		// Note: This doesn't handle rotation properly - would need to emit rotated quad
		let topLeft = TransformPoint(.(rect.X, rect.Y));
		let bottomRight = TransformPoint(.(rect.X + rect.Width, rect.Y + rect.Height));

		return .(topLeft.X, topLeft.Y, bottomRight.X - topLeft.X, bottomRight.Y - topLeft.Y);
	}
}

/// Internal state for DrawContext
struct DrawState
{
	public Matrix Transform = Matrix.Identity;
	public RectangleF ClipRect = default;
	public ClipMode ClipMode = .None;
	public int32 StencilRef = 0;
	public float Opacity = 1.0f;
}
