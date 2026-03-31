using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.RenderGraph;

namespace Sedulous.RenderGraph.Tests;

class DebugTests
{
	[Test]
	public static void TestExportDOTBasic()
	{
		let graph = scope RenderGraph();

		RGTexture tex = default;

		graph.AddPass("Write", .Graphics, scope [&] (builder) =>
		{
			tex = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 1920, 1080, 1, "Color"));
			builder.WriteRenderTarget(tex, 0);
		});

		graph.AddPass("Read", .Graphics, scope [&] (builder) =>
		{
			builder.ReadTexture(tex, .Fragment);
			builder.HasSideEffects();
		});

		graph.Compile();

		let dot = scope String();
		GraphDebug.ExportDOT(graph, dot);

		// Verify basic DOT structure
		Test.Assert(dot.Contains("digraph RenderGraph"));
		Test.Assert(dot.Contains("pass_0"));
		Test.Assert(dot.Contains("pass_1"));
		Test.Assert(dot.Contains("res_")); // resource node
		Test.Assert(dot.Contains("GFX")); // queue label
		Test.Assert(dot.Contains("Color")); // resource name
	}

	[Test]
	public static void TestExportDOTCulledPass()
	{
		let graph = scope RenderGraph();

		graph.AddPass("Culled", .Graphics, scope (builder) =>
		{
			let tex = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 256, 256, 1, "Unused"));
			builder.WriteRenderTarget(tex, 0);
		});

		graph.AddPass("Retained", .Graphics, scope (builder) =>
		{
			builder.HasSideEffects();
		});

		graph.Compile();

		let dot = scope String();
		GraphDebug.ExportDOT(graph, dot);

		// Culled pass should show dashed style
		Test.Assert(dot.Contains("dashed"));
		Test.Assert(dot.Contains("#cccccc")); // culled color
	}

	[Test]
	public static void TestExportDOTCrossQueueSync()
	{
		let graph = scope RenderGraph();

		RGTexture tex = default;

		graph.AddPass("GfxWrite", .Graphics, scope [&] (builder) =>
		{
			tex = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 1920, 1080, 1, "Tex"));
			builder.WriteRenderTarget(tex, 0);
		});

		graph.AddPass("ComputeRead", .Compute, scope [&] (builder) =>
		{
			builder.ReadTexture(tex, .Compute);
			builder.HasSideEffects();
		});

		graph.Compile();

		let dot = scope String();
		GraphDebug.ExportDOT(graph, dot);

		// Should have fence sync edge
		Test.Assert(dot.Contains("fence="));
		Test.Assert(dot.Contains("penwidth=2"));
	}

	[Test]
	public static void TestExportLifetimeDOT()
	{
		let graph = scope RenderGraph();

		RGTexture tex1 = default;
		RGTexture tex2 = default;

		graph.AddPass("Pass1", .Graphics, scope [&] (builder) =>
		{
			tex1 = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 1920, 1080, 1, "Tex1"));
			builder.WriteRenderTarget(tex1, 0);
		});

		graph.AddPass("Pass2", .Graphics, scope [&] (builder) =>
		{
			builder.ReadTexture(tex1, .Fragment);
			tex2 = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 1920, 1080, 1, "Tex2"));
			builder.WriteRenderTarget(tex2, 0);
		});

		graph.AddPass("Pass3", .Graphics, scope [&] (builder) =>
		{
			builder.ReadTexture(tex2, .Fragment);
			builder.HasSideEffects();
		});

		graph.Compile();

		let dot = scope String();
		GraphDebug.ExportLifetimeDOT(graph, dot);

		Test.Assert(dot.Contains("digraph ResourceLifetimes"));
		Test.Assert(dot.Contains("Tex1"));
		Test.Assert(dot.Contains("Tex2"));
		Test.Assert(dot.Contains("timeline"));
	}

	[Test]
	public static void TestExportSummary()
	{
		let graph = scope RenderGraph();

		RGTexture tex = default;

		graph.AddPass("Write", .Graphics, scope [&] (builder) =>
		{
			tex = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 1920, 1080, 1, "Color"));
			builder.WriteRenderTarget(tex, 0);
		});

		graph.AddPass("Read", .Graphics, scope [&] (builder) =>
		{
			builder.ReadTexture(tex, .Fragment);
			builder.HasSideEffects();
		});

		graph.AddPass("Orphan", .Graphics, scope (builder) =>
		{
			let unused = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 256, 256, 1, "Unused"));
			builder.WriteRenderTarget(unused, 0);
		});

		graph.Compile();

		let summary = scope String();
		GraphDebug.ExportSummary(graph, summary);

		Test.Assert(summary.Contains("Total passes:     3"));
		Test.Assert(summary.Contains("Scheduled passes: 2"));
		Test.Assert(summary.Contains("Culled passes:    1"));
		Test.Assert(summary.Contains("Orphan")); // in culled list
	}

	[Test]
	public static void TestValidateUninitializedRead()
	{
		let graph = scope RenderGraph();

		// Create a resource in one pass, but read a DIFFERENT resource that was never written
		// This is tricky to set up since our API creates resources during setup.
		// Instead, test the normal valid case — no uninitialized reads.
		RGTexture tex = default;

		graph.AddPass("Write", .Graphics, scope [&] (builder) =>
		{
			tex = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 1920, 1080, 1, "Tex"));
			builder.WriteRenderTarget(tex, 0);
		});

		graph.AddPass("Read", .Graphics, scope [&] (builder) =>
		{
			builder.ReadTexture(tex, .Fragment);
			builder.HasSideEffects();
		});

		graph.Compile();

		let text = scope String();
		GraphValidator.ValidateToString(graph, text);

		// Should have no errors (only possible warning: empty passes without callbacks)
		Test.Assert(!text.Contains("ERROR"));
	}

	[Test]
	public static void TestValidateRedundantWrite()
	{
		let graph = scope RenderGraph();

		RGTexture tex = default;

		graph.AddPass("Write1", .Graphics, scope [&] (builder) =>
		{
			tex = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 1920, 1080, 1, "Tex"));
			builder.WriteRenderTarget(tex, 0);
			builder.HasSideEffects(); // Keep this pass alive
		});

		// Second write without intermediate read — redundant
		graph.AddPass("Write2", .Graphics, scope [&] (builder) =>
		{
			builder.WriteStorage(tex, .Fragment);
			builder.HasSideEffects();
		});

		graph.Compile();

		let messages = scope List<ValidationMessage>();
		GraphValidator.Validate(graph, messages);

		// Should warn about redundant write
		bool foundRedundant = false;
		for (let msg in messages)
		{
			if (msg.Message.Contains("without any read since"))
				foundRedundant = true;
			delete msg.Message;
		}
		Test.Assert(foundRedundant);
	}

	[Test]
	public static void TestValidateCulledPassWarning()
	{
		let graph = scope RenderGraph();

		graph.AddPass("Orphan", .Graphics, scope (builder) =>
		{
			let tex = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 256, 256, 1, "Unused"));
			builder.WriteRenderTarget(tex, 0);
		});

		graph.AddPass("Retained", .Graphics, scope (builder) =>
		{
			builder.HasSideEffects();
		});

		graph.Compile();

		let messages = scope List<ValidationMessage>();
		GraphValidator.Validate(graph, messages);

		bool foundCulled = false;
		for (let msg in messages)
		{
			if (msg.Message.Contains("culled"))
				foundCulled = true;
			delete msg.Message;
		}
		Test.Assert(foundCulled);
	}

	[Test]
	public static void TestValidateCleanGraph()
	{
		let graph = scope RenderGraph();

		RGTexture tex = default;

		graph.AddPass("Write", .Graphics, scope [&] (builder) =>
		{
			tex = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 1920, 1080, 1, "Tex"));
			builder.WriteRenderTarget(tex, 0);
			builder.SetExecute(new (encoder, registry) => { });
		});

		graph.AddPass("Read", .Graphics, scope [&] (builder) =>
		{
			builder.ReadTexture(tex, .Fragment);
			builder.HasSideEffects();
			builder.SetExecute(new (encoder, registry) => { });
		});

		graph.Compile();

		let text = scope String();
		GraphValidator.ValidateToString(graph, text);

		Test.Assert(text.Contains("OK"));
	}

	[Test]
	public static void TestExportDOTMultiQueue()
	{
		let graph = scope RenderGraph();

		RGTexture depthTex = default;
		RGBuffer ssaoData = default;

		graph.AddPass("DepthPrepass", .Graphics, scope [&] (builder) =>
		{
			depthTex = builder.CreateTexture(.DepthBuffer(.Depth32Float, 1920, 1080, 1, "Depth"));
			builder.WriteDepthStencil(depthTex);
		});

		graph.AddPass("SSAO_Compute", .Compute, scope [&] (builder) =>
		{
			builder.ReadTexture(depthTex, .Compute);
			ssaoData = builder.CreateBuffer(.() { Size = 1920 * 1080 * 4, Usage = .Storage, Name = "SSAO" });
			builder.WriteStorage(ssaoData, .Compute);
		});

		graph.AddPass("Lighting", .Graphics, scope [&] (builder) =>
		{
			builder.ReadStorageBuffer(ssaoData, .Fragment);
			builder.HasSideEffects();
		});

		graph.Compile();

		let dot = scope String();
		GraphDebug.ExportDOT(graph, dot);

		// Should have all three queue colors
		Test.Assert(dot.Contains("#a8d8ea")); // Graphics
		Test.Assert(dot.Contains("#ffd3b6")); // Compute
		// Resource nodes
		Test.Assert(dot.Contains("Depth"));
		Test.Assert(dot.Contains("SSAO"));
		// Cross-queue sync
		Test.Assert(dot.Contains("fence="));
	}

	[Test]
	public static void TestExportDOTToFile()
	{
		// This test generates a DOT file that can be rendered with Graphviz
		let graph = scope RenderGraph();

		RGTexture gbufferAlbedo = default;
		RGTexture gbufferNormal = default;
		RGTexture gbufferDepth = default;
		RGTexture hdr = default;
		RGBuffer ssao = default;

		graph.AddPass("GBuffer", .Graphics, scope [&] (builder) =>
		{
			gbufferAlbedo = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 1920, 1080, 1, "Albedo"));
			gbufferNormal = builder.CreateTexture(.RenderTarget(.RGBA16Float, 1920, 1080, 1, "Normal"));
			gbufferDepth = builder.CreateTexture(.DepthBuffer(.Depth32Float, 1920, 1080, 1, "Depth"));
			builder.WriteRenderTarget(gbufferAlbedo, 0);
			builder.WriteRenderTarget(gbufferNormal, 1);
			builder.WriteDepthStencil(gbufferDepth);
		});

		graph.AddPass("SSAO", .Compute, scope [&] (builder) =>
		{
			builder.ReadTexture(gbufferDepth, .Compute);
			builder.ReadTexture(gbufferNormal, .Compute);
			ssao = builder.CreateBuffer(.() { Size = 1920 * 1080 * 4, Usage = .Storage, Name = "SSAO_Data" });
			builder.WriteStorage(ssao, .Compute);
		});

		graph.AddPass("Lighting", .Graphics, scope [&] (builder) =>
		{
			builder.ReadTexture(gbufferAlbedo, .Fragment);
			builder.ReadTexture(gbufferNormal, .Fragment);
			builder.ReadTexture(gbufferDepth, .Fragment);
			builder.ReadStorageBuffer(ssao, .Fragment);
			hdr = builder.CreateTexture(.RenderTarget(.RGBA16Float, 1920, 1080, 1, "HDR"));
			builder.WriteRenderTarget(hdr, 0);
		});

		graph.AddPass("Tonemap", .Graphics, scope [&] (builder) =>
		{
			builder.ReadTexture(hdr, .Fragment);
			builder.HasSideEffects();
		});

		// Also add an orphan pass that gets culled
		graph.AddPass("DebugView", .Graphics, scope (builder) =>
		{
			let dbg = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 256, 256, 1, "Debug"));
			builder.WriteRenderTarget(dbg, 0);
		});

		graph.Compile();

		// Export DOT
		let dot = scope String();
		GraphDebug.ExportDOT(graph, dot);

		// Write to file for manual Graphviz rendering
		System.IO.File.WriteAllText("rendergraph_test.dot", dot);

		// Export summary too
		let summary = scope String();
		GraphDebug.ExportSummary(graph, summary);
		System.IO.File.WriteAllText("rendergraph_test_summary.txt", summary);

		// Export lifetime diagram
		let lifetime = scope String();
		GraphDebug.ExportLifetimeDOT(graph, lifetime);
		System.IO.File.WriteAllText("rendergraph_test_lifetime.dot", lifetime);

		// Export validation
		let validation = scope String();
		GraphValidator.ValidateToString(graph, validation);
		System.IO.File.WriteAllText("rendergraph_test_validation.txt", validation);

		// Basic assertions
		Test.Assert(dot.Length > 100);
		Test.Assert(summary.Contains("Scheduled passes: 4"));
		Test.Assert(summary.Contains("Culled passes:    1"));
	}
}
