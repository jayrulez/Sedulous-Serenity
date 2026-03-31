using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.RenderGraph;

namespace Sedulous.RenderGraph.Tests;

class ExecutionTests
{
	[Test]
	public static void TestExecuteCallbackInvoked()
	{
		let graph = scope RenderGraph();
		bool callbackCalled = false;

		graph.AddPass("Test", .Graphics, scope [&] (builder) =>
		{
			builder.HasSideEffects();
			builder.SetExecute(new [&] (encoder, registry) =>
			{
				callbackCalled = true;
			});
		});

		graph.Compile();
		graph.Execute(null); // headless

		Test.Assert(callbackCalled);
	}

	[Test]
	public static void TestExecuteOrder()
	{
		let graph = scope RenderGraph();
		let order = scope List<String>();

		RGTexture tex = default;

		graph.AddPass("First", .Graphics, scope [&] (builder) =>
		{
			tex = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 1920, 1080, 1, "Tex"));
			builder.WriteRenderTarget(tex, 0);
			builder.SetExecute(new [&] (encoder, registry) =>
			{
				order.Add("First");
			});
		});

		graph.AddPass("Second", .Graphics, scope [&] (builder) =>
		{
			builder.ReadTexture(tex, .Fragment);
			builder.HasSideEffects();
			builder.SetExecute(new [&] (encoder, registry) =>
			{
				order.Add("Second");
			});
		});

		graph.Compile();
		graph.Execute(null);

		Test.Assert(order.Count == 2);
		Test.Assert(order[0] == "First");
		Test.Assert(order[1] == "Second");
	}

	[Test]
	public static void TestCulledPassNotExecuted()
	{
		let graph = scope RenderGraph();
		bool culledExecuted = false;
		bool retainedExecuted = false;

		graph.AddPass("Culled", .Graphics, scope [&] (builder) =>
		{
			let tex = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 256, 256, 1, "Unused"));
			builder.WriteRenderTarget(tex, 0);
			builder.SetExecute(new [&] (encoder, registry) =>
			{
				culledExecuted = true;
			});
		});

		graph.AddPass("Retained", .Graphics, scope [&] (builder) =>
		{
			builder.HasSideEffects();
			builder.SetExecute(new [&] (encoder, registry) =>
			{
				retainedExecuted = true;
			});
		});

		graph.Compile();
		graph.Execute(null);

		Test.Assert(!culledExecuted);
		Test.Assert(retainedExecuted);
	}

	[Test]
	public static void TestRegistryResolvesImportedTexture()
	{
		let graph = scope RenderGraph();
		// We use null for the actual GPU resources since we're in headless mode,
		// but we can verify the registry returns what we imported
		let backbuffer = graph.ImportTexture("Backbuffer", null, null, .Present);

		ITexture resolvedTexture = null;
		bool callbackRan = false;

		graph.AddPass("Render", .Graphics, scope [&] (builder) =>
		{
			builder.WriteRenderTarget(backbuffer, 0);
			builder.SetExecute(new [&] (encoder, registry) =>
			{
				resolvedTexture = registry.GetTexture(backbuffer);
				callbackRan = true;
			});
		});

		graph.Compile();
		graph.Execute(null);

		// Callback should have run, and resolved to null (what we imported)
		Test.Assert(callbackRan);
		Test.Assert(resolvedTexture == null);
	}

	[Test]
	public static void TestRegistryResolvesImportedBuffer()
	{
		let graph = scope RenderGraph();
		let buf = graph.ImportBuffer("UBO", null, .UniformBuffer);

		IBuffer resolvedBuffer = null;
		bool bufCallbackRan = false;

		graph.AddPass("Render", .Graphics, scope [&] (builder) =>
		{
			builder.ReadUniformBuffer(buf, .Vertex);
			builder.HasSideEffects();
			builder.SetExecute(new [&] (encoder, registry) =>
			{
				resolvedBuffer = registry.GetBuffer(buf);
				bufCallbackRan = true;
			});
		});

		graph.Compile();
		graph.Execute(null);

		Test.Assert(bufCallbackRan);
		Test.Assert(resolvedBuffer == null);
	}

	[Test]
	public static void TestCompileExecuteResetCycle()
	{
		let graph = scope RenderGraph();
		int executeCount = 0;

		// Frame 1
		graph.AddPass("Frame1", .Graphics, scope [&] (builder) =>
		{
			builder.HasSideEffects();
			builder.SetExecute(new [&] (encoder, registry) =>
			{
				executeCount++;
			});
		});

		graph.Compile();
		graph.Execute(null);
		Test.Assert(executeCount == 1);

		graph.Reset();

		// Frame 2
		graph.AddPass("Frame2", .Graphics, scope [&] (builder) =>
		{
			builder.HasSideEffects();
			builder.SetExecute(new [&] (encoder, registry) =>
			{
				executeCount++;
			});
		});

		graph.Compile();
		graph.Execute(null);
		Test.Assert(executeCount == 2);
	}

	[Test]
	public static void TestGetRenderPassDesc()
	{
		let graph = scope RenderGraph();

		graph.AddPass("MRT", .Graphics, scope (builder) =>
		{
			let color0 = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 1920, 1080, 1, "Color0"));
			let color1 = builder.CreateTexture(.RenderTarget(.RGBA16Float, 1920, 1080, 1, "Color1"));
			let depth = builder.CreateTexture(.DepthBuffer(.Depth32Float, 1920, 1080, 1, "Depth"));
			builder.WriteRenderTarget(color0, 0, .Clear, .Store, .Black);
			builder.WriteRenderTarget(color1, 1, .Clear, .Store, .White);
			builder.WriteDepthStencil(depth);
			builder.HasSideEffects();
		});

		graph.Compile();

		let pass = graph.GetScheduledPass(0);
		Test.Assert(pass.RenderTargets.Count == 2);
		Test.Assert(pass.DepthStencil.HasValue);
		Test.Assert(pass.RenderTargets[0].LoadOp == .Clear);
		Test.Assert(pass.RenderTargets[1].LoadOp == .Clear);
	}

	[Test]
	public static void TestExecuteWithNoScheduledPasses()
	{
		let graph = scope RenderGraph();

		// All passes get culled
		graph.AddPass("Orphan", .Graphics, scope (builder) =>
		{
			let tex = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 256, 256, 1, "Orphan"));
			builder.WriteRenderTarget(tex, 0);
		});

		graph.Compile();
		Test.Assert(graph.ScheduledPassCount == 0);

		// Should not crash
		graph.Execute(null);
	}

	[Test]
	public static void TestThreePassPipelineExecution()
	{
		// GBuffer → Lighting → Tonemap (the canonical render graph example)
		let graph = scope RenderGraph();
		let order = scope List<String>();

		RGTexture gbufferAlbedo = default;
		RGTexture gbufferNormal = default;
		RGTexture gbufferDepth = default;
		RGTexture hdr = default;

		graph.AddPass("GBuffer", .Graphics, scope [&] (builder) =>
		{
			gbufferAlbedo = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 1920, 1080, 1, "Albedo"));
			gbufferNormal = builder.CreateTexture(.RenderTarget(.RGBA16Float, 1920, 1080, 1, "Normal"));
			gbufferDepth = builder.CreateTexture(.DepthBuffer(.Depth32Float, 1920, 1080, 1, "Depth"));
			builder.WriteRenderTarget(gbufferAlbedo, 0);
			builder.WriteRenderTarget(gbufferNormal, 1);
			builder.WriteDepthStencil(gbufferDepth);
			builder.SetExecute(new [&] (encoder, registry) =>
			{
				order.Add("GBuffer");
			});
		});

		graph.AddPass("Lighting", .Graphics, scope [&] (builder) =>
		{
			builder.ReadTexture(gbufferAlbedo, .Fragment);
			builder.ReadTexture(gbufferNormal, .Fragment);
			builder.ReadTexture(gbufferDepth, .Fragment);
			hdr = builder.CreateTexture(.RenderTarget(.RGBA16Float, 1920, 1080, 1, "HDR"));
			builder.WriteRenderTarget(hdr, 0);
			builder.SetExecute(new [&] (encoder, registry) =>
			{
				order.Add("Lighting");
			});
		});

		graph.AddPass("Tonemap", .Graphics, scope [&] (builder) =>
		{
			builder.ReadTexture(hdr, .Fragment);
			builder.HasSideEffects();
			builder.SetExecute(new [&] (encoder, registry) =>
			{
				order.Add("Tonemap");
			});
		});

		graph.Compile();
		graph.Execute(null);

		Test.Assert(order.Count == 3);
		Test.Assert(order[0] == "GBuffer");
		Test.Assert(order[1] == "Lighting");
		Test.Assert(order[2] == "Tonemap");

		// Verify barriers are correct
		// GBuffer: Undefined→RenderTarget for albedo, normal; Undefined→DepthStencilWrite for depth
		let gbufBarriers = graph.GetBarriersForPass(0);
		Test.Assert(gbufBarriers.HasValue);
		Test.Assert(gbufBarriers.Value.TextureBarriers.Count == 3);

		// Lighting: RenderTarget→ShaderRead for albedo, normal; DepthStencilWrite→ShaderRead for depth
		//           Undefined→RenderTarget for HDR
		let lightBarriers = graph.GetBarriersForPass(1);
		Test.Assert(lightBarriers.HasValue);
		Test.Assert(lightBarriers.Value.TextureBarriers.Count == 4);

		// Tonemap: RenderTarget→ShaderRead for HDR
		let tonemapBarriers = graph.GetBarriersForPass(2);
		Test.Assert(tonemapBarriers.HasValue);
		Test.Assert(tonemapBarriers.Value.TextureBarriers.Count == 1);
	}
}
