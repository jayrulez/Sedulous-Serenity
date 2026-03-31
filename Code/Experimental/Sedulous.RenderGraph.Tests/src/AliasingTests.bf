using System;
using Sedulous.RHI;
using Sedulous.RenderGraph;

namespace Sedulous.RenderGraph.Tests;

class AliasingTests
{
	[Test]
	public static void TestSingleTransientTexture()
	{
		let graph = scope RenderGraph();

		graph.AddPass("Render", .Graphics, scope (builder) =>
		{
			let tex = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 1920, 1080, 1, "Color"));
			builder.WriteRenderTarget(tex, 0);
			builder.HasSideEffects();
		});

		graph.Compile();

		// One transient texture → one pool entry
		Test.Assert(graph.Pool.AssignmentCount == 1);
		Test.Assert(graph.Pool.TexturePoolSize == 1);
	}

	[Test]
	public static void TestNonOverlappingTexturesAliased()
	{
		// Two transient textures with non-overlapping lifetimes and same descriptor
		// should share a single pool slot
		let graph = scope RenderGraph();

		RGTexture texA = default;

		graph.AddPass("PassA", .Graphics, scope [&] (builder) =>
		{
			texA = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 1920, 1080, 1, "TempA"));
			builder.WriteRenderTarget(texA, 0);
			builder.HasSideEffects();
		});

		graph.AddPass("PassB", .Graphics, scope [&] (builder) =>
		{
			// texA is last used in PassA (index 0), PassB starts at index 1
			let texB = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 1920, 1080, 1, "TempB"));
			builder.WriteRenderTarget(texB, 0);
			builder.HasSideEffects();
		});

		graph.Compile();

		// Both textures have same descriptor, non-overlapping lifetimes → should alias
		Test.Assert(graph.Pool.AssignmentCount == 2);
		Test.Assert(graph.Pool.TexturePoolSize == 1); // Aliased to same slot

		// Verify both map to pool index 0
		let a0 = graph.Pool.GetAssignment(0);
		let a1 = graph.Pool.GetAssignment(1);
		Test.Assert(a0.PoolIndex == a1.PoolIndex);
	}

	[Test]
	public static void TestOverlappingTexturesNotAliased()
	{
		// Two textures with overlapping lifetimes must NOT share a pool slot
		let graph = scope RenderGraph();

		RGTexture texA = default;
		RGTexture texB = default;

		graph.AddPass("GBuffer", .Graphics, scope [&] (builder) =>
		{
			texA = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 1920, 1080, 1, "Albedo"));
			texB = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 1920, 1080, 1, "Normal"));
			builder.WriteRenderTarget(texA, 0);
			builder.WriteRenderTarget(texB, 1);
		});

		graph.AddPass("Lighting", .Graphics, scope [&] (builder) =>
		{
			builder.ReadTexture(texA, .Fragment);
			builder.ReadTexture(texB, .Fragment);
			builder.HasSideEffects();
		});

		graph.Compile();

		// Both textures are alive during Lighting pass — cannot alias
		Test.Assert(graph.Pool.AssignmentCount == 2);
		Test.Assert(graph.Pool.TexturePoolSize == 2); // Separate pool slots

		let a0 = graph.Pool.GetAssignment(0);
		let a1 = graph.Pool.GetAssignment(1);
		Test.Assert(a0.PoolIndex != a1.PoolIndex);
	}

	[Test]
	public static void TestDifferentDescriptorsNotAliased()
	{
		// Two textures with different formats, even if non-overlapping, get separate slots
		let graph = scope RenderGraph();

		graph.AddPass("PassA", .Graphics, scope (builder) =>
		{
			let tex = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 1920, 1080, 1, "A"));
			builder.WriteRenderTarget(tex, 0);
			builder.HasSideEffects();
		});

		graph.AddPass("PassB", .Graphics, scope (builder) =>
		{
			let tex = builder.CreateTexture(.RenderTarget(.RGBA16Float, 1920, 1080, 1, "B"));
			builder.WriteRenderTarget(tex, 0);
			builder.HasSideEffects();
		});

		graph.Compile();

		// Different formats → cannot alias
		Test.Assert(graph.Pool.TexturePoolSize == 2);
	}

	[Test]
	public static void TestBufferAliasing()
	{
		let graph = scope RenderGraph();

		RGBuffer bufA = default;

		graph.AddPass("Compute1", .Compute, scope [&] (builder) =>
		{
			bufA = builder.CreateBuffer(.() { Size = 4096, Usage = .Storage, Name = "BufA" });
			builder.WriteStorage(bufA, .Compute);
			builder.HasSideEffects();
		});

		graph.AddPass("Compute2", .Compute, scope (builder) =>
		{
			// bufA not used here — non-overlapping
			let bufB = builder.CreateBuffer(.() { Size = 4096, Usage = .Storage, Name = "BufB" });
			builder.WriteStorage(bufB, .Compute);
			builder.HasSideEffects();
		});

		graph.Compile();

		// Same size + usage, non-overlapping → should alias
		Test.Assert(graph.Pool.BufferPoolSize == 1);
	}

	[Test]
	public static void TestMixedTextureAndBuffer()
	{
		let graph = scope RenderGraph();

		graph.AddPass("Pass", .Graphics, scope (builder) =>
		{
			let tex = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 1920, 1080, 1, "Tex"));
			let buf = builder.CreateBuffer(.() { Size = 1024, Usage = .Storage, Name = "Buf" });
			builder.WriteRenderTarget(tex, 0);
			builder.WriteStorage(buf, .Fragment);
			builder.HasSideEffects();
		});

		graph.Compile();

		Test.Assert(graph.Pool.TexturePoolSize == 1);
		Test.Assert(graph.Pool.BufferPoolSize == 1);
		Test.Assert(graph.Pool.AssignmentCount == 2);
	}

	[Test]
	public static void TestPoolReuseAcrossFrames()
	{
		let graph = scope RenderGraph();

		// Frame 1
		graph.AddPass("Render", .Graphics, scope (builder) =>
		{
			let tex = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 1920, 1080, 1, "Color"));
			builder.WriteRenderTarget(tex, 0);
			builder.HasSideEffects();
		});

		graph.Compile();
		Test.Assert(graph.Pool.TexturePoolSize == 1);

		graph.Reset();

		// Frame 2 — same descriptor, pool should reuse
		graph.AddPass("Render", .Graphics, scope (builder) =>
		{
			let tex = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 1920, 1080, 1, "Color"));
			builder.WriteRenderTarget(tex, 0);
			builder.HasSideEffects();
		});

		graph.Compile();
		// Pool size should still be 1 — reused existing slot
		Test.Assert(graph.Pool.TexturePoolSize == 1);
	}

	[Test]
	public static void TestCulledResourcesNotAllocated()
	{
		let graph = scope RenderGraph();

		// This pass's output isn't consumed → gets culled
		graph.AddPass("Unused", .Graphics, scope (builder) =>
		{
			let tex = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 256, 256, 1, "Orphan"));
			builder.WriteRenderTarget(tex, 0);
		});

		graph.AddPass("Used", .Graphics, scope (builder) =>
		{
			let tex = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 1920, 1080, 1, "Real"));
			builder.WriteRenderTarget(tex, 0);
			builder.HasSideEffects();
		});

		graph.Compile();

		// Only the non-culled pass's resource should be assigned
		Test.Assert(graph.ScheduledPassCount == 1);
		// The culled resource has no firstUsePass set, so it shouldn't get an assignment
		Test.Assert(graph.Pool.AssignmentCount == 1);
	}

	[Test]
	public static void TestThreeResourceAliasingChain()
	{
		// A → B → C with same descriptor, sequential non-overlapping lifetimes
		let graph = scope RenderGraph();

		RGTexture texA = default;
		RGTexture texB = default;

		graph.AddPass("PassA", .Graphics, scope [&] (builder) =>
		{
			texA = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 512, 512, 1, "A"));
			builder.WriteRenderTarget(texA, 0);
		});

		graph.AddPass("PassB", .Graphics, scope [&] (builder) =>
		{
			builder.ReadTexture(texA, .Fragment);
			texB = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 512, 512, 1, "B"));
			builder.WriteRenderTarget(texB, 0);
		});

		graph.AddPass("PassC", .Graphics, scope [&] (builder) =>
		{
			builder.ReadTexture(texB, .Fragment);
			let texC = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 512, 512, 1, "C"));
			builder.WriteRenderTarget(texC, 0);
			builder.HasSideEffects();
		});

		graph.Compile();

		Test.Assert(graph.ScheduledPassCount == 3);
		Test.Assert(graph.Pool.AssignmentCount == 3);

		// texA is alive in PassA-PassB (indices 0-1)
		// texB is alive in PassB-PassC (indices 1-2)
		// texC is alive in PassC only (index 2)
		// texA and texC don't overlap → can alias
		// texB overlaps with both → needs its own slot
		// So we need at minimum 2 pool slots
		Test.Assert(graph.Pool.TexturePoolSize == 2);
	}

	[Test]
	public static void TestImportedResourcesNotPooled()
	{
		let graph = scope RenderGraph();

		let backbuffer = graph.ImportTexture("Backbuffer", null, null, .Present);

		graph.AddPass("Render", .Graphics, scope [&] (builder) =>
		{
			builder.WriteRenderTarget(backbuffer, 0);
		});

		graph.Compile();

		// Imported resources should NOT be assigned pool slots
		Test.Assert(graph.Pool.AssignmentCount == 0);
		Test.Assert(graph.Pool.TexturePoolSize == 0);
	}
}
