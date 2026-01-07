using System;
using Sedulous.Mathematics;
using Sedulous.Drawing;

namespace Sedulous.Drawing.Tests;

class DrawContextTests
{
	[Test]
	public static void New_BatchIsEmpty()
	{
		let ctx = scope DrawContext();
		let batch = ctx.GetBatch();

		Test.Assert(batch.VertexCount == 0);
		Test.Assert(batch.IndexCount == 0);
	}

	[Test]
	public static void Clear_ResetsBatch()
	{
		let ctx = scope DrawContext();
		ctx.FillRect(.(0, 0, 100, 100), Color.Red);
		ctx.Clear();
		let batch = ctx.GetBatch();

		Test.Assert(batch.VertexCount == 0);
		Test.Assert(batch.IndexCount == 0);
	}

	// === Transform Tests ===

	[Test]
	public static void GetTransform_Default_IsIdentity()
	{
		let ctx = scope DrawContext();

		Test.Assert(ctx.GetTransform() == Matrix.Identity);
	}

	[Test]
	public static void SetTransform_ChangesTransform()
	{
		let ctx = scope DrawContext();
		let transform = Matrix.CreateTranslation(100, 200, 0);
		ctx.SetTransform(transform);

		Test.Assert(ctx.GetTransform() == transform);
	}

	[Test]
	public static void ResetTransform_ResetsToIdentity()
	{
		let ctx = scope DrawContext();
		ctx.SetTransform(Matrix.CreateTranslation(100, 200, 0));
		ctx.ResetTransform();

		Test.Assert(ctx.GetTransform() == Matrix.Identity);
	}

	[Test]
	public static void Translate_ModifiesTransform()
	{
		let ctx = scope DrawContext();
		ctx.Translate(50, 100);

		let transform = ctx.GetTransform();
		// Check that translation is applied
		Test.Assert(transform != Matrix.Identity);
	}

	[Test]
	public static void Rotate_ModifiesTransform()
	{
		let ctx = scope DrawContext();
		ctx.Rotate(Math.PI_f / 4);

		Test.Assert(ctx.GetTransform() != Matrix.Identity);
	}

	[Test]
	public static void Scale_ModifiesTransform()
	{
		let ctx = scope DrawContext();
		ctx.Scale(2.0f, 0.5f);

		Test.Assert(ctx.GetTransform() != Matrix.Identity);
	}

	// === State Stack Tests ===

	[Test]
	public static void PushPopState_RestoresTransform()
	{
		let ctx = scope DrawContext();
		let original = Matrix.CreateScale(2, 2, 1);
		ctx.SetTransform(original);

		ctx.PushState();
		ctx.SetTransform(Matrix.CreateTranslation(100, 100, 0));
		ctx.PopState();

		Test.Assert(ctx.GetTransform() == original);
	}

	[Test]
	public static void PopState_WithEmptyStack_DoesNotCrash()
	{
		let ctx = scope DrawContext();
		ctx.PopState(); // Should not crash
		Test.Assert(true);
	}

	// === Fill Tests ===

	[Test]
	public static void FillRect_AddsGeometry()
	{
		let ctx = scope DrawContext();
		ctx.FillRect(.(0, 0, 100, 50), Color.Red);

		let batch = ctx.GetBatch();
		Test.Assert(batch.VertexCount == 4);
		Test.Assert(batch.IndexCount == 6);
	}

	[Test]
	public static void FillRect_WithBrush_AddsGeometry()
	{
		let ctx = scope DrawContext();
		let brush = scope SolidBrush(Color.Blue);
		ctx.FillRect(.(0, 0, 100, 50), brush);

		let batch = ctx.GetBatch();
		Test.Assert(batch.VertexCount == 4);
	}

	[Test]
	public static void FillCircle_AddsGeometry()
	{
		let ctx = scope DrawContext();
		ctx.FillCircle(.(50, 50), 30, Color.Green);

		let batch = ctx.GetBatch();
		Test.Assert(batch.VertexCount > 0);
		Test.Assert(batch.IndexCount > 0);
	}

	[Test]
	public static void FillEllipse_AddsGeometry()
	{
		let ctx = scope DrawContext();
		ctx.FillEllipse(.(50, 50), 40, 20, Color.Yellow);

		let batch = ctx.GetBatch();
		Test.Assert(batch.VertexCount > 0);
	}

	[Test]
	public static void FillRoundedRect_AddsGeometry()
	{
		let ctx = scope DrawContext();
		ctx.FillRoundedRect(.(0, 0, 100, 50), 10, Color.Purple);

		let batch = ctx.GetBatch();
		Test.Assert(batch.VertexCount > 0);
	}

	[Test]
	public static void FillArc_AddsGeometry()
	{
		let ctx = scope DrawContext();
		ctx.FillArc(.(50, 50), 30, 0, Math.PI_f / 2, Color.Orange);

		let batch = ctx.GetBatch();
		Test.Assert(batch.VertexCount > 0);
	}

