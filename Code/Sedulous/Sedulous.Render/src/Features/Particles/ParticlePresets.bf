namespace Sedulous.Render;

using System;
using Sedulous.Mathematics;

/// Factory presets for common particle effects.
public static class ParticlePresets
{
	/// Creates a fire emitter configuration.
	/// Upward cone with orange-to-red color, additive blending.
	public static ParticleEmitterProxy Fire(Vector3 position = .Zero, float intensity = 1.0f)
	{
		var emitter = ParticleEmitterProxy.CreateDefault();
		emitter.Position = position;
		emitter.Backend = .CPU;
		emitter.BlendMode = .Additive;
		emitter.SpawnRate = 50 * intensity;
		emitter.ParticleLifetime = 1.0f;
		emitter.StartSize = .(0.15f, 0.15f);
		emitter.EndSize = .(0.02f, 0.02f);
		emitter.StartColor = .(1.0f, 0.6f, 0.1f, 0.9f);
		emitter.EndColor = .(0.8f, 0.1f, 0.0f, 0.0f);
		emitter.InitialVelocity = .(0, 2.0f, 0);
		emitter.VelocityRandomness = .(0.3f, 0.3f, 0.3f);
		emitter.GravityMultiplier = -0.3f; // Slight upward buoyancy
		emitter.Drag = 1.0f;
		emitter.LifetimeVarianceMin = 0.7f;
		emitter.LifetimeVarianceMax = 1.3f;

		// Color curve: bright yellow -> orange -> dark red -> transparent
		emitter.ColorOverLifetime = .();
		emitter.ColorOverLifetime.AddKey(0.0f, .(1.0f, 0.9f, 0.3f, 1.0f));
		emitter.ColorOverLifetime.AddKey(0.3f, .(1.0f, 0.5f, 0.1f, 0.8f));
		emitter.ColorOverLifetime.AddKey(0.7f, .(0.7f, 0.1f, 0.0f, 0.4f));
		emitter.ColorOverLifetime.AddKey(1.0f, .(0.3f, 0.0f, 0.0f, 0.0f));

		// Size peaks then shrinks
		emitter.SizeOverLifetime = .();
		emitter.SizeOverLifetime.AddKey(0.0f, .(0.05f, 0.05f));
		emitter.SizeOverLifetime.AddKey(0.2f, .(0.15f, 0.15f));
		emitter.SizeOverLifetime.AddKey(1.0f, .(0.02f, 0.02f));

		return emitter;
	}

	/// Creates a smoke emitter configuration.
	/// Slow upward drift with gray color, alpha blending.
	public static ParticleEmitterProxy Smoke(Vector3 position = .Zero, float intensity = 1.0f)
	{
		var emitter = ParticleEmitterProxy.CreateDefault();
		emitter.Position = position;
		emitter.Backend = .CPU;
		emitter.BlendMode = .Alpha;
		emitter.SpawnRate = 20 * intensity;
		emitter.ParticleLifetime = 3.0f;
		emitter.StartSize = .(0.1f, 0.1f);
		emitter.EndSize = .(0.5f, 0.5f);
		emitter.StartColor = .(0.4f, 0.4f, 0.4f, 0.6f);
		emitter.EndColor = .(0.3f, 0.3f, 0.3f, 0.0f);
		emitter.InitialVelocity = .(0, 0.8f, 0);
		emitter.VelocityRandomness = .(0.2f, 0.1f, 0.2f);
		emitter.GravityMultiplier = -0.1f;
		emitter.Drag = 0.5f;
		emitter.SortParticles = true;
		emitter.LifetimeVarianceMin = 0.8f;
		emitter.LifetimeVarianceMax = 1.5f;

		// Alpha fades out over lifetime
		emitter.AlphaOverLifetime = .FadeOut(1.0f, 0.5f);

		// Size grows over lifetime
		emitter.SizeOverLifetime = .Linear(.(0.1f, 0.1f), .(0.5f, 0.5f));

		// Slight turbulence for organic movement
		emitter.ForceModules.TurbulenceStrength = 0.5f;
		emitter.ForceModules.TurbulenceFrequency = 1.0f;
		emitter.ForceModules.TurbulenceSpeed = 0.5f;

		return emitter;
	}

	/// Creates a sparks emitter configuration.
	/// Fast particles with gravity, additive blending.
	public static ParticleEmitterProxy Sparks(Vector3 position = .Zero, float intensity = 1.0f)
	{
		var emitter = ParticleEmitterProxy.CreateDefault();
		emitter.Position = position;
		emitter.Backend = .CPU;
		emitter.BlendMode = .Additive;
		emitter.SpawnRate = 30 * intensity;
		emitter.ParticleLifetime = 1.5f;
		emitter.StartSize = .(0.02f, 0.02f);
		emitter.EndSize = .(0.005f, 0.005f);
		emitter.StartColor = .(1.0f, 0.8f, 0.3f, 1.0f);
		emitter.EndColor = .(1.0f, 0.3f, 0.0f, 0.0f);
		emitter.InitialVelocity = .(0, 3.0f, 0);
		emitter.VelocityRandomness = .(2.0f, 1.0f, 2.0f);
		emitter.GravityMultiplier = 1.5f;
		emitter.Drag = 0.2f;
		emitter.RenderMode = .StretchedBillboard;
		emitter.StretchFactor = 2.0f;
		emitter.LifetimeVarianceMin = 0.5f;
		emitter.LifetimeVarianceMax = 1.0f;

		return emitter;
	}

