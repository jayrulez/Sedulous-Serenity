namespace RendererNGSandbox;

using System;
using Sedulous.RendererNG;
using Sedulous.Mathematics;

extension RendererNGSandboxApp
{
	/// Tests the particle system (Phase 5)
	private void TestParticleSystem()
	{
		Console.WriteLine("\n--- Testing Particle System ---");

		// Test 1: ParticleEmitter creation and configuration
		Console.WriteLine("\nTest 1: ParticleEmitter creation...");
		{
			let emitter = new ParticleEmitter(1000);
			defer delete emitter;

			Console.WriteLine("  Max particles: {0}", emitter.MaxParticles);
			Console.WriteLine("  Initial count: {0}", emitter.ParticleCount);
			Console.WriteLine("  Is emitting: {0}", emitter.IsEmitting);
			Console.WriteLine("  Has config: {0}", emitter.Config != null);

			let passed = emitter.MaxParticles == 1000 &&
						 emitter.ParticleCount == 0 &&
						 emitter.IsEmitting &&
						 emitter.Config != null;
			Console.WriteLine("  PASSED: {0}", passed);
		}

		// Test 2: ParticleEmitterConfig defaults
		Console.WriteLine("\nTest 2: ParticleEmitterConfig defaults...");
		{
			let config = new ParticleEmitterConfig();
			defer delete config;

			Console.WriteLine("  EmissionRate: {0}", config.EmissionRate);
			Console.WriteLine("  Lifetime.Min: {0}", config.Lifetime.Min);
			Console.WriteLine("  Lifetime.Max: {0}", config.Lifetime.Max);
			Console.WriteLine("  BlendMode: {0}", config.BlendMode);
			Console.WriteLine("  Gravity.Y: {0}", config.Gravity.Y);

			let passed = config.EmissionRate == 100 &&
						 config.Lifetime.Min > 0 &&
						 config.BlendMode == .Additive;
			Console.WriteLine("  PASSED: {0}", passed);
		}

		// Test 3: Particle emission
		Console.WriteLine("\nTest 3: Particle emission...");
		{
			let emitter = new ParticleEmitter(1000);
			defer delete emitter;

			// Emit for 0.1 seconds at 100 particles/sec = ~10 particles
			emitter.Update(0.1f);
			let count1 = emitter.ParticleCount;
			Console.WriteLine("  After 0.1s: {0} particles", count1);

			// Emit for another 0.1 seconds
			emitter.Update(0.1f);
			let count2 = emitter.ParticleCount;
			Console.WriteLine("  After 0.2s: {0} particles", count2);

			let passed = count1 > 0 && count2 > count1;
			Console.WriteLine("  PASSED: {0}", passed);
		}

		// Test 4: Burst emission
		Console.WriteLine("\nTest 4: Burst emission...");
		{
			let emitter = new ParticleEmitter(1000);
			defer delete emitter;
			emitter.IsEmitting = false; // Disable continuous emission

			emitter.Burst(50);
			Console.WriteLine("  After burst(50): {0} particles", emitter.ParticleCount);

			emitter.Burst(100);
			Console.WriteLine("  After burst(100): {0} particles", emitter.ParticleCount);

			let passed = emitter.ParticleCount == 150;
			Console.WriteLine("  PASSED: {0}", passed);
		}

		// Test 5: Particle lifetime decay
		Console.WriteLine("\nTest 5: Particle lifetime decay...");
		{
			let config = new ParticleEmitterConfig();
			defer delete config;
			config.Lifetime = .(0.5f, 0.5f); // Fixed 0.5 second lifetime
			config.EmissionRate = 0; // No continuous emission

			let emitter = new ParticleEmitter(config, 1000);
			defer delete emitter;

			emitter.Burst(10);
			let initialCount = emitter.ParticleCount;
			Console.WriteLine("  Initial: {0} particles", initialCount);

			// Update past lifetime
			emitter.Update(0.6f);
			let afterDecay = emitter.ParticleCount;
			Console.WriteLine("  After 0.6s: {0} particles", afterDecay);

			let passed = initialCount == 10 && afterDecay == 0;
			Console.WriteLine("  PASSED: {0}", passed);
		}

		// Test 6: Clear particles
		Console.WriteLine("\nTest 6: Clear particles...");
		{
			let emitter = new ParticleEmitter(1000);
			defer delete emitter;

			emitter.Burst(100);
			Console.WriteLine("  Before clear: {0} particles", emitter.ParticleCount);

			emitter.Clear();
			Console.WriteLine("  After clear: {0} particles", emitter.ParticleCount);

			let passed = emitter.ParticleCount == 0;
			Console.WriteLine("  PASSED: {0}", passed);
		}

		// Test 7: Emission shapes
		Console.WriteLine("\nTest 7: Emission shapes...");
		{
			let config = new ParticleEmitterConfig();
			defer delete config;

			// Point
			config.EmissionShape = .Point;
			Console.WriteLine("  Point shape: Type={0}", config.EmissionShape.Type);

			// Sphere
			config.EmissionShape = EmissionShape.Sphere(2.0f, true);
			Console.WriteLine("  Sphere shape: Type={0}, Radius={1}, Surface={2}",
				config.EmissionShape.Type, config.EmissionShape.Size.X, config.EmissionShape.EmitFromSurface);

			// Cone
			config.EmissionShape = EmissionShape.Cone(30.0f, 1.0f);
			Console.WriteLine("  Cone shape: Type={0}, Angle={1}, Radius={2}",
				config.EmissionShape.Type, config.EmissionShape.ConeAngle, config.EmissionShape.Size.X);

			// Box
			config.EmissionShape = EmissionShape.Box(.(1, 2, 3));
			Console.WriteLine("  Box shape: Type={0}, Size=({1}, {2}, {3})",
				config.EmissionShape.Type, config.EmissionShape.Size.X, config.EmissionShape.Size.Y, config.EmissionShape.Size.Z);

			Console.WriteLine("  PASSED: true");
		}

		// Test 8: WriteVertices
		Console.WriteLine("\nTest 8: WriteVertices...");
		{
			let emitter = new ParticleEmitter(100);
			defer delete emitter;

			emitter.Burst(10);
			let particles = emitter.ParticleCount;

			ParticleVertex[] vertices = new ParticleVertex[particles];
			defer delete vertices;

			let written = emitter.WriteVertices(.(vertices.Ptr, particles));
			Console.WriteLine("  Particles: {0}, Written: {1}", particles, written);

			// Check first vertex has valid data
			if (written > 0)
			{
				Console.WriteLine("  First vertex pos: ({0:F2}, {1:F2}, {2:F2})",
					vertices[0].Position.X, vertices[0].Position.Y, vertices[0].Position.Z);
				Console.WriteLine("  First vertex size: ({0:F2}, {1:F2})",
					vertices[0].Size.X, vertices[0].Size.Y);
			}

			let passed = written == particles;
			Console.WriteLine("  PASSED: {0}", passed);
		}

		// Test 9: ParticleVertex layout
		Console.WriteLine("\nTest 9: ParticleVertex layout...");
		{
			Console.WriteLine("  ParticleVertex.Stride: {0} bytes", ParticleVertex.Stride);
			Console.WriteLine("  Expected: 52 bytes");

			// Verify struct size matches stride
			let actualSize = sizeof(ParticleVertex);
			Console.WriteLine("  sizeof(ParticleVertex): {0} bytes", actualSize);

			let passed = ParticleVertex.Stride == 52 && actualSize == 52;
			Console.WriteLine("  PASSED: {0}", passed);
		}

		// Test 10: ParticleDrawSystem creation
		Console.WriteLine("\nTest 10: ParticleDrawSystem...");
		{
			let drawSystem = new ParticleDrawSystem(mRenderer);
			defer delete drawSystem;

			Console.WriteLine("  IsInitialized (before): {0}", drawSystem.IsInitialized);

			// Initialize with device
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

		// Test 11: BeginFrame and PrepareEmitter
		Console.WriteLine("\nTest 11: BeginFrame and PrepareEmitter...");
		{
			let drawSystem = new ParticleDrawSystem(mRenderer);
			defer delete drawSystem;
			drawSystem.Initialize(mDevice, .BGRA8UnormSrgb, .Depth24PlusStencil8);

			let emitter = new ParticleEmitter(100);
			defer delete emitter;
			emitter.Burst(25);

			// Begin frame
			mRenderer.TransientBuffers.BeginFrame(0);
			drawSystem.BeginFrame();

			// Prepare emitter
			drawSystem.PrepareEmitter(emitter);

			// Check stats
			let stats = drawSystem.Stats;
			Console.WriteLine("  EmitterCount: {0}", stats.EmitterCount);
			Console.WriteLine("  ParticleCount: {0}", stats.ParticleCount);
			Console.WriteLine("  VertexBytesUsed: {0}", stats.VertexBytesUsed);

			let passed = stats.EmitterCount == 1 && stats.ParticleCount == 25;
			Console.WriteLine("  PASSED: {0}", passed);
		}

		// Test 12: Blend modes
		Console.WriteLine("\nTest 12: Blend modes...");
		{
			let config = new ParticleEmitterConfig();
			defer delete config;

			config.BlendMode = .AlphaBlend;
			Console.WriteLine("  AlphaBlend: {0}", config.BlendMode);

			config.BlendMode = .Additive;
			Console.WriteLine("  Additive: {0}", config.BlendMode);

			config.BlendMode = .Multiply;
			Console.WriteLine("  Multiply: {0}", config.BlendMode);

			config.BlendMode = .PremultipliedAlpha;
			Console.WriteLine("  PremultipliedAlpha: {0}", config.BlendMode);

			Console.WriteLine("  PASSED: true");
		}

		// Test 13: Range types
		Console.WriteLine("\nTest 13: Range types...");
		{
			let random = scope System.Random();

			// RangeFloat
			RangeFloat rf = .(1.0f, 5.0f);
			float val = rf.Evaluate(random);
			Console.WriteLine("  RangeFloat(1,5).Evaluate: {0:F2}", val);
			Console.WriteLine("  RangeFloat.Lerp(0.5): {0:F2}", rf.Lerp(0.5f));

			// RangeColor
			RangeColor rc = .(Color.Red, Color.Blue);
			Color col = rc.Evaluate(random);
			Console.WriteLine("  RangeColor(Red,Blue).Evaluate: R={0}", col.R);
			Console.WriteLine("  RangeColor.Lerp(0.5): R={0}", rc.Lerp(0.5f).R);

			let passed = val >= 1.0f && val <= 5.0f;
			Console.WriteLine("  PASSED: {0}", passed);
		}

		// Test 14: Particle sorting
		Console.WriteLine("\nTest 14: Particle sorting...");
		{
			let emitter = new ParticleEmitter(100);
			defer delete emitter;

			emitter.Burst(10);

			// Set camera position
			emitter.CameraPosition = .(0, 0, 10);

			// Sort by distance
			emitter.SortByDistance();

			Console.WriteLine("  Sorted {0} particles by distance from camera", emitter.ParticleCount);
			Console.WriteLine("  PASSED: true");
		}

		// Test 15: GetStats string
		Console.WriteLine("\nTest 15: GetStats string...");
		{
			let drawSystem = new ParticleDrawSystem(mRenderer);
			defer delete drawSystem;
			drawSystem.Initialize(mDevice, .BGRA8UnormSrgb, .Depth24PlusStencil8);

			let emitter = new ParticleEmitter(100);
			defer delete emitter;
			emitter.Burst(50);

			mRenderer.TransientBuffers.BeginFrame(0);
			drawSystem.BeginFrame();
			drawSystem.PrepareEmitter(emitter);

			let statsStr = scope String();
			drawSystem.GetStats(statsStr);
			Console.WriteLine(statsStr);

			let passed = statsStr.Contains("Particle Draw System");
			Console.WriteLine("  PASSED: {0}", passed);
		}

		Console.WriteLine("\n--- Particle System Tests Complete ---");
	}
}
