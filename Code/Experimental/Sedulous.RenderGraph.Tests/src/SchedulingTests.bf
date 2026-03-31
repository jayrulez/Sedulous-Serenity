using System;
using Sedulous.RHI;
using Sedulous.RenderGraph;

namespace Sedulous.RenderGraph.Tests;

class SchedulingTests
{
	[Test]
	public static void TestTopologicalSort()
	{
		let graph = scope RenderGraph();

		RGTexture albedo = default;

		graph.AddPass("GBuffer", .Graphics, scope [&] (builder) =>
		{
			albedo = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 1920, 1080, 1, "Albedo"));
			builder.WriteRenderTarget(albedo, 0);
			builder.HasSideEffects();
		});

		graph.AddPass("Lighting", .Graphics, scope [&] (builder) =>
		{
			builder.ReadTexture(albedo, .Fragment);
			builder.HasSideEffects();
		});

		graph.Compile();

		// Both passes should survive (both have side effects)
		Test.Assert(graph.ScheduledPassCount == 2);
		// GBuffer must execute before Lighting
		Test.Assert(graph.GetScheduledPass(0).Name == "GBuffer");
		Test.Assert(graph.GetScheduledPass(1).Name == "Lighting");
	}

	[Test]
	public static void TestCullingUnusedPass()
	{
		let graph = scope RenderGraph();

		RGTexture used = default;

		graph.AddPass("UsedPass", .Graphics, scope [&] (builder) =>
		{
			used = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 1920, 1080, 1, "Used"));
			builder.WriteRenderTarget(used, 0);
			builder.HasSideEffects();
		});

		// This pass creates a texture nobody reads and has no side effects
		graph.AddPass("UnusedPass", .Graphics, scope (builder) =>
		{
			let unused = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 256, 256, 1, "Unused"));
			builder.WriteRenderTarget(unused, 0);
		});

		graph.Compile();

		// Only the used pass should survive
		Test.Assert(graph.ScheduledPassCount == 1);
		Test.Assert(graph.GetScheduledPass(0).Name == "UsedPass");
	}

	[Test]
	public static void TestCullingPreservesDependencyChain()
	{
		let graph = scope RenderGraph();

		RGTexture tex = default;

		// Pass A creates a texture
		graph.AddPass("Producer", .Graphics, scope [&] (builder) =>
		{
			tex = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 1920, 1080, 1, "Tex"));
			builder.WriteRenderTarget(tex, 0);
		});

		// Pass B reads it and has side effects
		graph.AddPass("Consumer", .Graphics, scope [&] (builder) =>
		{
			builder.ReadTexture(tex, .Fragment);
			builder.HasSideEffects();
		});

		graph.Compile();

		// Both should survive — Consumer has side effects and depends on Producer
		Test.Assert(graph.ScheduledPassCount == 2);
		Test.Assert(graph.GetScheduledPass(0).Name == "Producer");
		Test.Assert(graph.GetScheduledPass(1).Name == "Consumer");
	}

	[Test]
	public static void TestImportedResourcePreventsCulling()
	{
		let graph = scope RenderGraph();

		let backbuffer = graph.ImportTexture("Backbuffer", null, null, .Present);

		// This pass writes to the imported backbuffer — should not be culled
		graph.AddPass("Present", .Graphics, scope [&] (builder) =>
		{
			builder.WriteRenderTarget(backbuffer, 0);
		});

		graph.Compile();

		Test.Assert(graph.ScheduledPassCount == 1);
		Test.Assert(graph.GetScheduledPass(0).Name == "Present");
	}

	[Test]
	public static void TestSideEffectsPreventCulling()
	{
		let graph = scope RenderGraph();

		graph.AddPass("SideEffectPass", .Graphics, scope (builder) =>
		{
			builder.HasSideEffects();
		});

		graph.Compile();

		Test.Assert(graph.ScheduledPassCount == 1);
	}

	[Test]
	public static void TestThreePassChain()
	{
		let graph = scope RenderGraph();

		RGTexture gbuffer = default;
		RGTexture hdr = default;

		graph.AddPass("GBuffer", .Graphics, scope [&] (builder) =>
		{
			gbuffer = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 1920, 1080, 1, "GBuffer"));
			builder.WriteRenderTarget(gbuffer, 0);
		});

		graph.AddPass("Lighting", .Graphics, scope [&] (builder) =>
		{
			builder.ReadTexture(gbuffer, .Fragment);
			hdr = builder.CreateTexture(.RenderTarget(.RGBA16Float, 1920, 1080, 1, "HDR"));
			builder.WriteRenderTarget(hdr, 0);
		});

		graph.AddPass("Tonemap", .Graphics, scope [&] (builder) =>
		{
			builder.ReadTexture(hdr, .Fragment);
			builder.HasSideEffects();
		});

		graph.Compile();

		// All three should be retained (chain leads to side-effect pass)
		Test.Assert(graph.ScheduledPassCount == 3);
		Test.Assert(graph.GetScheduledPass(0).Name == "GBuffer");
		Test.Assert(graph.GetScheduledPass(1).Name == "Lighting");
		Test.Assert(graph.GetScheduledPass(2).Name == "Tonemap");
	}

	[Test]
	public static void TestCompileAndReset()
	{
		let graph = scope RenderGraph();

		graph.AddPass("Pass1", .Graphics, scope (builder) =>
		{
			builder.HasSideEffects();
		});

		graph.Compile();
		Test.Assert(graph.IsCompiled == true);
		Test.Assert(graph.ScheduledPassCount == 1);

		graph.Reset();
		Test.Assert(graph.IsCompiled == false);
		Test.Assert(graph.PassCount == 0);
		Test.Assert(graph.ScheduledPassCount == 0);

		// Should be able to reuse after reset
		graph.AddPass("Pass2", .Graphics, scope (builder) =>
		{
			builder.HasSideEffects();
		});

		graph.Compile();
		Test.Assert(graph.ScheduledPassCount == 1);
		Test.Assert(graph.GetScheduledPass(0).Name == "Pass2");
	}

	[Test]
	public static void TestAllPassesCulled()
	{
		let graph = scope RenderGraph();

		// Two passes with no side effects and no imported resource writes
		graph.AddPass("Orphan1", .Graphics, scope (builder) =>
		{
			let tex = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 256, 256, 1, "Orphan"));
			builder.WriteRenderTarget(tex, 0);
		});

		graph.AddPass("Orphan2", .Compute, scope (builder) =>
		{
			let buf = builder.CreateBuffer(.() { Size = 1024, Usage = .Storage, Name = "OrphanBuf" });
			builder.WriteStorage(buf, .Compute);
		});

		graph.Compile();

		Test.Assert(graph.ScheduledPassCount == 0);
	}

	[Test]
	public static void TestLoadOpCreatesWriteAfterWriteDependency()
	{
		// Two passes write to the same render target.
		// The second uses LoadOp.Load, which implies reading the first pass's output.
		// The scheduler must order the Load pass after the Clear pass.
		let graph = scope RenderGraph();

		let backbuffer = graph.ImportTexture("Backbuffer", null, null, .Present);

		graph.AddPass("Blit", .Graphics, scope [&] (builder) =>
		{
			builder.WriteRenderTarget(backbuffer, 0, .Clear, .Store);
		});

		graph.AddPass("Overlay", .Graphics, scope [&] (builder) =>
		{
			builder.WriteRenderTarget(backbuffer, 0, .Load, .Store);
			builder.HasSideEffects();
		});

		graph.Compile();

		// Both passes should be retained (Overlay has side effects, Blit writes to imported resource)
		Test.Assert(graph.ScheduledPassCount == 2);
		// Blit must execute before Overlay (Load depends on previous write)
		Test.Assert(graph.GetScheduledPass(0).Name == "Blit");
		Test.Assert(graph.GetScheduledPass(1).Name == "Overlay");
	}

	[Test]
	public static void TestLoadOpDepthCreatesWriteAfterWriteDependency()
	{
		// Same pattern for depth: Load implies reading the previous depth writer's output.
		let graph = scope RenderGraph();

		RGTexture depth = default;

		graph.AddPass("DepthPrepass", .Graphics, scope [&] (builder) =>
		{
			depth = builder.CreateTexture(.DepthBuffer(.Depth32Float, 1920, 1080, 1, "Depth"));
			builder.WriteDepthStencil(depth, .Clear, .Store);
			builder.HasSideEffects();
		});

		graph.AddPass("ForwardOpaque", .Graphics, scope [&] (builder) =>
		{
			builder.WriteDepthStencil(depth, .Load, .Store);
			builder.HasSideEffects();
		});

		graph.Compile();

		Test.Assert(graph.ScheduledPassCount == 2);
		Test.Assert(graph.GetScheduledPass(0).Name == "DepthPrepass");
		Test.Assert(graph.GetScheduledPass(1).Name == "ForwardOpaque");
	}
}