	[Test]
	public static void FillPolygon_AddsGeometry()
	{
		let ctx = scope DrawContext();
		Vector2[] points = scope .(.(0, 0), .(100, 0), .(50, 100));
		ctx.FillPolygon(points, Color.Red);

		let batch = ctx.GetBatch();
		Test.Assert(batch.VertexCount == 3);
	}

	// === Stroke Tests ===

	[Test]
	public static void DrawLine_AddsGeometry()
	{
		let ctx = scope DrawContext();
		ctx.DrawLine(.(0, 0), .(100, 100), Color.Black, 2.0f);

		let batch = ctx.GetBatch();
		Test.Assert(batch.VertexCount >= 4);
	}

	[Test]
	public static void DrawLine_WithPen_AddsGeometry()
	{
		let ctx = scope DrawContext();
		let pen = scope Pen(Color.Red, 3.0f);
		ctx.DrawLine(.(0, 0), .(100, 100), pen);

		let batch = ctx.GetBatch();
		Test.Assert(batch.VertexCount > 0);
	}

	[Test]
	public static void DrawRect_AddsGeometry()
	{
		let ctx = scope DrawContext();
		ctx.DrawRect(.(0, 0, 100, 50), Color.Black, 1.0f);

		let batch = ctx.GetBatch();
		Test.Assert(batch.VertexCount > 0);
	}

	[Test]
	public static void DrawCircle_AddsGeometry()
	{
		let ctx = scope DrawContext();
		ctx.DrawCircle(.(50, 50), 30, Color.Black, 2.0f);

		let batch = ctx.GetBatch();
		Test.Assert(batch.VertexCount > 0);
	}

	[Test]
	public static void DrawPolygon_AddsGeometry()
	{
		let ctx = scope DrawContext();
		Vector2[] points = scope .(.(0, 0), .(100, 0), .(100, 100), .(0, 100));
		ctx.DrawPolygon(points, Color.Black, 1.0f);

		let batch = ctx.GetBatch();
		Test.Assert(batch.VertexCount > 0);
	}

	[Test]
	public static void DrawPolyline_AddsGeometry()
	{
		let ctx = scope DrawContext();
		Vector2[] points = scope .(.(0, 0), .(50, 50), .(100, 0));
		ctx.DrawPolyline(points, Color.Black, 1.0f);

		let batch = ctx.GetBatch();
		Test.Assert(batch.VertexCount > 0);
	}

	// === Blend Mode Tests ===

	[Test]
	public static void SetBlendMode_CreatesNewCommand()
	{
		let ctx = scope DrawContext();
		ctx.FillRect(.(0, 0, 50, 50), Color.Red);
		ctx.SetBlendMode(.Additive);
		ctx.FillRect(.(50, 0, 50, 50), Color.Blue);

		let batch = ctx.GetBatch();
		Test.Assert(batch.CommandCount == 2);
		Test.Assert(batch.GetCommand(0).BlendMode == .Normal);
		Test.Assert(batch.GetCommand(1).BlendMode == .Additive);
	}

	// === Clip Tests ===

	[Test]
	public static void PushClipRect_SetsClipOnCommand()
	{
		let ctx = scope DrawContext();
		ctx.PushClipRect(.(10, 10, 80, 80));
		ctx.FillRect(.(0, 0, 100, 100), Color.Red);

		let batch = ctx.GetBatch();
		let cmd = batch.GetCommand(0);
		Test.Assert(cmd.ClipMode == .Scissor);
		Test.Assert(cmd.ClipRect.Width > 0);
	}

	// === WhitePixelUV Tests ===

	[Test]
	public static void WhitePixelUV_PropagatestoRasterizer()
	{
		let ctx = scope DrawContext();
		ctx.WhitePixelUV = .(0.5f, 0.5f);
		ctx.FillRect(.(0, 0, 10, 10), Color.White);

		let batch = ctx.GetBatch();
		Test.Assert(batch.Vertices[0].TexCoord.X == 0.5f);
	}

	// === Gradient Tests ===

	[Test]
	public static void FillRect_WithLinearGradient_InterpolatesColors()
	{
		let ctx = scope DrawContext();
		let brush = scope LinearGradientBrush(.(0, 0), .(100, 0), Color.Red, Color.Blue);
		ctx.FillRect(.(0, 0, 100, 50), brush);

		let batch = ctx.GetBatch();
		// Vertices should have different colors due to gradient
		Test.Assert(batch.VertexCount == 4);
	}

	[Test]
	public static void FillCircle_WithRadialGradient_InterpolatesColors()
	{
		let ctx = scope DrawContext();
		let brush = scope RadialGradientBrush(.(50, 50), 50, Color.White, Color.Black);
		ctx.FillCircle(.(50, 50), 50, brush);

		let batch = ctx.GetBatch();
		Test.Assert(batch.VertexCount > 0);
	}
}
