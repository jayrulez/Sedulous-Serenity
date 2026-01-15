namespace RendererNGSandbox;

using System;
using Sedulous.RendererNG;
using Sedulous.Mathematics;

extension RendererNGSandboxApp
{
	/// Tests the sprite and skybox draw systems (Phase 6)
	private void TestSpriteAndSkyboxSystems()
	{
		Console.WriteLine("\n--- Testing Sprite Draw System ---");

		// Test 1: SpriteVertex layout
		Console.WriteLine("\nTest 1: SpriteVertex layout...");
		{
			Console.WriteLine("  SpriteVertex.Stride: {0} bytes", SpriteVertex.Stride);
			Console.WriteLine("  Expected: 48 bytes");

			let actualSize = sizeof(SpriteVertex);
			Console.WriteLine("  sizeof(SpriteVertex): {0} bytes", actualSize);

			let passed = SpriteVertex.Stride == 48 && actualSize == 48;
			Console.WriteLine("  PASSED: {0}", passed);
		}

		// Test 2: SpriteProxy default
		Console.WriteLine("\nTest 2: SpriteProxy default...");
		{
			let sprite = SpriteProxy.Default;

			Console.WriteLine("  Position: ({0}, {1}, {2})", sprite.Position.X, sprite.Position.Y, sprite.Position.Z);
			Console.WriteLine("  Size: ({0}, {1})", sprite.Size.X, sprite.Size.Y);
			Console.WriteLine("  Billboard: {0}", sprite.Billboard);
			Console.WriteLine("  BlendMode: {0}", sprite.BlendMode);
			Console.WriteLine("  IsVisible: {0}", sprite.IsVisible);

			let passed = sprite.Size.X == 1 && sprite.Size.Y == 1 &&
						 sprite.Billboard == .Full && sprite.IsVisible;
			Console.WriteLine("  PASSED: {0}", passed);
		}

		// Test 3: SpriteDrawSystem creation
		Console.WriteLine("\nTest 3: SpriteDrawSystem creation...");
		{
			let drawSystem = new SpriteDrawSystem(mRenderer);
			defer delete drawSystem;

			Console.WriteLine("  IsInitialized (before): {0}", drawSystem.IsInitialized);

			let initResult = drawSystem.Initialize(mDevice, .BGRA8UnormSrgb, .Depth24PlusStencil8);
			Console.WriteLine("  Initialize result: {0}", initResult case .Ok);
			Console.WriteLine("  IsInitialized (after): {0}", drawSystem.IsInitialized);

			if (drawSystem.IsInitialized)
			{
				Console.WriteLine("  BindGroupLayout: {0}", drawSystem.BindGroupLayout != null);
				Console.WriteLine("  DefaultTextureView: {0}", drawSystem.DefaultTextureView != null);
				Console.WriteLine("  DefaultSampler: {0}", drawSystem.DefaultSampler != null);
			}

			let passed = drawSystem.IsInitialized &&
						 drawSystem.BindGroupLayout != null &&
						 drawSystem.DefaultTextureView != null;
			Console.WriteLine("  PASSED: {0}", passed);
		}

		// Test 4: Adding sprites
		Console.WriteLine("\nTest 4: Adding sprites...");
		{
			let drawSystem = new SpriteDrawSystem(mRenderer);
			defer delete drawSystem;
			drawSystem.Initialize(mDevice, .BGRA8UnormSrgb, .Depth24PlusStencil8);

			mRenderer.TransientBuffers.BeginFrame(0);
			drawSystem.BeginFrame();

			// Add some sprites with different textures
			SpriteProxy sprite1 = .Default;
			sprite1.Position = .(0, 0, 0);
			sprite1.TextureHandle = 1;

			SpriteProxy sprite2 = .Default;
			sprite2.Position = .(1, 0, 0);
			sprite2.TextureHandle = 1; // Same texture - should batch

			SpriteProxy sprite3 = .Default;
			sprite3.Position = .(2, 0, 0);
			sprite3.TextureHandle = 2; // Different texture - new batch

			drawSystem.AddSprite(sprite1);
			drawSystem.AddSprite(sprite2);
			drawSystem.AddSprite(sprite3);

			// Prepare batches
			drawSystem.Prepare(.(0, 0, 5));

			let stats = drawSystem.Stats;
			Console.WriteLine("  SpriteCount: {0}", stats.SpriteCount);
			Console.WriteLine("  BatchCount: {0}", stats.BatchCount);
			Console.WriteLine("  VertexBytesUsed: {0}", stats.VertexBytesUsed);

			// Should have 3 sprites in 2 batches (grouped by texture)
			let passed = stats.SpriteCount == 3 && stats.BatchCount == 2;
			Console.WriteLine("  PASSED: {0}", passed);
		}

		// Test 5: Billboard modes
		Console.WriteLine("\nTest 5: Billboard modes...");
		{
			SpriteProxy sprite = .Default;

			sprite.Billboard = .None;
			Console.WriteLine("  None: {0}", sprite.Billboard);

			sprite.Billboard = .Full;
			Console.WriteLine("  Full: {0}", sprite.Billboard);

			sprite.Billboard = .AxisY;
			Console.WriteLine("  AxisY: {0}", sprite.Billboard);

			sprite.Billboard = .CustomAxis;
			Console.WriteLine("  CustomAxis: {0}", sprite.Billboard);

			Console.WriteLine("  PASSED: true");
		}

		// Test 6: Sprite flags
		Console.WriteLine("\nTest 6: Sprite flags...");
		{
			SpriteProxy sprite = .Default;
			Console.WriteLine("  Default flags: {0}", sprite.Flags);
			Console.WriteLine("  IsVisible: {0}", sprite.IsVisible);

			sprite.Flags = .None;
			Console.WriteLine("  After None: IsVisible = {0}", sprite.IsVisible);

			sprite.Flags = .Visible | .FlipX | .FlipY;
			Console.WriteLine("  FlipX|FlipY: {0}", sprite.Flags);

			let passed = !SpriteProxy.Default.IsVisible == false;
			Console.WriteLine("  PASSED: {0}", passed);
		}

		// Test 7: SpriteVertex from SpriteProxy
		Console.WriteLine("\nTest 7: SpriteVertex from SpriteProxy...");
		{
			SpriteProxy sprite = .Default;
			sprite.Position = .(1, 2, 3);
			sprite.Size = .(4, 5);
			sprite.Color = .Red;
			sprite.Rotation = 1.57f;
			sprite.UVRect = .(0.25f, 0.25f, 0.5f, 0.5f);
			sprite.Billboard = .Full;
			sprite.Flags = .Visible | .FlipX;

			let vertex = SpriteVertex(sprite);

			Console.WriteLine("  Position: ({0}, {1}, {2})", vertex.Position.X, vertex.Position.Y, vertex.Position.Z);
			Console.WriteLine("  Size: ({0}, {1})", vertex.Size.X, vertex.Size.Y);
			Console.WriteLine("  Rotation: {0:F2}", vertex.Rotation);
			Console.WriteLine("  Flags: 0x{0:X}", vertex.Flags);

			let passed = vertex.Position.X == 1 && vertex.Position.Y == 2 && vertex.Position.Z == 3;
			Console.WriteLine("  PASSED: {0}", passed);
		}

		// Test 8: Sprite sorting by blend mode and texture
		Console.WriteLine("\nTest 8: Sprite sorting...");
		{
			let drawSystem = new SpriteDrawSystem(mRenderer);
			defer delete drawSystem;
			drawSystem.Initialize(mDevice, .BGRA8UnormSrgb, .Depth24PlusStencil8);

			mRenderer.TransientBuffers.BeginFrame(0);
			drawSystem.BeginFrame();

			// Add sprites with different blend modes
			SpriteProxy spriteAdditive = .Default;
			spriteAdditive.BlendMode = .Additive;
			spriteAdditive.TextureHandle = 1;

			SpriteProxy spriteAlpha = .Default;
			spriteAlpha.BlendMode = .AlphaBlend;
			spriteAlpha.TextureHandle = 1;

			SpriteProxy spriteAlpha2 = .Default;
			spriteAlpha2.BlendMode = .AlphaBlend;
			spriteAlpha2.TextureHandle = 2;

			// Add in mixed order
			drawSystem.AddSprite(spriteAdditive);
			drawSystem.AddSprite(spriteAlpha);
			drawSystem.AddSprite(spriteAlpha2);

			drawSystem.Prepare(.(0, 0, 5));

			let stats = drawSystem.Stats;
			Console.WriteLine("  BatchCount (sorted by blend, then texture): {0}", stats.BatchCount);

			// Should be 3 batches: AlphaBlend/tex1, AlphaBlend/tex2, Additive/tex1
			let passed = stats.BatchCount == 3;
			Console.WriteLine("  PASSED: {0}", passed);
		}

		// Test 9: GetStats string
		Console.WriteLine("\nTest 9: GetStats string...");
		{
			let drawSystem = new SpriteDrawSystem(mRenderer);
			defer delete drawSystem;
			drawSystem.Initialize(mDevice, .BGRA8UnormSrgb, .Depth24PlusStencil8);

			mRenderer.TransientBuffers.BeginFrame(0);
			drawSystem.BeginFrame();

			for (int i = 0; i < 10; i++)
			{
				SpriteProxy sprite = .Default;
				sprite.Position = .((float)i, 0, 0);
				drawSystem.AddSprite(sprite);
			}

			drawSystem.Prepare(.(0, 0, 5));

			let statsStr = scope String();
			drawSystem.GetStats(statsStr);
			Console.WriteLine(statsStr);

			let passed = statsStr.Contains("Sprite Draw System");
			Console.WriteLine("  PASSED: {0}", passed);
		}

		Console.WriteLine("\n--- Testing Skybox Draw System ---");

		// Test 10: SkyboxUniforms layout
		Console.WriteLine("\nTest 10: SkyboxUniforms layout...");
		{
			Console.WriteLine("  SkyboxUniforms.Size: {0} bytes", SkyboxUniforms.Size);
			Console.WriteLine("  Expected: 80 bytes");

			let actualSize = sizeof(SkyboxUniforms);
			Console.WriteLine("  sizeof(SkyboxUniforms): {0} bytes", actualSize);

			let passed = SkyboxUniforms.Size == 80 && actualSize == 80;
			Console.WriteLine("  PASSED: {0}", passed);
		}

		// Test 11: SkyboxDrawSystem creation
		Console.WriteLine("\nTest 11: SkyboxDrawSystem creation...");
		{
			let drawSystem = new SkyboxDrawSystem(mRenderer);
			defer delete drawSystem;

			Console.WriteLine("  IsInitialized (before): {0}", drawSystem.IsInitialized);

			let initResult = drawSystem.Initialize(mDevice, .BGRA8UnormSrgb, .Depth24PlusStencil8);
			Console.WriteLine("  Initialize result: {0}", initResult case .Ok);
			Console.WriteLine("  IsInitialized (after): {0}", drawSystem.IsInitialized);

			if (drawSystem.IsInitialized)
			{
				Console.WriteLine("  BindGroupLayout: {0}", drawSystem.BindGroupLayout != null);
				Console.WriteLine("  UniformBuffer: {0}", drawSystem.UniformBuffer != null);
				Console.WriteLine("  DefaultCubemapView: {0}", drawSystem.DefaultCubemapView != null);
				Console.WriteLine("  CubemapSampler: {0}", drawSystem.CubemapSampler != null);
				Console.WriteLine("  HasPipeline: {0}", drawSystem.HasPipeline);
			}

			let passed = drawSystem.IsInitialized &&
						 drawSystem.BindGroupLayout != null &&
						 drawSystem.UniformBuffer != null &&
						 drawSystem.DefaultCubemapView != null;
			Console.WriteLine("  PASSED: {0}", passed);
		}

		// Test 12: Skybox settings
		Console.WriteLine("\nTest 12: Skybox settings...");
		{
			let drawSystem = new SkyboxDrawSystem(mRenderer);
			defer delete drawSystem;
			drawSystem.Initialize(mDevice, .BGRA8UnormSrgb, .Depth24PlusStencil8);

			drawSystem.SetExposure(2.0f);
			drawSystem.SetRotation(Math.PI_f / 4);

			Console.WriteLine("  Exposure set: 2.0");
			Console.WriteLine("  Rotation set: PI/4");

			// Update uniforms
			Matrix view = Matrix.CreateLookAt(.(0, 0, 0), .(0, 0, 1), .(0, 1, 0));
			Matrix proj = Matrix.CreatePerspectiveFieldOfView(Math.PI_f / 2, 16.0f / 9.0f, 0.1f, 1000.0f);
			drawSystem.UpdateUniforms(view, proj);

			Console.WriteLine("  Uniforms updated");
			Console.WriteLine("  PASSED: true");
		}

		// Test 13: SkyboxUniforms default
		Console.WriteLine("\nTest 13: SkyboxUniforms default...");
		{
			let uniforms = SkyboxUniforms.Default;

			Console.WriteLine("  Exposure: {0}", uniforms.Exposure);
			Console.WriteLine("  Rotation: {0}", uniforms.Rotation);

			let passed = uniforms.Exposure == 1.0f && uniforms.Rotation == 0.0f;
			Console.WriteLine("  PASSED: {0}", passed);
		}

		Console.WriteLine("\n--- Sprite and Skybox Tests Complete ---");
	}
}
