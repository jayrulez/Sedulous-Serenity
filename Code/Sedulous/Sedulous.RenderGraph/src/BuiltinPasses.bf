using System;
using Sedulous.RHI;
using Sedulous.Foundation.Mathematics;

namespace Sedulous.RenderGraph;

/// Helper methods for common render graph pass patterns.
public static class BuiltinPasses
{
	/// Adds a pass that clears a render target to a solid color.
	///
	/// Returns the written resource handle (new version after the clear).
	public static ResourceHandle AddClearPass(RenderGraph graph, StringView name,
		ResourceHandle target, Color clearColor)
	{
		ResourceHandle result = .Invalid;

		graph.AddRasterPass(name,
			new [&result, =target, =clearColor](builder) =>
			{
				result = builder.SetColorAttachment(0, target, .Clear, clearColor);
				builder.SideEffect();
			},
			new (encoder) =>
			{
				// Nothing to draw — the clear is performed by the load op
			}
		);

		return result;
	}

	/// Adds a pass that clears both a color target and a depth target.
	///
	/// Returns the written color resource handle.
	public static ResourceHandle AddClearPass(RenderGraph graph, StringView name,
		ResourceHandle colorTarget, Color clearColor,
		ResourceHandle depthTarget, float clearDepth = 1.0f)
	{
		ResourceHandle colorResult = .Invalid;

		graph.AddRasterPass(name,
			new [&colorResult, =colorTarget, =clearColor, =depthTarget, =clearDepth](builder) =>
			{
				colorResult = builder.SetColorAttachment(0, colorTarget, .Clear, clearColor);
				builder.SetDepthStencilAttachment(depthTarget, .Clear, clearDepth);
				builder.SideEffect();
			},
			new (encoder) =>
			{
				// Clear only — no draw calls
			}
		);

		return colorResult;
	}

	/// Adds a fullscreen triangle pass with a given pipeline.
	///
	/// The pass reads `input` as a texture and writes to `output` as a color attachment.
	/// The user provides a pre-created pipeline and bind group for the fullscreen shader.
	///
	/// Returns the written output handle.
	public static ResourceHandle AddFullscreenPass(RenderGraph graph, StringView name,
		ResourceHandle input, ResourceHandle output,
		IRenderPipeline pipeline, IBindGroup bindGroup)
	{
		ResourceHandle result = .Invalid;

		graph.AddRasterPass(name,
			new [&result, =input, =output](builder) =>
			{
				builder.Read(input);
				result = builder.SetColorAttachment(0, output, .DontCare);
				builder.SideEffect();
			},
			new (encoder) =>
			{
				encoder.SetPipeline(pipeline);
				encoder.SetBindGroup(0, bindGroup);
				encoder.Draw(3, 1, 0, 0); // Fullscreen triangle
			}
		);

		return result;
	}

	/// Adds a blit (copy) pass that copies one texture to another.
	///
	/// This is a transfer pass that uses the command encoder's Blit operation.
	/// Both source and destination textures must support the appropriate copy usage.
	public static void AddBlitPass(RenderGraph graph, StringView name,
		ResourceHandle source, ResourceHandle destination)
	{
		graph.AddTransferPass(name,
			new (builder) =>
			{
				builder.Read(source);
				builder.Write(destination);
				builder.SideEffect();
			},
			new (encoder) =>
			{
				let srcTexture = graph.GetTexture(source);
				let dstTexture = graph.GetTexture(destination);
				if (srcTexture != null && dstTexture != null)
					encoder.Blit(srcTexture, dstTexture);
			}
		);
	}
}
