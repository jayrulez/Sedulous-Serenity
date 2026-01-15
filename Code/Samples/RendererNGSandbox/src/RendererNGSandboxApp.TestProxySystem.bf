namespace RendererNGSandbox;

using System;
using Sedulous.Mathematics;
using Sedulous.RendererNG;

extension RendererNGSandboxApp
{
	/// Tests the proxy system (Phase 1.4)
	private void TestProxySystem()
	{
		Console.WriteLine("\n--- Testing Proxy System ---");

		// Test ProxyHandle basics
		Console.WriteLine("\nTesting ProxyHandle<T>...");
		let invalidHandle = ProxyHandle<StaticMeshProxy>.Invalid;
		Console.WriteLine("  Invalid handle: index={0}, gen={1}, HasValidIndex={2}",
			invalidHandle.Index, invalidHandle.Generation, invalidHandle.HasValidIndex);

		// Test RenderWorld static mesh proxies
		Console.WriteLine("\nTesting StaticMeshProxy...");
		let meshHandle1 = mRenderWorld.CreateStaticMesh();
		Console.WriteLine("  Created mesh1: index={0}, gen={1}", meshHandle1.Index, meshHandle1.Generation);

		if (let mesh1 = mRenderWorld.GetStaticMesh(meshHandle1))
		{
			mesh1.Transform = Matrix.CreateTranslation(1.0f, 0.0f, 0.0f);
			mesh1.Flags = .Visible | .CastShadow;
			Console.WriteLine("  Modified mesh1: Position=({0}, {1}, {2})",
				mesh1.Transform.M14, mesh1.Transform.M24, mesh1.Transform.M34);
		}

		// Create second mesh with initial data
		var initialMesh = StaticMeshProxy.Default;
		initialMesh.Transform = Matrix.CreateTranslation(5.0f, 0.0f, 0.0f);
		let meshHandle2 = mRenderWorld.CreateStaticMesh(initialMesh);
		Console.WriteLine("  Created mesh2 with initial data: index={0}", meshHandle2.Index);

		Console.WriteLine("  Static mesh count: {0}", mRenderWorld.StaticMeshCount);

		// Test ForEach iteration
		Console.WriteLine("\nTesting ForEach iteration...");
		int32 meshCount = 0;
		mRenderWorld.ForEachStaticMesh(scope [&meshCount](handle, proxy) => {
			Console.WriteLine("  Iterating mesh: index={0}, visible={1}",
				handle.Index, (proxy.Flags & .Visible) != 0);
			meshCount++;
		});
		Console.WriteLine("  Iterated {0} meshes", meshCount);

		// Test light proxies
		Console.WriteLine("\nTesting LightProxy...");
		let lightHandle = mRenderWorld.CreateLight(LightProxy.DefaultDirectional);
		if (let light = mRenderWorld.GetLight(lightHandle))
		{
			light.Color = .(1.0f, 0.9f, 0.8f);
			light.Intensity = 2.5f;
			Console.WriteLine("  Created directional light: color=({0}, {1}, {2}), intensity={3}",
				light.Color.X, light.Color.Y, light.Color.Z, light.Intensity);
		}

		let pointLightHandle = mRenderWorld.CreateLight(LightProxy.DefaultPoint);
		if (let pointLight = mRenderWorld.GetLight(pointLightHandle))
		{
			pointLight.Position = .(3.0f, 2.0f, 0.0f);
			pointLight.Range = 15.0f;
			Console.WriteLine("  Created point light: range={0}", pointLight.Range);
		}
		Console.WriteLine("  Light count: {0}", mRenderWorld.LightCount);

		// Test camera proxies
		Console.WriteLine("\nTesting CameraProxy...");
		let cameraHandle = mRenderWorld.CreateCamera(CameraProxy.DefaultPerspective);
		if (let camera = mRenderWorld.GetCamera(cameraHandle))
		{
			camera.Position = .(0, 5, 10);
			camera.Forward = Vector3.Normalize(.(0, -0.5f, -1.0f));
			Console.WriteLine("  Created camera: pos=({0}, {1}, {2}), fov={3}",
				camera.Position.X, camera.Position.Y, camera.Position.Z,
				camera.FieldOfView * (180.0f / Math.PI_f));
		}
		Console.WriteLine("  Camera count: {0}", mRenderWorld.CameraCount);

		// Test handle destruction and reuse
		Console.WriteLine("\nTesting handle destruction and generation...");
		let gen1 = meshHandle1.Generation;
		mRenderWorld.DestroyStaticMesh(meshHandle1);
		Console.WriteLine("  Destroyed mesh1, count now: {0}", mRenderWorld.StaticMeshCount);

		// Verify old handle is now invalid
		let oldMesh = mRenderWorld.GetStaticMesh(meshHandle1);
		Console.WriteLine("  Old handle valid: {0}", oldMesh != null);

		// Create new mesh - should reuse slot but with new generation
		let meshHandle3 = mRenderWorld.CreateStaticMesh();
		Console.WriteLine("  Created mesh3: index={0}, gen={1}", meshHandle3.Index, meshHandle3.Generation);
		Console.WriteLine("  Slot reused: {0}, generation incremented: {1}",
			meshHandle3.Index == meshHandle1.Index,
			meshHandle3.Generation > gen1);

		// Test particle emitter proxy
		Console.WriteLine("\nTesting ParticleEmitterProxy...");
		let emitterHandle = mRenderWorld.CreateParticleEmitter(ParticleEmitterProxy.Default);
		if (let emitter = mRenderWorld.GetParticleEmitter(emitterHandle))
		{
			emitter.EmissionRate = 500.0f;
			emitter.MaxParticles = 5000;
			Console.WriteLine("  Created emitter: rate={0}, max={1}", emitter.EmissionRate, emitter.MaxParticles);
		}
		Console.WriteLine("  Particle emitter count: {0}", mRenderWorld.ParticleEmitterCount);

		// Test sprite proxy
		Console.WriteLine("\nTesting SpriteProxy...");
		let spriteHandle = mRenderWorld.CreateSprite(SpriteProxy.Default);
		if (let sprite = mRenderWorld.GetSprite(spriteHandle))
		{
			sprite.Position = .(2.0f, 1.0f, 0.0f);
			sprite.Size = .(1.5f, 1.5f);
			Console.WriteLine("  Created sprite: pos=({0}, {1}, {2}), size=({3}, {4})",
				sprite.Position.X, sprite.Position.Y, sprite.Position.Z,
				sprite.Size.X, sprite.Size.Y);
		}
		Console.WriteLine("  Sprite count: {0}", mRenderWorld.SpriteCount);

		// Test force field proxy
		Console.WriteLine("\nTesting ForceFieldProxy...");
		let windHandle = mRenderWorld.CreateForceField(ForceFieldProxy.DefaultWind);
		if (let wind = mRenderWorld.GetForceField(windHandle))
		{
			wind.Strength = 10.0f;
			wind.Direction = .(1, 0, 0);
			Console.WriteLine("  Created wind force: strength={0}, dir=({1}, {2}, {3})",
				wind.Strength, wind.Direction.X, wind.Direction.Y, wind.Direction.Z);
		}
		Console.WriteLine("  Force field count: {0}", mRenderWorld.ForceFieldCount);

		// Summary
		Console.WriteLine("\nRenderWorld Summary:");
		Console.WriteLine("  Static Meshes: {0}", mRenderWorld.StaticMeshCount);
		Console.WriteLine("  Skinned Meshes: {0}", mRenderWorld.SkinnedMeshCount);
		Console.WriteLine("  Lights: {0}", mRenderWorld.LightCount);
		Console.WriteLine("  Cameras: {0}", mRenderWorld.CameraCount);
		Console.WriteLine("  Particle Emitters: {0}", mRenderWorld.ParticleEmitterCount);
		Console.WriteLine("  Sprites: {0}", mRenderWorld.SpriteCount);
		Console.WriteLine("  Force Fields: {0}", mRenderWorld.ForceFieldCount);

		Console.WriteLine("\nProxy System tests complete!");
	}
}
