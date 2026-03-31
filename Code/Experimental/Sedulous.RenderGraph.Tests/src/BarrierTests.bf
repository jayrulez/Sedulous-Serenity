using System;
using Sedulous.RHI;
using Sedulous.RenderGraph;

namespace Sedulous.RenderGraph.Tests;

class BarrierTests
{
	[Test]
	public static void TestBasicStateTransition()
	{
		// Texture goes from RenderTarget → ShaderRead between two passes
		let graph = scope RenderGraph();

		RGTexture color = default;

		graph.AddPass("Render", .Graphics, scope [&] (builder) =>
		{
			color = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 1920, 1080, 1, "Color"));
			builder.WriteRenderTarget(color, 0);
		});

		graph.AddPass("Sample", .Graphics, scope [&] (builder) =>
		{
			builder.ReadTexture(color, .Fragment);
			builder.HasSideEffects();
		});

		graph.Compile();

		Test.Assert(graph.ScheduledPassCount == 2);
		// The Sample pass (index 1) should have a barrier: RenderTarget → ShaderRead
		let barriers = graph.GetBarriersForPass(1);
		Test.Assert(barriers.HasValue);
		Test.Assert(barriers.Value.TextureBarriers != null);
		Test.Assert(barriers.Value.TextureBarriers.Count == 1);
		Test.Assert(barriers.Value.TextureBarriers[0].OldState == .RenderTarget);
		Test.Assert(barriers.Value.TextureBarriers[0].NewState == .ShaderRead);
	}

	[Test]
	public static void TestNoBarrierWhenStateSame()
	{
		// Two consecutive reads of the same texture — no barrier needed
		let graph = scope RenderGraph();

		RGTexture tex = default;

		graph.AddPass("Write", .Graphics, scope [&] (builder) =>
		{
			tex = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 1920, 1080, 1, "Tex"));
			builder.WriteRenderTarget(tex, 0);
		});

		graph.AddPass("Read1", .Graphics, scope [&] (builder) =>
		{
			builder.ReadTexture(tex, .Fragment);
			builder.HasSideEffects();
		});

		graph.AddPass("Read2", .Graphics, scope [&] (builder) =>
		{
			builder.ReadTexture(tex, .Fragment);
			builder.HasSideEffects();
		});

		graph.Compile();

		Test.Assert(graph.ScheduledPassCount == 3);

		// Read1 needs barrier (RenderTarget → ShaderRead)
		let barriersRead1 = graph.GetBarriersForPass(1);
		Test.Assert(barriersRead1.HasValue);

		// Read2 should NOT need a barrier (already in ShaderRead)
		let barriersRead2 = graph.GetBarriersForPass(2);
		Test.Assert(!barriersRead2.HasValue);
	}

	[Test]
	public static void TestUndefinedToFirstUse()
	{
		// Transient texture starts in Undefined state, first use is RenderTarget
		let graph = scope RenderGraph();

		graph.AddPass("Render", .Graphics, scope (builder) =>
		{
			let tex = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 1920, 1080, 1, "Tex"));
			builder.WriteRenderTarget(tex, 0);
			builder.HasSideEffects();
		});

		graph.Compile();

		// Undefined → RenderTarget barrier should be generated
		let barriers = graph.GetBarriersForPass(0);
		Test.Assert(barriers.HasValue);
		Test.Assert(barriers.Value.TextureBarriers != null);
		Test.Assert(barriers.Value.TextureBarriers[0].OldState == .Undefined);
		Test.Assert(barriers.Value.TextureBarriers[0].NewState == .RenderTarget);
	}

	[Test]
	public static void TestImportedResourceInitialState()
	{
		// Imported texture starts in Present state, first pass writes it as RenderTarget
		let graph = scope RenderGraph();

		let backbuffer = graph.ImportTexture("Backbuffer", null, null, .Present);

		graph.AddPass("Render", .Graphics, scope [&] (builder) =>
		{
			builder.WriteRenderTarget(backbuffer, 0);
		});

		graph.Compile();

		// Present → RenderTarget
		let barriers = graph.GetBarriersForPass(0);
		Test.Assert(barriers.HasValue);
		Test.Assert(barriers.Value.TextureBarriers != null);
		Test.Assert(barriers.Value.TextureBarriers[0].OldState == .Present);
		Test.Assert(barriers.Value.TextureBarriers[0].NewState == .RenderTarget);
	}

	[Test]
	public static void TestMultipleResourceBarriers()
	{
		// Pass reads two textures that were written by a previous pass
		let graph = scope RenderGraph();

		RGTexture albedo = default;
		RGTexture normal = default;

		graph.AddPass("GBuffer", .Graphics, scope [&] (builder) =>
		{
			albedo = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 1920, 1080, 1, "Albedo"));
			normal = builder.CreateTexture(.RenderTarget(.RGBA16Float, 1920, 1080, 1, "Normal"));
			builder.WriteRenderTarget(albedo, 0);
			builder.WriteRenderTarget(normal, 1);
		});

		graph.AddPass("Lighting", .Graphics, scope [&] (builder) =>
		{
			builder.ReadTexture(albedo, .Fragment);
			builder.ReadTexture(normal, .Fragment);
			builder.HasSideEffects();
		});

		graph.Compile();

		// Lighting pass should have 2 texture barriers
		let barriers = graph.GetBarriersForPass(1);
		Test.Assert(barriers.HasValue);
		Test.Assert(barriers.Value.TextureBarriers != null);
		Test.Assert(barriers.Value.TextureBarriers.Count == 2);
		// Both should be RenderTarget → ShaderRead
		for (let tb in barriers.Value.TextureBarriers)
		{
			Test.Assert(tb.OldState == .RenderTarget);
			Test.Assert(tb.NewState == .ShaderRead);
		}
	}

	[Test]
	public static void TestBufferBarrier()
	{
		let graph = scope RenderGraph();

		RGBuffer buf = default;

		graph.AddPass("Compute", .Compute, scope [&] (builder) =>
		{
			buf = builder.CreateBuffer(.() { Size = 4096, Usage = .Storage, Name = "Data" });
			builder.WriteStorage(buf, .Compute);
		});

		graph.AddPass("Read", .Graphics, scope [&] (builder) =>
		{
			builder.ReadStorageBuffer(buf, .Vertex);
			builder.HasSideEffects();
		});

		graph.Compile();

		// Read pass should have a buffer barrier: ShaderWrite → ShaderRead
		let barriers = graph.GetBarriersForPass(1);
		Test.Assert(barriers.HasValue);
		Test.Assert(barriers.Value.BufferBarriers != null);
		Test.Assert(barriers.Value.BufferBarriers.Count == 1);
		Test.Assert(barriers.Value.BufferBarriers[0].OldState == .ShaderWrite);
		Test.Assert(barriers.Value.BufferBarriers[0].NewState == .ShaderRead);
	}

	[Test]
	public static void TestDepthWriteThenRead()
	{
		let graph = scope RenderGraph();

		RGTexture depth = default;

		graph.AddPass("DepthPrepass", .Graphics, scope [&] (builder) =>
		{
			depth = builder.CreateTexture(.DepthBuffer(.Depth32Float, 1920, 1080, 1, "Depth"));
			builder.WriteDepthStencil(depth);
		});

		graph.AddPass("Lighting", .Graphics, scope [&] (builder) =>
		{
			builder.ReadDepthStencil(depth);
			builder.HasSideEffects();
		});

		graph.Compile();

		// Lighting needs barrier: DepthStencilWrite → DepthStencilRead
		let barriers = graph.GetBarriersForPass(1);
		Test.Assert(barriers.HasValue);
		Test.Assert(barriers.Value.TextureBarriers != null);
		Test.Assert(barriers.Value.TextureBarriers[0].OldState == .DepthStencilWrite);
		Test.Assert(barriers.Value.TextureBarriers[0].NewState == .DepthStencilRead);
	}

	[Test]
	public static void TestCopyBarriers()
	{
		let graph = scope RenderGraph();

		RGTexture tex = default;

		graph.AddPass("Render", .Graphics, scope [&] (builder) =>
		{
			tex = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 1920, 1080, 1, "Tex"));
			builder.WriteRenderTarget(tex, 0);
		});

		graph.AddPass("Copy", .Transfer, scope [&] (builder) =>
		{
			builder.ReadCopySrc(tex);
			builder.HasSideEffects();
		});

		graph.Compile();

		// Copy pass: RenderTarget → CopySrc
		let barriers = graph.GetBarriersForPass(1);
		Test.Assert(barriers.HasValue);
		Test.Assert(barriers.Value.TextureBarriers != null);
		Test.Assert(barriers.Value.TextureBarriers[0].OldState == .RenderTarget);
		Test.Assert(barriers.Value.TextureBarriers[0].NewState == .CopySrc);
	}

	[Test]
	public static void TestWriteAfterWriteMemoryBarrier()
	{
		// Two passes write the same storage buffer — needs execution barrier
		let graph = scope RenderGraph();

		RGBuffer buf = default;

		graph.AddPass("Compute1", .Compute, scope [&] (builder) =>
		{
			buf = builder.CreateBuffer(.() { Size = 4096, Usage = .Storage, Name = "Data" });
			builder.WriteStorage(buf, .Compute);
			builder.HasSideEffects();
		});

		graph.AddPass("Compute2", .Compute, scope [&] (builder) =>
		{
			builder.WriteStorage(buf, .Compute);
			builder.HasSideEffects();
		});

		graph.Compile();

		// Compute2 should have a memory barrier (same state, write-after-write)
		let barriers = graph.GetBarriersForPass(1);
		Test.Assert(barriers.HasValue);
		Test.Assert(barriers.Value.MemoryBarriers != null);
		Test.Assert(barriers.Value.MemoryBarriers.Count == 1);
		Test.Assert(barriers.Value.MemoryBarriers[0].OldState == .ShaderWrite);
		Test.Assert(barriers.Value.MemoryBarriers[0].NewState == .ShaderWrite);
	}

	[Test]
	public static void TestThreePassBarrierChain()
	{
		// RenderTarget → ShaderRead → CopySrc
		let graph = scope RenderGraph();

		RGTexture tex = default;

		graph.AddPass("Render", .Graphics, scope [&] (builder) =>
		{
			tex = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 1920, 1080, 1, "Tex"));
			builder.WriteRenderTarget(tex, 0);
		});

		graph.AddPass("Sample", .Graphics, scope [&] (builder) =>
		{
			builder.ReadTexture(tex, .Fragment);
			let outTex = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 1920, 1080, 1, "Out"));
			builder.WriteRenderTarget(outTex, 0);
			builder.HasSideEffects();
		});

		graph.AddPass("Readback", .Transfer, scope [&] (builder) =>
		{
			builder.ReadCopySrc(tex);
			builder.HasSideEffects();
		});

		graph.Compile();

		// Sample pass: Undefined→RenderTarget for Out, RenderTarget→ShaderRead for Tex
		let barriers1 = graph.GetBarriersForPass(1);
		Test.Assert(barriers1.HasValue);

		// Readback pass: ShaderRead→CopySrc for Tex
		let barriers2 = graph.GetBarriersForPass(2);
		Test.Assert(barriers2.HasValue);
		Test.Assert(barriers2.Value.TextureBarriers != null);

		// Find the barrier for Tex (ShaderRead → CopySrc)
		bool foundCopySrc = false;
		for (let tb in barriers2.Value.TextureBarriers)
		{
			if (tb.OldState == .ShaderRead && tb.NewState == .CopySrc)
				foundCopySrc = true;
		}
		Test.Assert(foundCopySrc);
	}

	[Test]
	public static void TestNoBarriersForSinglePass()
	{
		// Single pass with side effects, imported resource already in correct state
		let graph = scope RenderGraph();

		let backbuffer = graph.ImportTexture("Backbuffer", null, null, .RenderTarget);

		graph.AddPass("Render", .Graphics, scope [&] (builder) =>
		{
			builder.WriteRenderTarget(backbuffer, 0);
		});

		graph.Compile();

		// Already in RenderTarget state — no barrier needed
		Test.Assert(graph.PassBarriers.Count == 0);
	}

	[Test]
	public static void TestAccessToResourceStateMapping()
	{
		// Verify the mapping table from RGResourceAccess.ToResourceState()
		RGResourceAccess access = default;

		access.AccessType = .ReadTexture;
		Test.Assert(access.ToResourceState() == .ShaderRead);

		access.AccessType = .ReadUniformBuffer;
		Test.Assert(access.ToResourceState() == .UniformBuffer);

		access.AccessType = .ReadStorageBuffer;
		Test.Assert(access.ToResourceState() == .ShaderRead);

		access.AccessType = .ReadDepthStencil;
		Test.Assert(access.ToResourceState() == .DepthStencilRead);

		access.AccessType = .ReadCopySrc;
		Test.Assert(access.ToResourceState() == .CopySrc);

		access.AccessType = .WriteRenderTarget;
		Test.Assert(access.ToResourceState() == .RenderTarget);

		access.AccessType = .WriteDepthStencil;
		Test.Assert(access.ToResourceState() == .DepthStencilWrite);

		access.AccessType = .WriteStorage;
		Test.Assert(access.ToResourceState() == .ShaderWrite);

		access.AccessType = .WriteCopyDst;
		Test.Assert(access.ToResourceState() == .CopyDst);
	}
}
