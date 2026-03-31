namespace Sedulous.RenderGraph;

using System;
using System.Collections;
using Sedulous.RHI;

/// Debug visualization and profiling utilities for the render graph.
static class GraphDebug
{
	/// Exports the render graph as a DOT file for Graphviz visualization.
	/// Shows passes colored by queue type, data dependencies, resource lifetimes,
	/// cross-queue sync points, and culled passes (greyed out).
	public static void ExportDOT(RenderGraph graph, String outDot)
	{
		outDot.Append("digraph RenderGraph {\n");
		outDot.Append("  rankdir=LR;\n");
		outDot.Append("  node [shape=box, style=\"filled,rounded\", fontname=\"Consolas\"];\n");
		outDot.Append("  edge [fontname=\"Consolas\", fontsize=9];\n\n");

		// Legend
		outDot.Append("  subgraph cluster_legend {\n");
		outDot.Append("    label=\"Queue Types\";\n");
		outDot.Append("    style=dashed;\n");
		outDot.Append("    fontname=\"Consolas\";\n");
		outDot.Append("    legend_gfx [label=\"Graphics\", fillcolor=\"#a8d8ea\"];\n");
		outDot.Append("    legend_compute [label=\"Compute\", fillcolor=\"#ffd3b6\"];\n");
		outDot.Append("    legend_transfer [label=\"Transfer\", fillcolor=\"#d5f5e3\"];\n");
		outDot.Append("    legend_culled [label=\"Culled\", fillcolor=\"#cccccc\"];\n");
		outDot.Append("  }\n\n");

		// Pass nodes
		for (int i = 0; i < graph.PassCount; i++)
		{
			let pass = graph.GetPass(i);
			let color = pass.IsCulled ? "#cccccc" : GetQueueColor(pass.QueueType);
			let style = pass.IsCulled ? "filled,rounded,dashed" : "filled,rounded";
			let queueLabel = GetQueueLabel(pass.QueueType);

			outDot.AppendF(scope $"  pass_{i} [label=\"{pass.Name}\\n[{queueLabel}]\", fillcolor=\"{color}\", style=\"{style}\"];\n");
		}

		outDot.Append("\n");

		// Resource nodes (as ellipses)
		let resources = scope HashSet<uint32>();
		for (int i = 0; i < graph.PassCount; i++)
		{
			let pass = graph.GetPass(i);
			for (let access in pass.Accesses)
			{
				if (!resources.Contains(access.Resource.Index))
				{
					resources.Add(access.Resource.Index);
					let resName = GetResourceName(graph, access.Resource.Index);
					let resType = IsTextureResource(graph, access.Resource.Index) ? "tex" : "buf";
					outDot.AppendF(scope $"  res_{access.Resource.Index} [shape=ellipse, style=filled, fillcolor=\"#ffffcc\", label=\"{resName}\\n({resType})\"];\n");
				}
			}
		}

		outDot.Append("\n");

		// Edges: pass → resource (writes) and resource → pass (reads)
		for (int i = 0; i < graph.PassCount; i++)
		{
			let pass = graph.GetPass(i);
			for (let access in pass.Accesses)
			{
				if (access.IsWrite)
				{
					let stateLabel = GetStateLabel(access.ToResourceState());
					outDot.AppendF(scope $"  pass_{i} -> res_{access.Resource.Index} [label=\"{stateLabel}\", color=\"#cc4444\"];\n");
				}
				else
				{
					let stateLabel = GetStateLabel(access.ToResourceState());
					outDot.AppendF(scope $"  res_{access.Resource.Index} -> pass_{i} [label=\"{stateLabel}\", color=\"#4444cc\"];\n");
				}
			}
		}

		// Cross-queue sync edges
		if (graph.SyncPoints.Count > 0)
		{
			outDot.Append("\n  // Cross-queue synchronization\n");
			for (let sp in graph.SyncPoints)
			{
				if (sp.SrcPassIndex < graph.ScheduledPassCount && sp.DstPassIndex < graph.ScheduledPassCount)
				{
					let srcPass = graph.GetScheduledPass(sp.SrcPassIndex);
					let dstPass = graph.GetScheduledPass(sp.DstPassIndex);
					outDot.AppendF(scope $"  pass_{srcPass.Index} -> pass_{dstPass.Index} [style=dashed, color=\"#ff0000\", penwidth=2, label=\"fence={sp.FenceValue}\"];\n");
				}
			}
		}

		outDot.Append("}\n");
	}

	/// Exports a resource lifetime diagram showing which passes each resource is alive in.
	/// Each resource gets a row; passes form the columns.
	public static void ExportLifetimeDOT(RenderGraph graph, String outDot)
	{
		outDot.Append("digraph ResourceLifetimes {\n");
		outDot.Append("  rankdir=LR;\n");
		outDot.Append("  node [shape=record, fontname=\"Consolas\", style=filled];\n\n");

		let scheduledCount = graph.ScheduledPassCount;
		if (scheduledCount == 0)
		{
			outDot.Append("}\n");
			return;
		}

		// Timeline header row
		outDot.Append("  // Timeline\n");
		outDot.AppendF(scope $"  timeline [label=\"");
		for (int i = 0; i < scheduledCount; i++)
		{
			if (i > 0) outDot.Append("|");
			outDot.AppendF(scope $"<p{i}> {graph.GetScheduledPass(i).Name}");
		}
		outDot.Append("\", fillcolor=\"#e8e8e8\"];\n\n");

		// One row per resource with lifetime bars
		outDot.Append("  // Resource lifetimes\n");
		for (let resource in graph.Resources)
		{
			if (resource.FirstUsePass < 0 || resource.LastUsePass < 0)
				continue;

			let resLabel = scope String();
			for (int i = 0; i < scheduledCount; i++)
			{
				if (i > 0) resLabel.Append("|");
				resLabel.AppendF(scope $"<p{i}> ");
				if (i >= resource.FirstUsePass && i <= resource.LastUsePass)
					resLabel.Append("##"); // active
				else
					resLabel.Append("  "); // inactive
			}

			let fillColor = resource.IsTexture ? "#ffffcc" : "#ccffcc";
			let typeTag = resource.IsTexture ? "tex" : "buf";
			outDot.AppendF(scope $"  res_{resource.Index} [label=\"{resource.Name} ({typeTag})|{resLabel}\", fillcolor=\"{fillColor}\"];\n");
		}

		// Invisible edges to keep alignment
		outDot.Append("\n  // Alignment\n");
		bool first = true;
		for (let resource in graph.Resources)
		{
			if (resource.FirstUsePass < 0) continue;
			if (first)
			{
				outDot.AppendF(scope $"  timeline -> res_{resource.Index} [style=invis];\n");
				first = false;
			}
		}

		outDot.Append("}\n");
	}

