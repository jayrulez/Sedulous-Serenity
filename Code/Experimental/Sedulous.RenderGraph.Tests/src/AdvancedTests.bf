using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.RenderGraph;

namespace Sedulous.RenderGraph.Tests;

class AdvancedTests
{
	// =========================================================================
	// Conditional Passes
	// =========================================================================

	[Test]
	public static void TestConditionalPassSkipped()
	{
		let graph = scope RenderGraph();
		let order = scope List<String>();

		graph.AddPass("Always", .Graphics, scope [&] (builder) =>
		{
			builder.HasSideEffects();
			builder.SetExecute(new [&] (encoder, registry) =>
			{
				order.Add("Always");
			});
		});

		graph.AddPass("Conditional", .Graphics, scope [&] (builder) =>
		{
			builder.HasSideEffects();
			builder.EnableIf(new () => false); // always disabled
			builder.SetExecute(new [&] (encoder, registry) =>
			{
				order.Add("Conditional");
			});
		});

		graph.Compile();
		graph.Execute(null);

		// Conditional pass should be skipped
		Test.Assert(order.Count == 1);
		Test.Assert(order[0] == "Always");
	}

	[Test]
	public static void TestConditionalPassEnabled()
	{
		let graph = scope RenderGraph();
		let order = scope List<String>();

		graph.AddPass("Always", .Graphics, scope [&] (builder) =>
		{
			builder.HasSideEffects();
			builder.SetExecute(new [&] (encoder, registry) =>
			{
				order.Add("Always");
			});
		});

		graph.AddPass("Conditional", .Graphics, scope [&] (builder) =>
		{
			builder.HasSideEffects();
			builder.EnableIf(new () => true); // always enabled
			builder.SetExecute(new [&] (encoder, registry) =>
			{
				order.Add("Conditional");
			});
		});

		graph.Compile();
		graph.Execute(null);

		// Both should execute
		Test.Assert(order.Count == 2);
		Test.Assert(order[0] == "Always");
		Test.Assert(order[1] == "Conditional");
	}

