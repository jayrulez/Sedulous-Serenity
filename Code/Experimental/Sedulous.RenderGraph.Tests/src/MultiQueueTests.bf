using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.RenderGraph;

namespace Sedulous.RenderGraph.Tests;

class MultiQueueTests
{
	[Test]
	public static void TestSameQueueNoCrossSync()
	{
		let graph = scope RenderGraph();

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

		// Same queue — no cross-queue sync needed
		Test.Assert(graph.SyncPoints.Count == 0);
	}

	[Test]
	public static void TestGraphicsToComputeSync()
	{
		let graph = scope RenderGraph();

		RGTexture tex = default;

		graph.AddPass("Render", .Graphics, scope [&] (builder) =>
		{
			tex = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 1920, 1080, 1, "Tex"));
			builder.WriteRenderTarget(tex, 0);
		});

		graph.AddPass("Process", .Compute, scope [&] (builder) =>
		{
			builder.ReadTexture(tex, .Compute);
			builder.HasSideEffects();
		});

		graph.Compile();

		// Cross-queue: Graphics → Compute
		Test.Assert(graph.SyncPoints.Count == 1);
		Test.Assert(graph.SyncPoints[0].SrcQueue == .Graphics);
		Test.Assert(graph.SyncPoints[0].DstQueue == .Compute);
		Test.Assert(graph.SyncPoints[0].FenceValue == 1);
	}

	[Test]
	public static void TestComputeToGraphicsSync()
	{
		let graph = scope RenderGraph();

		RGBuffer buf = default;

		graph.AddPass("Compute", .Compute, scope [&] (builder) =>
		{
			buf = builder.CreateBuffer(.() { Size = 4096, Usage = .Storage, Name = "Data" });
			builder.WriteStorage(buf, .Compute);
		});

		graph.AddPass("Render", .Graphics, scope [&] (builder) =>
		{
			builder.ReadStorageBuffer(buf, .Vertex);
			builder.HasSideEffects();
		});

		graph.Compile();

		Test.Assert(graph.SyncPoints.Count == 1);
		Test.Assert(graph.SyncPoints[0].SrcQueue == .Compute);
		Test.Assert(graph.SyncPoints[0].DstQueue == .Graphics);
	}

	[Test]
	public static void TestMultipleCrossQueueSyncs()
	{
		let graph = scope RenderGraph();

		RGTexture depthTex = default;
		RGBuffer ssaoData = default;

		// Graphics writes depth
		graph.AddPass("DepthPrepass", .Graphics, scope [&] (builder) =>
		{
			depthTex = builder.CreateTexture(.DepthBuffer(.Depth32Float, 1920, 1080, 1, "Depth"));
			builder.WriteDepthStencil(depthTex);
		});

		// Compute reads depth, writes SSAO buffer
		graph.AddPass("SSAO_Compute", .Compute, scope [&] (builder) =>
		{
			builder.ReadTexture(depthTex, .Compute);
			ssaoData = builder.CreateBuffer(.() { Size = 1920 * 1080 * 4, Usage = .Storage, Name = "SSAO" });
			builder.WriteStorage(ssaoData, .Compute);
		});

		// Graphics reads SSAO buffer
		graph.AddPass("Lighting", .Graphics, scope [&] (builder) =>
		{
			builder.ReadStorageBuffer(ssaoData, .Fragment);
			builder.HasSideEffects();
		});

		graph.Compile();

		// Two cross-queue syncs: Graphics→Compute (depth), Compute→Graphics (SSAO)
		Test.Assert(graph.SyncPoints.Count == 2);

		bool hasGraphicsToCompute = false;
		bool hasComputeToGraphics = false;
		for (let sp in graph.SyncPoints)
		{
			if (sp.SrcQueue == .Graphics && sp.DstQueue == .Compute)
				hasGraphicsToCompute = true;
			if (sp.SrcQueue == .Compute && sp.DstQueue == .Graphics)
				hasComputeToGraphics = true;
		}
		Test.Assert(hasGraphicsToCompute);
		Test.Assert(hasComputeToGraphics);
	}

	[Test]
	public static void TestTransferToGraphicsSync()
	{
		let graph = scope RenderGraph();

		RGBuffer staging = default;

		graph.AddPass("Upload", .Transfer, scope [&] (builder) =>
		{
			staging = builder.CreateBuffer(.() { Size = 65536, Usage = .CopySrc | .CopyDst, Name = "Staging" });
			builder.WriteCopyDst(staging);
		});

		graph.AddPass("Render", .Graphics, scope [&] (builder) =>
		{
			builder.ReadStorageBuffer(staging, .Vertex);
			builder.HasSideEffects();
		});

		graph.Compile();

		Test.Assert(graph.SyncPoints.Count == 1);
		Test.Assert(graph.SyncPoints[0].SrcQueue == .Transfer);
		Test.Assert(graph.SyncPoints[0].DstQueue == .Graphics);
	}

	[Test]
	public static void TestMixedQueueExecution()
	{
		let graph = scope RenderGraph();
		let order = scope List<String>();

		RGTexture tex = default;

		graph.AddPass("GfxWrite", .Graphics, scope [&] (builder) =>
		{
			tex = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 1920, 1080, 1, "Tex"));
			builder.WriteRenderTarget(tex, 0);
			builder.SetExecute(new [&] (encoder, registry) =>
			{
				order.Add("GfxWrite");
			});
		});

		graph.AddPass("ComputeRead", .Compute, scope [&] (builder) =>
		{
			builder.ReadTexture(tex, .Compute);
			builder.HasSideEffects();
			builder.SetExecute(new [&] (encoder, registry) =>
			{
				order.Add("ComputeRead");
			});
		});

		graph.Compile();
		graph.Execute(null); // headless

		// Both should execute in order
		Test.Assert(order.Count == 2);
		Test.Assert(order[0] == "GfxWrite");
		Test.Assert(order[1] == "ComputeRead");
	}

	[Test]
	public static void TestFenceValuesIncrement()
	{
		let graph = scope RenderGraph();

		RGTexture tex1 = default;
		RGBuffer buf1 = default;

		graph.AddPass("GfxPass", .Graphics, scope [&] (builder) =>
		{
			tex1 = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 1920, 1080, 1, "Tex1"));
			builder.WriteRenderTarget(tex1, 0);
		});

		graph.AddPass("ComputePass", .Compute, scope [&] (builder) =>
		{
			builder.ReadTexture(tex1, .Compute);
			buf1 = builder.CreateBuffer(.() { Size = 4096, Usage = .Storage, Name = "Buf1" });
			builder.WriteStorage(buf1, .Compute);
		});

		graph.AddPass("TransferRead", .Transfer, scope [&] (builder) =>
		{
			builder.ReadCopySrc(buf1);
			builder.HasSideEffects();
		});

		graph.Compile();

		// Graphics→Compute and Compute→Transfer = 2 sync points
		Test.Assert(graph.SyncPoints.Count == 2);
		// Fence values should be sequential
		Test.Assert(graph.SyncPoints[0].FenceValue == 1);
		Test.Assert(graph.SyncPoints[1].FenceValue == 2);
	}
}
