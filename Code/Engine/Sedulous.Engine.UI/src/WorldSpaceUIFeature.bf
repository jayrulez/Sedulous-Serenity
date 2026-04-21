namespace Sedulous.Engine.UI;

using System;
using System.Collections;
using Sedulous.Render;
using Sedulous.RenderGraph;
using Sedulous.RHI;
using Sedulous.Drawing;
using Sedulous.Core.Mathematics;
using Sedulous.Profiler;

/// Render feature that renders world-space UI panels to their textures.
/// Each dirty panel gets a render graph pass that clears and renders UI to its texture.
/// These passes run early (no dependencies) so sprites can sample the results later.
public class WorldSpaceUIFeature : RenderFeatureBase
{
	private List<WorldUIPanel> mPanels = new .() ~ delete _;

	public override StringView Name => "WorldSpaceUI";

	/// Adds a panel to be rendered each frame.
	public void AddPanel(WorldUIPanel panel)
	{
		if (!mPanels.Contains(panel))
			mPanels.Add(panel);
	}

	/// Removes a panel from rendering.
	public void RemovePanel(WorldUIPanel panel)
	{
		mPanels.Remove(panel);
	}

	/// Number of active panels.
	public int PanelCount => mPanels.Count;

	public override void AddPasses(RenderGraph graph, ViewContext view, RenderableList renderables)
	{
		using (SProfiler.Begin("WorldUI.AddPasses"))
		{
		if (mPanels.Count == 0)
			return;

		let frameIndex = Renderer.RenderFrameContext.FrameIndex;

		for (let panel in mPanels)
		{
			//if (!panel.IsDirty)
			//	continue;

			if (panel.Texture == null || panel.TextureView == null)
				continue;

			// Build UI geometry for this panel
			panel.PanelDrawContext.Clear();
			panel.GUIContext.SetViewportSize((float)panel.PixelWidth, (float)panel.PixelHeight);
			panel.GUIContext.Render(panel.PanelDrawContext);
			let batch = panel.PanelDrawContext.GetBatch();
			if (batch == null || batch.Commands.Count == 0)
			{
				panel.IsDirty = false;
				continue;
			}

			// Upload to panel's GPU buffers
			panel.Renderer.UpdateProjection(panel.PixelWidth, panel.PixelHeight, frameIndex);
			panel.Renderer.Prepare(batch, frameIndex);

			// Import panel's render texture into the graph.
			let handle = graph.ImportTarget(panel.ResourceName, panel.Texture, panel.TextureView);

			// Mark as readable after write — the barrier solver will transition to ShaderRead
			// after the UI pass writes to it, so sprites can sample it without declaring ReadTexture.
			graph.RequireReadableAfterWrite(handle);

			// Capture panel and frame index for the callback
			let capturedPanel = panel;
			let capturedFrameIndex = frameIndex;
			let capturedWidth = panel.PixelWidth;
			let capturedHeight = panel.PixelHeight;

			// Add a render pass that renders UI to this panel's texture
			graph.AddRenderPass(panel.PassName, scope (builder) => {
				builder.SetColorTarget(0, handle, .Clear, .Store, ClearColor(0, 0, 0, 0));
				builder.NeverCull();
				builder.SetExecute(new (encoder) => {
					encoder.SetViewport(0, 0, capturedWidth, capturedHeight, 0, 1);
					encoder.SetScissor(0, 0, capturedWidth, capturedHeight);
					capturedPanel.Renderer.Render(encoder, capturedWidth, capturedHeight, capturedFrameIndex);
				});
			});

			panel.IsDirty = false;
		}
		}
	}
}