	/// Creates a firework burst configuration.
	/// Single burst that explodes outward from a point.
	public static ParticleEmitterProxy Firework(Vector3 position = .Zero, Vector4 color = .(1, 0.8f, 0.2f, 1))
	{
		var emitter = ParticleEmitterProxy.CreateDefault();
		emitter.Position = position;
		emitter.Backend = .CPU;
		emitter.BlendMode = .Additive;
		emitter.SpawnRate = 0; // No continuous emission
		emitter.BurstCount = 100;
		emitter.BurstInterval = 0; // Single burst
		emitter.BurstCycles = 1;
		emitter.ParticleLifetime = 2.0f;
		emitter.StartSize = .(0.04f, 0.04f);
		emitter.EndSize = .(0.01f, 0.01f);
		emitter.StartColor = color;
		emitter.EndColor = .(color.X * 0.5f, color.Y * 0.5f, color.Z * 0.5f, 0.0f);
		emitter.InitialVelocity = .Zero;
		emitter.VelocityRandomness = .(4.0f, 4.0f, 4.0f);
		emitter.GravityMultiplier = 0.5f;
		emitter.Drag = 0.8f;
		emitter.RenderMode = .StretchedBillboard;
		emitter.StretchFactor = 1.5f;
		emitter.LifetimeVarianceMin = 0.6f;
		emitter.LifetimeVarianceMax = 1.0f;

		// Use sphere emission to get uniform outward burst
		emitter.CPUEmitter?.Shape = .Sphere(0.1f, true);

		// Alpha fades smoothly
		emitter.AlphaOverLifetime = .FadeOut(1.0f, 0.6f);

		return emitter;
	}

	/// Creates a dust/debris emitter configuration.
	/// Low particles that spread outward, alpha blended.
	public static ParticleEmitterProxy Dust(Vector3 position = .Zero, float intensity = 1.0f)
	{
		var emitter = ParticleEmitterProxy.CreateDefault();
		emitter.Position = position;
		emitter.Backend = .CPU;
		emitter.BlendMode = .Alpha;
		emitter.SpawnRate = 15 * intensity;
		emitter.ParticleLifetime = 2.5f;
		emitter.StartSize = .(0.05f, 0.05f);
		emitter.EndSize = .(0.2f, 0.2f);
		emitter.StartColor = .(0.6f, 0.5f, 0.4f, 0.4f);
		emitter.EndColor = .(0.5f, 0.45f, 0.4f, 0.0f);
		emitter.InitialVelocity = .(0, 0.3f, 0);
		emitter.VelocityRandomness = .(0.5f, 0.2f, 0.5f);
		emitter.GravityMultiplier = 0.1f;
		emitter.Drag = 1.5f;
		emitter.SortParticles = true;
		emitter.LifetimeVarianceMin = 0.7f;
		emitter.LifetimeVarianceMax = 1.3f;

		return emitter;
	}

	/// Creates a snow emitter configuration.
	/// Slow falling particles with gentle wind.
	public static ParticleEmitterProxy Snow(Vector3 position = .Zero, float areaSize = 10.0f, float intensity = 1.0f)
	{
		var emitter = ParticleEmitterProxy.CreateDefault();
		emitter.Position = position;
		emitter.Backend = .CPU;
		emitter.BlendMode = .Alpha;
		emitter.SpawnRate = 40 * intensity;
		emitter.ParticleLifetime = 5.0f;
		emitter.StartSize = .(0.03f, 0.03f);
		emitter.EndSize = .(0.03f, 0.03f);
		emitter.StartColor = .(1.0f, 1.0f, 1.0f, 0.8f);
		emitter.EndColor = .(1.0f, 1.0f, 1.0f, 0.0f);
		emitter.InitialVelocity = .(0, -0.5f, 0);
		emitter.VelocityRandomness = .(0.1f, 0.1f, 0.1f);
		emitter.GravityMultiplier = 0.05f;
		emitter.Drag = 2.0f;
		emitter.LifetimeVarianceMin = 0.8f;
		emitter.LifetimeVarianceMax = 1.2f;

		// Emit from a box above the area
		emitter.CPUEmitter?.Shape = .Box(.(areaSize, 0.1f, areaSize));

		// Gentle wind
		emitter.ForceModules.WindForce = .(0.3f, 0, 0.1f);
		emitter.ForceModules.WindTurbulence = 0.2f;

		// Slow rotation
		emitter.RotationSpeedOverLifetime = .Constant(0.5f);

		return emitter;
	}

