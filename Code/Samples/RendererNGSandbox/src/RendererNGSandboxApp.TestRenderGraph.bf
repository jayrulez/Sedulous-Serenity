namespace RendererNGSandbox;

using System;
using Sedulous.RendererNG;
using Sedulous.RHI;
using Sedulous.Mathematics;

extension RendererNGSandboxApp
{
	/// Tests the render graph system (Phase 7)
	private void TestRenderGraph()
	{
		Console.WriteLine("\n--- Testing Render Graph ---");

		// Test 1: RGResourceHandle
		Console.WriteLine("\nTest 1: RGResourceHandle...");
		{
			let invalid = RGResourceHandle.Invalid;
			Console.WriteLine("  Invalid.IsValid: {0}", invalid.IsValid);
			Console.WriteLine("  Invalid.Index: {0}", invalid.Index);

			RGResourceHandle valid = .() { Index = 5, Generation = 1 };
			Console.WriteLine("  Valid.IsValid: {0}", valid.IsValid);
			Console.WriteLine("  Valid.Index: {0}", valid.Index);
			Console.WriteLine("  Valid.Generation: {0}", valid.Generation);

			// Test equality
			RGResourceHandle same = .() { Index = 5, Generation = 1 };
			RGResourceHandle different = .() { Index = 5, Generation = 2 };
			Console.WriteLine("  valid == same: {0}", valid == same);
			Console.WriteLine("  valid == different: {0}", valid == different);

			let passed = !invalid.IsValid && valid.IsValid && valid == same && valid != different;
			Console.WriteLine("  PASSED: {0}", passed);
		}

		// Test 2: PassHandle
		Console.WriteLine("\nTest 2: PassHandle...");
		{
			let invalid = PassHandle.Invalid;
			Console.WriteLine("  Invalid.IsValid: {0}", invalid.IsValid);

			PassHandle valid = .() { Index = 3 };
			Console.WriteLine("  Valid.IsValid: {0}", valid.IsValid);
			Console.WriteLine("  Valid.Index: {0}", valid.Index);

			let passed = !invalid.IsValid && valid.IsValid;
			Console.WriteLine("  PASSED: {0}", passed);
		}

		// Test 3: TextureResourceDesc helpers
		Console.WriteLine("\nTest 3: TextureResourceDesc helpers...");
		{
			let rtDesc = TextureResourceDesc.RenderTarget(1920, 1080, .RGBA8Unorm);
			Console.WriteLine("  RenderTarget: {0}x{1}, format={2}", rtDesc.Width, rtDesc.Height, rtDesc.Format);
			Console.WriteLine("  Usage: {0}", rtDesc.Usage);

			let dsDesc = TextureResourceDesc.DepthStencil(1920, 1080, .Depth24PlusStencil8);
			Console.WriteLine("  DepthStencil: {0}x{1}, format={2}", dsDesc.Width, dsDesc.Height, dsDesc.Format);
			Console.WriteLine("  Usage: {0}", dsDesc.Usage);

			let passed = rtDesc.Width == 1920 && rtDesc.Height == 1080 &&
						 dsDesc.Format == .Depth24PlusStencil8;
			Console.WriteLine("  PASSED: {0}", passed);
		}

		// Test 4: ColorAttachment.Default
		Console.WriteLine("\nTest 4: ColorAttachment.Default...");
		{
			RGResourceHandle handle = .() { Index = 0, Generation = 1 };
			let attachment = ColorAttachment.Default(handle);

			Console.WriteLine("  Handle.Index: {0}", attachment.Handle.Index);
			Console.WriteLine("  LoadOp: {0}", attachment.LoadOp);
			Console.WriteLine("  StoreOp: {0}", attachment.StoreOp);
			Console.WriteLine("  MipLevel: {0}", attachment.MipLevel);

			let passed = attachment.Handle == handle &&
						 attachment.LoadOp == .Clear &&
						 attachment.StoreOp == .Store;
			Console.WriteLine("  PASSED: {0}", passed);
		}

		// Test 5: DepthStencilAttachment.Default
		Console.WriteLine("\nTest 5: DepthStencilAttachment.Default...");
		{
			RGResourceHandle handle = .() { Index = 1, Generation = 1 };
			let attachment = DepthStencilAttachment.Default(handle);

			Console.WriteLine("  Handle.Index: {0}", attachment.Handle.Index);
			Console.WriteLine("  DepthLoadOp: {0}", attachment.DepthLoadOp);
			Console.WriteLine("  DepthStoreOp: {0}", attachment.DepthStoreOp);
			Console.WriteLine("  ClearDepth: {0}", attachment.ClearDepth);
			Console.WriteLine("  ReadOnly: {0}", attachment.ReadOnly);

			let passed = attachment.Handle == handle &&
						 attachment.ClearDepth == 1.0f &&
						 !attachment.ReadOnly;
			Console.WriteLine("  PASSED: {0}", passed);
		}

		// Test 6: RenderGraph creation
		Console.WriteLine("\nTest 6: RenderGraph creation...");
		{
			let graph = new RenderGraph(mDevice);
			defer delete graph;

			Console.WriteLine("  PassCount (initial): {0}", graph.PassCount);
			Console.WriteLine("  ResourceCount (initial): {0}", graph.ResourceCount);

			let passed = graph.PassCount == 0 && graph.ResourceCount == 0;
			Console.WriteLine("  PASSED: {0}", passed);
		}

		// Test 7: Creating transient textures
		Console.WriteLine("\nTest 7: Creating transient textures...");
		{
			let graph = new RenderGraph(mDevice);
			defer delete graph;

			graph.BeginFrame();

			let colorHandle = graph.CreateTexture("ColorBuffer",
				TextureResourceDesc.RenderTarget(1920, 1080, .RGBA8Unorm));
			let depthHandle = graph.CreateTexture("DepthBuffer",
				TextureResourceDesc.DepthStencil(1920, 1080, .Depth24PlusStencil8));

			Console.WriteLine("  ColorBuffer handle valid: {0}", colorHandle.IsValid);
			Console.WriteLine("  DepthBuffer handle valid: {0}", depthHandle.IsValid);
			Console.WriteLine("  ResourceCount: {0}", graph.ResourceCount);

			let passed = colorHandle.IsValid && depthHandle.IsValid && graph.ResourceCount == 2;
			Console.WriteLine("  PASSED: {0}", passed);
		}

		// Test 8: Getting resources by name
		Console.WriteLine("\nTest 8: Getting resources by name...");
		{
			let graph = new RenderGraph(mDevice);
			defer delete graph;

			graph.BeginFrame();

			let original = graph.CreateTexture("MyTexture",
				TextureResourceDesc.RenderTarget(800, 600, .RGBA8Unorm));

			let retrieved = graph.GetResource("MyTexture");
			let notFound = graph.GetResource("NonExistent");

			Console.WriteLine("  Original handle: index={0}, gen={1}", original.Index, original.Generation);
			Console.WriteLine("  Retrieved handle: index={0}, gen={1}", retrieved.Index, retrieved.Generation);
			Console.WriteLine("  NotFound.IsValid: {0}", notFound.IsValid);

			let passed = original == retrieved && !notFound.IsValid;
			Console.WriteLine("  PASSED: {0}", passed);
		}

		// Test 9: Adding graphics passes
		Console.WriteLine("\nTest 9: Adding graphics passes...");
		{
			let graph = new RenderGraph(mDevice);
			defer delete graph;

			graph.BeginFrame();

			let colorTex = graph.CreateTexture("Color",
				TextureResourceDesc.RenderTarget(1920, 1080, .RGBA8Unorm));
			let depthTex = graph.CreateTexture("Depth",
				TextureResourceDesc.DepthStencil(1920, 1080, .Depth24PlusStencil8));

			let builder = graph.AddGraphicsPass("MainPass");
			builder
				.SetColorAttachment(0, colorTex, Color.Blue)
				.SetDepthAttachment(depthTex)
				.SetFlags(.NeverCull);

			Console.WriteLine("  PassCount: {0}", graph.PassCount);
			Console.WriteLine("  Pass handle valid: {0}", builder.Handle.IsValid);

			let passed = graph.PassCount == 1 && builder.Handle.IsValid;
			Console.WriteLine("  PASSED: {0}", passed);
		}

		// Test 10: Adding compute passes
		Console.WriteLine("\nTest 10: Adding compute passes...");
		{
			let graph = new RenderGraph(mDevice);
			defer delete graph;

			graph.BeginFrame();

			let builder = graph.AddComputePass("ComputePass");
			builder.SetFlags(.AsyncCompute);

			Console.WriteLine("  PassCount: {0}", graph.PassCount);

			let passed = graph.PassCount == 1;
			Console.WriteLine("  PASSED: {0}", passed);
		}

		// Test 11: Pass dependencies via resources
		Console.WriteLine("\nTest 11: Pass dependencies...");
		{
			let graph = new RenderGraph(mDevice);
			defer delete graph;

			graph.BeginFrame();

			// Create a texture
			let colorTex = graph.CreateTexture("SharedColor",
				TextureResourceDesc.RenderTarget(1920, 1080, .RGBA8Unorm));

			// Pass 1 writes to texture
			graph.AddGraphicsPass("Pass1")
				.SetColorAttachment(0, colorTex)
				.SetFlags(.NeverCull);

			// Pass 2 reads from texture
			graph.AddGraphicsPass("Pass2")
				.ReadTexture(colorTex)
				.SetFlags(.NeverCull);

			Console.WriteLine("  PassCount: {0}", graph.PassCount);

			let compileResult = graph.Compile();
			Console.WriteLine("  Compile result: {0}", compileResult case .Ok);

			let passed = graph.PassCount == 2 && compileResult case .Ok;
			Console.WriteLine("  PASSED: {0}", passed);
		}

		// Test 12: Pass culling
		Console.WriteLine("\nTest 12: Pass culling...");
		{
			let graph = new RenderGraph(mDevice);
			defer delete graph;

			graph.BeginFrame();

			let unusedTex = graph.CreateTexture("Unused",
				TextureResourceDesc.RenderTarget(256, 256, .RGBA8Unorm));

			// This pass writes to an unused texture, should be culled
			graph.AddGraphicsPass("UnusedPass")
				.SetColorAttachment(0, unusedTex);

			// This pass has NeverCull flag, should not be culled
			graph.AddGraphicsPass("RequiredPass")
				.SetFlags(.NeverCull);

			graph.Compile();

			Console.WriteLine("  PassCount: {0}", graph.PassCount);
			Console.WriteLine("  CulledPassCount: {0}", graph.CulledPassCount);

			// UnusedPass should be culled (1 culled), RequiredPass should not (0 culled of it)
			let passed = graph.CulledPassCount == 1;
			Console.WriteLine("  PASSED: {0}", passed);
		}

		// Test 13: Resource read/write tracking
		Console.WriteLine("\nTest 13: Resource read/write tracking...");
		{
			let graph = new RenderGraph(mDevice);
			defer delete graph;

			graph.BeginFrame();

			let buffer = graph.CreateBuffer("MyBuffer", .() { Size = 1024, Usage = .Storage | .CopyDst });
			Console.WriteLine("  Buffer created: {0}", buffer.IsValid);

			graph.AddComputePass("WritePass")
				.WriteBuffer(buffer)
				.SetFlags(.NeverCull);

			graph.AddComputePass("ReadPass")
				.ReadBuffer(buffer)
				.SetFlags(.NeverCull);

			let compileResult = graph.Compile();
			Console.WriteLine("  Compile result: {0}", compileResult case .Ok);
			Console.WriteLine("  PassCount: {0}", graph.PassCount);

			let passed = compileResult case .Ok;
			Console.WriteLine("  PASSED: {0}", passed);
		}

		// Test 14: Multiple color attachments
		Console.WriteLine("\nTest 14: Multiple color attachments (MRT)...");
		{
			let graph = new RenderGraph(mDevice);
			defer delete graph;

			graph.BeginFrame();

			let albedo = graph.CreateTexture("GBuffer_Albedo",
				TextureResourceDesc.RenderTarget(1920, 1080, .RGBA8Unorm));
			let normal = graph.CreateTexture("GBuffer_Normal",
				TextureResourceDesc.RenderTarget(1920, 1080, .RGBA16Float));
			let depth = graph.CreateTexture("GBuffer_Depth",
				TextureResourceDesc.DepthStencil(1920, 1080, .Depth24PlusStencil8));

			graph.AddGraphicsPass("GBufferPass")
				.SetColorAttachment(0, albedo, Color.Black)
				.SetColorAttachment(1, normal, Color.Black)
				.SetDepthAttachment(depth)
				.SetFlags(.NeverCull);

			let compileResult = graph.Compile();
			Console.WriteLine("  GBuffer pass added");
			Console.WriteLine("  Compile result: {0}", compileResult case .Ok);
			Console.WriteLine("  ResourceCount: {0}", graph.ResourceCount);

			let passed = graph.ResourceCount == 3 && compileResult case .Ok;
			Console.WriteLine("  PASSED: {0}", passed);
		}

		// Test 15: Complex pass chain
		Console.WriteLine("\nTest 15: Complex pass chain...");
		{
			let graph = new RenderGraph(mDevice);
			defer delete graph;

			graph.BeginFrame();

			// Create resources
			let gbufferAlbedo = graph.CreateTexture("GBuffer_Albedo",
				TextureResourceDesc.RenderTarget(1920, 1080, .RGBA8Unorm));
			let gbufferNormal = graph.CreateTexture("GBuffer_Normal",
				TextureResourceDesc.RenderTarget(1920, 1080, .RGBA16Float));
			let gbufferDepth = graph.CreateTexture("GBuffer_Depth",
				TextureResourceDesc.DepthStencil(1920, 1080, .Depth24PlusStencil8));
			let lightingResult = graph.CreateTexture("LightingResult",
				TextureResourceDesc.RenderTarget(1920, 1080, .RGBA16Float));
			let finalOutput = graph.CreateTexture("FinalOutput",
				TextureResourceDesc.RenderTarget(1920, 1080, .RGBA8UnormSrgb));

			// GBuffer pass
			graph.AddGraphicsPass("GBufferPass")
				.SetColorAttachment(0, gbufferAlbedo)
				.SetColorAttachment(1, gbufferNormal)
				.SetDepthAttachment(gbufferDepth)
				.SetFlags(.NeverCull);

			// Lighting pass - reads gbuffer, writes lighting result
			graph.AddGraphicsPass("LightingPass")
				.ReadTexture(gbufferAlbedo)
				.ReadTexture(gbufferNormal)
				.SetDepthAttachmentReadOnly(gbufferDepth)
				.SetColorAttachment(0, lightingResult)
				.SetFlags(.NeverCull);

			// Post-process pass
			graph.AddGraphicsPass("PostProcessPass")
				.ReadTexture(lightingResult)
				.SetColorAttachment(0, finalOutput)
				.SetFlags(.NeverCull);

			let compileResult = graph.Compile();

			Console.WriteLine("  PassCount: {0}", graph.PassCount);
			Console.WriteLine("  ResourceCount: {0}", graph.ResourceCount);
			Console.WriteLine("  Compile result: {0}", compileResult case .Ok);
			Console.WriteLine("  CulledPassCount: {0}", graph.CulledPassCount);

			let passed = graph.PassCount == 3 &&
						 graph.ResourceCount == 5 &&
						 graph.CulledPassCount == 0 &&
						 compileResult case .Ok;
			Console.WriteLine("  PASSED: {0}", passed);
		}

		// Test 16: Frame reset
		Console.WriteLine("\nTest 16: Frame reset...");
		{
			let graph = new RenderGraph(mDevice);
			defer delete graph;

			// First frame
			graph.BeginFrame();
			graph.CreateTexture("Frame1Tex", TextureResourceDesc.RenderTarget(100, 100, .RGBA8Unorm));
			graph.AddGraphicsPass("Frame1Pass").SetFlags(.NeverCull);
			graph.Compile();
			graph.EndFrame();

			Console.WriteLine("  After Frame 1: PassCount={0}, ResourceCount={1}",
				graph.PassCount, graph.ResourceCount);

			// Second frame should start fresh
			graph.BeginFrame();
			Console.WriteLine("  After BeginFrame 2: PassCount={0}", graph.PassCount);

			graph.CreateTexture("Frame2Tex", TextureResourceDesc.RenderTarget(200, 200, .RGBA8Unorm));
			graph.AddGraphicsPass("Frame2Pass").SetFlags(.NeverCull);

			Console.WriteLine("  After adding Frame 2 resources: PassCount={0}",
				graph.PassCount);

			let passed = graph.PassCount == 1;
			Console.WriteLine("  PASSED: {0}", passed);
		}

		Console.WriteLine("\n--- Render Graph Tests Complete ---");
	}
}