	/// Exports a summary of the compiled graph as a plain-text report.
	public static void ExportSummary(RenderGraph graph, String outText)
	{
		outText.AppendF(scope $"=== Render Graph Summary ===\n");
		outText.AppendF(scope $"Total passes:     {graph.PassCount}\n");
		outText.AppendF(scope $"Scheduled passes: {graph.ScheduledPassCount}\n");
		outText.AppendF(scope $"Culled passes:    {graph.PassCount - graph.ScheduledPassCount}\n");
		outText.AppendF(scope $"Resources:        {graph.ResourceCount}\n");
		outText.AppendF(scope $"Sync points:      {graph.SyncPoints.Count}\n\n");

		// Scheduled pass list
		outText.Append("--- Scheduled Passes ---\n");
		for (int i = 0; i < graph.ScheduledPassCount; i++)
		{
			let pass = graph.GetScheduledPass(i);
			let queueLabel = GetQueueLabel(pass.QueueType);
			outText.AppendF(scope $"  [{i}] {pass.Name} ({queueLabel})");

			// Count barriers
			let barriers = graph.GetBarriersForPass(i);
			if (barriers.HasValue)
			{
				let texCount = barriers.Value.TextureBarriers != null ? barriers.Value.TextureBarriers.Count : 0;
				let bufCount = barriers.Value.BufferBarriers != null ? barriers.Value.BufferBarriers.Count : 0;
				let memCount = barriers.Value.MemoryBarriers != null ? barriers.Value.MemoryBarriers.Count : 0;
				outText.AppendF(scope $" — barriers: {texCount} tex, {bufCount} buf, {memCount} mem");
			}
			outText.Append("\n");
		}

		// Culled passes
		if (graph.PassCount > graph.ScheduledPassCount)
		{
			outText.Append("\n--- Culled Passes ---\n");
			for (int i = 0; i < graph.PassCount; i++)
			{
				let pass = graph.GetPass(i);
				if (pass.IsCulled)
					outText.AppendF(scope $"  {pass.Name}\n");
			}
		}

		// Sync points
		if (graph.SyncPoints.Count > 0)
		{
			outText.Append("\n--- Cross-Queue Sync ---\n");
			for (let sp in graph.SyncPoints)
			{
				let srcLabel = GetQueueLabel(sp.SrcQueue);
				let dstLabel = GetQueueLabel(sp.DstQueue);
				outText.AppendF(scope $"  {srcLabel} → {dstLabel} (fence={sp.FenceValue})\n");
			}
		}

		// Resource lifetimes
		outText.Append("\n--- Resource Lifetimes ---\n");
		for (let resource in graph.Resources)
		{
			if (resource.FirstUsePass < 0) continue;
			let typeTag = resource.IsTexture ? "tex" : "buf";
			let imported = resource.IsImported ? " [imported]" : "";
			outText.AppendF(scope $"  {resource.Name} ({typeTag}{imported}) — passes [{resource.FirstUsePass}..{resource.LastUsePass}]\n");
		}
	}

	// =========================================================================
	// Helpers
	// =========================================================================

	private static StringView GetQueueColor(QueueType queue)
	{
		switch (queue)
		{
		case .Graphics: return "#a8d8ea";
		case .Compute:  return "#ffd3b6";
		case .Transfer: return "#d5f5e3";
		}
	}

	private static StringView GetQueueLabel(QueueType queue)
	{
		switch (queue)
		{
		case .Graphics: return "GFX";
		case .Compute:  return "CMP";
		case .Transfer: return "XFR";
		}
	}

	private static StringView GetStateLabel(ResourceState state)
	{
		switch (state)
		{
		case .ShaderRead:        return "SRV";
		case .ShaderWrite:       return "UAV";
		case .RenderTarget:      return "RT";
		case .DepthStencilWrite: return "DSW";
		case .DepthStencilRead:  return "DSR";
		case .CopySrc:           return "CopySrc";
		case .CopyDst:           return "CopyDst";
		case .UniformBuffer:     return "UBO";
		case .Present:           return "Present";
		case .Undefined:         return "Undef";
		default:                 return "?";
		}
	}

	private static StringView GetResourceName(RenderGraph graph, uint32 resourceIndex)
	{
		for (let resource in graph.Resources)
		{
			if (resource.Index == resourceIndex)
				return resource.Name;
		}
		return "unknown";
	}

	private static bool IsTextureResource(RenderGraph graph, uint32 resourceIndex)
	{
		for (let resource in graph.Resources)
		{
			if (resource.Index == resourceIndex)
				return resource.IsTexture;
		}
		return true;
	}
}