	/// Creates a rain emitter configuration.
	/// Fast falling stretched particles.
	public static ParticleEmitterProxy Rain(Vector3 position = .Zero, float areaSize = 10.0f, float intensity = 1.0f)
	{
		var emitter = ParticleEmitterProxy.CreateDefault();
		emitter.Position = position;
		emitter.Backend = .CPU;
		emitter.BlendMode = .Alpha;
		emitter.SpawnRate = 200 * intensity;
		emitter.ParticleLifetime = 1.5f;
		emitter.StartSize = .(0.01f, 0.05f);
		emitter.EndSize = .(0.01f, 0.05f);
		emitter.StartColor = .(0.7f, 0.8f, 0.9f, 0.6f);
		emitter.EndColor = .(0.7f, 0.8f, 0.9f, 0.0f);
		emitter.InitialVelocity = .(0, -8.0f, 0);
		emitter.VelocityRandomness = .(0.5f, 1.0f, 0.5f);
		emitter.GravityMultiplier = 1.0f;
		emitter.Drag = 0.0f;
		emitter.RenderMode = .StretchedBillboard;
		emitter.StretchFactor = 3.0f;
		emitter.LifetimeVarianceMin = 0.8f;
		emitter.LifetimeVarianceMax = 1.0f;

		// Emit from a flat box above
		emitter.CPUEmitter?.Shape = .Box(.(areaSize, 0.1f, areaSize));

		return emitter;
	}

	/// Creates a magic/sparkle emitter configuration.
	/// Glowing particles with vortex movement.
	public static ParticleEmitterProxy Magic(Vector3 position = .Zero, Vector4 color = .(0.3f, 0.6f, 1.0f, 1.0f))
	{
		var emitter = ParticleEmitterProxy.CreateDefault();
		emitter.Position = position;
		emitter.Backend = .CPU;
		emitter.BlendMode = .Additive;
		emitter.SpawnRate = 30;
		emitter.ParticleLifetime = 2.0f;
		emitter.StartSize = .(0.05f, 0.05f);
		emitter.EndSize = .(0.0f, 0.0f);
		emitter.StartColor = color;
		emitter.EndColor = .(color.X, color.Y, color.Z, 0.0f);
		emitter.InitialVelocity = .Zero;
		emitter.VelocityRandomness = .(0.5f, 0.5f, 0.5f);
		emitter.GravityMultiplier = -0.2f; // Float upward
		emitter.Drag = 1.0f;
		emitter.LifetimeVarianceMin = 0.7f;
		emitter.LifetimeVarianceMax = 1.3f;

		// Sphere emission
		emitter.CPUEmitter?.Shape = .Sphere(0.5f);

		// Vortex for swirling motion
		emitter.ForceModules.VortexStrength = 2.0f;
		emitter.ForceModules.VortexAxis = .(0, 1, 0);

		// Size pulsing effect via curve
		emitter.SizeOverLifetime = .();
		emitter.SizeOverLifetime.AddKey(0.0f, .(0.02f, 0.02f));
		emitter.SizeOverLifetime.AddKey(0.3f, .(0.06f, 0.06f));
		emitter.SizeOverLifetime.AddKey(0.6f, .(0.03f, 0.03f));
		emitter.SizeOverLifetime.AddKey(1.0f, .(0.0f, 0.0f));

		return emitter;
	}

	/// Creates a steam/mist emitter configuration.
	public static ParticleEmitterProxy Steam(Vector3 position = .Zero, float intensity = 1.0f)
	{
		var emitter = ParticleEmitterProxy.CreateDefault();
		emitter.Position = position;
		emitter.Backend = .CPU;
		emitter.BlendMode = .Alpha;
		emitter.SpawnRate = 10 * intensity;
		emitter.ParticleLifetime = 3.0f;
		emitter.StartSize = .(0.1f, 0.1f);
		emitter.EndSize = .(0.6f, 0.6f);
		emitter.StartColor = .(0.9f, 0.9f, 0.95f, 0.3f);
		emitter.EndColor = .(0.95f, 0.95f, 1.0f, 0.0f);
		emitter.InitialVelocity = .(0, 1.0f, 0);
		emitter.VelocityRandomness = .(0.2f, 0.2f, 0.2f);
		emitter.GravityMultiplier = -0.2f;
		emitter.Drag = 0.8f;
		emitter.SortParticles = true;
		emitter.LifetimeVarianceMin = 0.8f;
		emitter.LifetimeVarianceMax = 1.5f;

		emitter.ForceModules.TurbulenceStrength = 0.3f;
		emitter.ForceModules.TurbulenceFrequency = 0.8f;
		emitter.ForceModules.TurbulenceSpeed = 0.3f;

		return emitter;
	}
}