	[Test]
	public static void TestConditionalPassStillScheduled()
	{
		// Conditional passes participate in scheduling even when disabled at runtime
		let graph = scope RenderGraph();

		RGTexture tex = default;

		graph.AddPass("Write", .Graphics, scope [&] (builder) =>
		{
			tex = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 1920, 1080, 1, "Tex"));
			builder.WriteRenderTarget(tex, 0);
		});

		graph.AddPass("ConditionalRead", .Graphics, scope [&] (builder) =>
		{
			builder.ReadTexture(tex, .Fragment);
			builder.HasSideEffects();
			builder.EnableIf(new () => false);
		});

		graph.Compile();

		// Both passes should be scheduled (conditional doesn't affect culling)
		Test.Assert(graph.ScheduledPassCount == 2);
	}

	[Test]
	public static void TestConditionalPassDynamicFlag()
	{
		let graph = scope RenderGraph();
		bool enableDebug = false;
		let order = scope List<String>();

		graph.AddPass("Main", .Graphics, scope [&] (builder) =>
		{
			builder.HasSideEffects();
			builder.SetExecute(new [&] (encoder, registry) =>
			{
				order.Add("Main");
			});
		});

		graph.AddPass("DebugOverlay", .Graphics, scope [&] (builder) =>
		{
			builder.HasSideEffects();
			builder.EnableIf(new [&] () => enableDebug);
			builder.SetExecute(new [&] (encoder, registry) =>
			{
				order.Add("DebugOverlay");
			});
		});

		// First execution: debug disabled
		graph.Compile();
		graph.Execute(null);
		Test.Assert(order.Count == 1);

		// Change flag and re-execute (same compiled graph)
		order.Clear();
		enableDebug = true;
		graph.Execute(null);
		Test.Assert(order.Count == 2);
		Test.Assert(order[1] == "DebugOverlay");
	}

	// =========================================================================
	// Read-Write (UAV) Access
	// =========================================================================

	[Test]
	public static void TestReadWriteStorageTexture()
	{
		let graph = scope RenderGraph();

		RGTexture tex = default;

		graph.AddPass("Init", .Graphics, scope [&] (builder) =>
		{
			tex = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 1920, 1080, 1, "Tex"));
			builder.WriteRenderTarget(tex, 0);
		});

		// Read-write UAV access: reads and modifies in place
		graph.AddPass("Modify", .Compute, scope [&] (builder) =>
		{
			builder.ReadWriteStorage(tex, .Compute);
			builder.HasSideEffects();
		});

		graph.Compile();

		// Should create a dependency: Init → Modify
		Test.Assert(graph.ScheduledPassCount == 2);
		Test.Assert(graph.GetScheduledPass(0).Name == "Init");
		Test.Assert(graph.GetScheduledPass(1).Name == "Modify");

		// Should have a barrier (RenderTarget → ShaderWrite)
		let barriers = graph.GetBarriersForPass(1);
		Test.Assert(barriers.HasValue);
		Test.Assert(barriers.Value.TextureBarriers != null);
		Test.Assert(barriers.Value.TextureBarriers.Count == 1);
		Test.Assert(barriers.Value.TextureBarriers[0].OldState == .RenderTarget);
		Test.Assert(barriers.Value.TextureBarriers[0].NewState == .ShaderWrite);
	}

	[Test]
	public static void TestReadWriteStorageBuffer()
	{
		let graph = scope RenderGraph();

		RGBuffer buf = default;

		graph.AddPass("Init", .Compute, scope [&] (builder) =>
		{
			buf = builder.CreateBuffer(.() { Size = 4096, Usage = .Storage, Name = "Data" });
			builder.WriteStorage(buf, .Compute);
		});

		graph.AddPass("Update", .Compute, scope [&] (builder) =>
		{
			builder.ReadWriteStorage(buf, .Compute);
			builder.HasSideEffects();
		});

		graph.Compile();

		Test.Assert(graph.ScheduledPassCount == 2);
		Test.Assert(graph.GetScheduledPass(0).Name == "Init");
		Test.Assert(graph.GetScheduledPass(1).Name == "Update");
	}

	[Test]
	public static void TestReadWriteCreatesDependency()
	{
		// ReadWriteStorage should create a dependency on the writer even though it's also a write
		let graph = scope RenderGraph();

		RGBuffer buf = default;

		graph.AddPass("Fill", .Compute, scope [&] (builder) =>
		{
			buf = builder.CreateBuffer(.() { Size = 4096, Usage = .Storage, Name = "Particles" });
			builder.WriteStorage(buf, .Compute);
		});

		graph.AddPass("Simulate", .Compute, scope [&] (builder) =>
		{
			builder.ReadWriteStorage(buf, .Compute);
		});

		graph.AddPass("Render", .Graphics, scope [&] (builder) =>
		{
			builder.ReadStorageBuffer(buf, .Vertex);
			builder.HasSideEffects();
		});

		graph.Compile();

		// All three should be scheduled in order
		Test.Assert(graph.ScheduledPassCount == 3);
		Test.Assert(graph.GetScheduledPass(0).Name == "Fill");
		Test.Assert(graph.GetScheduledPass(1).Name == "Simulate");
		Test.Assert(graph.GetScheduledPass(2).Name == "Render");
	}

	[Test]
	public static void TestReadWriteChain()
	{
		// Multiple read-write passes in sequence (e.g., iterative simulation)
		let graph = scope RenderGraph();

		RGBuffer buf = default;

		graph.AddPass("Init", .Compute, scope [&] (builder) =>
		{
			buf = builder.CreateBuffer(.() { Size = 4096, Usage = .Storage, Name = "Sim" });
			builder.WriteStorage(buf, .Compute);
		});

		graph.AddPass("Step1", .Compute, scope [&] (builder) =>
		{
			builder.ReadWriteStorage(buf, .Compute);
		});

		graph.AddPass("Step2", .Compute, scope [&] (builder) =>
		{
			builder.ReadWriteStorage(buf, .Compute);
		});

		graph.AddPass("Visualize", .Graphics, scope [&] (builder) =>
		{
			builder.ReadStorageBuffer(buf, .Fragment);
			builder.HasSideEffects();
		});

		graph.Compile();

		Test.Assert(graph.ScheduledPassCount == 4);
		Test.Assert(graph.GetScheduledPass(0).Name == "Init");
		Test.Assert(graph.GetScheduledPass(1).Name == "Step1");
		Test.Assert(graph.GetScheduledPass(2).Name == "Step2");
		Test.Assert(graph.GetScheduledPass(3).Name == "Visualize");
	}

	// =========================================================================
	// Mipmap Generation
	// =========================================================================

	[Test]
	public static void TestGenerateMipmapsPass()
	{
		let graph = scope RenderGraph();

		RGTexture tex = default;

		graph.AddPass("Render", .Graphics, scope [&] (builder) =>
		{
			tex = builder.CreateTexture(.() {
				Format = .RGBA8Unorm,
				Width = 1024,
				Height = 1024,
				MipLevelCount = 10,
				Name = "Mipmapped"
			});
			builder.WriteRenderTarget(tex, 0);
		});

		graph.AddPass("GenMips", .Graphics, scope [&] (builder) =>
		{
			builder.GenerateMipmaps(tex);
		});

		graph.AddPass("Sample", .Graphics, scope [&] (builder) =>
		{
			builder.ReadTexture(tex, .Fragment);
			builder.HasSideEffects();
		});

		graph.Compile();

		// All three should be scheduled: Render → GenMips → Sample
		Test.Assert(graph.ScheduledPassCount == 3);
		Test.Assert(graph.GetScheduledPass(0).Name == "Render");
		Test.Assert(graph.GetScheduledPass(1).Name == "GenMips");
		Test.Assert(graph.GetScheduledPass(2).Name == "Sample");
	}
}
