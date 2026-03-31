using System;
using Sedulous.RHI;
using Sedulous.RenderGraph;

namespace Sedulous.RenderGraph.Tests;

class GraphBuilderTests
{
	[Test]
	public static void TestAddPass()
	{
		let graph = scope RenderGraph();

		graph.AddPass("TestPass", .Graphics, scope (builder) =>
		{
			builder.HasSideEffects();
			builder.SetExecute(new (encoder, registry) => { });
		});

		Test.Assert(graph.PassCount == 1);
		Test.Assert(graph.GetPass(0).Name == "TestPass");
		Test.Assert(graph.GetPass(0).QueueType == .Graphics);
		Test.Assert(graph.GetPass(0).HasSideEffects == true);
	}

	[Test]
	public static void TestMultiplePasses()
	{
		let graph = scope RenderGraph();

		graph.AddPass("Pass1", .Graphics, scope (builder) =>
		{
			builder.HasSideEffects();
		});

		graph.AddPass("Pass2", .Compute, scope (builder) =>
		{
			builder.HasSideEffects();
		});

		graph.AddPass("Pass3", .Transfer, scope (builder) =>
		{
			builder.HasSideEffects();
		});

		Test.Assert(graph.PassCount == 3);
		Test.Assert(graph.GetPass(0).QueueType == .Graphics);
		Test.Assert(graph.GetPass(1).QueueType == .Compute);
		Test.Assert(graph.GetPass(2).QueueType == .Transfer);
	}

	[Test]
	public static void TestImportTexture()
	{
		let graph = scope RenderGraph();

		let tex = graph.ImportTexture("Backbuffer", null, null, .Present);

		Test.Assert(tex.IsValid);
		Test.Assert(graph.ResourceCount == 1);
	}

	[Test]
	public static void TestImportBuffer()
	{
		let graph = scope RenderGraph();

		let buf = graph.ImportBuffer("SceneUBO", null, .UniformBuffer);

		Test.Assert(buf.IsValid);
		Test.Assert(graph.ResourceCount == 1);
	}

	[Test]
	public static void TestCreateTransientTexture()
	{
		let graph = scope RenderGraph();

		graph.AddPass("GBuffer", .Graphics, scope (builder) =>
		{
			let albedo = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 1920, 1080, 1, "Albedo"));
			builder.WriteRenderTarget(albedo, 0);
			builder.HasSideEffects();
		});

		Test.Assert(graph.ResourceCount == 1);
		Test.Assert(graph.PassCount == 1);
		// Pass should have 1 access: WriteRenderTarget
		Test.Assert(graph.GetPass(0).Accesses.Count == 1);
	}

	[Test]
	public static void TestCreateTransientBuffer()
	{
		let graph = scope RenderGraph();

		graph.AddPass("Upload", .Transfer, scope (builder) =>
		{
			let buf = builder.CreateBuffer(.() { Size = 4096, Usage = .Storage, Name = "WorkBuffer" });
			builder.WriteStorage(buf, .Compute);
			builder.HasSideEffects();
		});

		Test.Assert(graph.ResourceCount == 1);
		Test.Assert(graph.GetPass(0).Accesses.Count == 1);
	}

	[Test]
	public static void TestPassDependencyDeclaration()
	{
		let graph = scope RenderGraph();

		RGTexture albedo = default;
		RGTexture depth = default;

		graph.AddPass("GBuffer", .Graphics, scope [&] (builder) =>
		{
			albedo = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 1920, 1080, 1, "Albedo"));
			depth = builder.CreateTexture(.DepthBuffer(.Depth32Float, 1920, 1080, 1, "Depth"));
			builder.WriteRenderTarget(albedo, 0);
			builder.WriteDepthStencil(depth);
			builder.HasSideEffects();
		});

		graph.AddPass("Lighting", .Graphics, scope [&] (builder) =>
		{
			builder.ReadTexture(albedo, .Fragment);
			builder.ReadTexture(depth, .Fragment);
			let hdr = builder.CreateTexture(.RenderTarget(.RGBA16Float, 1920, 1080, 1, "HDR"));
			builder.WriteRenderTarget(hdr, 0);
			builder.HasSideEffects();
		});

		Test.Assert(graph.PassCount == 2);
		// GBuffer: 2 accesses (WriteRenderTarget + WriteDepthStencil)
		Test.Assert(graph.GetPass(0).Accesses.Count == 2);
		// Lighting: 3 accesses (ReadTexture x2 + WriteRenderTarget)
		Test.Assert(graph.GetPass(1).Accesses.Count == 3);
	}

	[Test]
	public static void TestRenderTargetSlots()
	{
		let graph = scope RenderGraph();

		graph.AddPass("MRT", .Graphics, scope (builder) =>
		{
			let color0 = builder.CreateTexture(.RenderTarget(.RGBA8Unorm, 1920, 1080, 1, "Color0"));
			let color1 = builder.CreateTexture(.RenderTarget(.RGBA16Float, 1920, 1080, 1, "Color1"));
			builder.WriteRenderTarget(color0, 0);
			builder.WriteRenderTarget(color1, 1);
			builder.HasSideEffects();
		});

		let pass = graph.GetPass(0);
		Test.Assert(pass.RenderTargets.Count == 2);
		Test.Assert(pass.RenderTargets[0].Slot == 0);
		Test.Assert(pass.RenderTargets[1].Slot == 1);
	}

	[Test]
	public static void TestDepthStencilAttachment()
	{
		let graph = scope RenderGraph();

		graph.AddPass("DepthOnly", .Graphics, scope (builder) =>
		{
			let depth = builder.CreateTexture(.DepthBuffer(.Depth32Float, 1920, 1080, 1, "Depth"));
			builder.WriteDepthStencil(depth, .Clear, .Store, 1.0f);
			builder.HasSideEffects();
		});

		let pass = graph.GetPass(0);
		Test.Assert(pass.DepthStencil.HasValue);
		Test.Assert(pass.DepthStencil.Value.DepthLoadOp == .Clear);
		Test.Assert(pass.DepthStencil.Value.DepthStoreOp == .Store);
		Test.Assert(pass.DepthStencil.Value.DepthReadOnly == false);
	}

	[Test]
	public static void TestReadOnlyDepthStencil()
	{
		let graph = scope RenderGraph();

		RGTexture depth = default;

		graph.AddPass("DepthWrite", .Graphics, scope [&] (builder) =>
		{
			depth = builder.CreateTexture(.DepthBuffer(.Depth32Float, 1920, 1080, 1, "Depth"));
			builder.WriteDepthStencil(depth);
			builder.HasSideEffects();
		});

		graph.AddPass("DepthRead", .Graphics, scope [&] (builder) =>
		{
			builder.ReadDepthStencil(depth);
			builder.HasSideEffects();
		});

		let readPass = graph.GetPass(1);
		Test.Assert(readPass.DepthStencil.HasValue);
		Test.Assert(readPass.DepthStencil.Value.DepthReadOnly == true);
	}

	[Test]
	public static void TestReset()
	{
		let graph = scope RenderGraph();

		graph.AddPass("Pass1", .Graphics, scope (builder) =>
		{
			builder.HasSideEffects();
		});

		Test.Assert(graph.PassCount == 1);

		graph.Reset();

		Test.Assert(graph.PassCount == 0);
		Test.Assert(graph.ResourceCount == 0);
		Test.Assert(graph.IsCompiled == false);
	}
}
