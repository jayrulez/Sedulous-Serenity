namespace Sedulous.Render;

using System;
using Sedulous.Mathematics;
using Sedulous.Materials;
using Sedulous.RHI;

/// Particle simulation space.
public enum ParticleSpace : uint8
{
	/// Particles simulate in world space.
	World,

	/// Particles simulate relative to emitter.
	Local
}

/// Particle blend mode.
public enum ParticleBlendMode : uint8
{
	/// Standard alpha blending.
	Alpha,

	/// Additive blending.
	Additive,

	/// Premultiplied alpha.
	Premultiplied
}

/// Particle rendering mode.
public enum ParticleRenderMode : uint8
{
	/// Camera-facing billboards.
	Billboard,

	/// Velocity-aligned billboards.
	StretchedBillboard,

	/// Horizontal billboards (facing up).
	HorizontalBillboard,

	/// Mesh particles.
	Mesh
}

/// Proxy for a particle emitter in the render world.
public struct ParticleEmitterProxy
{
	/// Emitter position in world space.
	public Vector3 Position;

	/// Emitter rotation.
	public Quaternion Rotation;

	/// Emitter scale.
	public Vector3 Scale;

	/// Previous frame position (for motion vectors).
	public Vector3 PrevPosition;

	/// Simulation space.
	public ParticleSpace SimulationSpace;

	/// Blend mode.
	public ParticleBlendMode BlendMode;

	/// Render mode.
	public ParticleRenderMode RenderMode;

	/// Handle to the GPU particle buffer.
	public IBuffer ParticleBuffer;

	/// Handle to the GPU indirect draw buffer.
	public IBuffer IndirectBuffer;

	/// Particle texture.
	public ITextureView ParticleTexture;

	/// Material for rendering (optional, for custom shaders).
	public MaterialInstance Material;

	/// Maximum particle count.
	public uint32 MaxParticles;

	/// Current alive particle count (updated by simulation).
	public uint32 AliveCount;

	/// Particles per second spawn rate.
	public float SpawnRate;

	/// Base particle lifetime in seconds.
	public float ParticleLifetime;

	/// Initial particle size.
	public Vector2 StartSize;

	/// End particle size.
	public Vector2 EndSize;

	/// Initial particle color.
	public Vector4 StartColor;

	/// End particle color.
	public Vector4 EndColor;

	/// Initial velocity (in local/world space based on SimulationSpace).
	public Vector3 InitialVelocity;

	/// Velocity randomization range.
	public Vector3 VelocityRandomness;

	/// Gravity multiplier.
	public float GravityMultiplier;

	/// Drag coefficient.
	public float Drag;

	/// Stretch factor for stretched billboards.
	public float StretchFactor;

	/// Sort particles back-to-front (for alpha blending).
	public bool SortParticles;

	/// Whether the emitter is enabled.
	public bool IsEnabled;

	/// Whether the emitter is currently emitting.
	public bool IsEmitting;

	/// Render layer mask.
	public uint32 LayerMask;

	/// Generation counter (for handle validation).
	public uint32 Generation;

	/// Whether this proxy slot is in use.
	public bool IsActive;

	/// Gets the world transform matrix.
	public Matrix GetWorldMatrix()
	{
		return Matrix.CreateScale(Scale) *
			   Matrix.CreateFromQuaternion(Rotation) *
			   Matrix.CreateTranslation(Position);
	}

	/// Updates the emitter position and saves previous.
	public void SetPosition(Vector3 position) mut
	{
		PrevPosition = Position;
		Position = position;
	}

	/// Creates a default particle emitter.
	public static Self CreateDefault()
	{
		var emitter = Self();
		emitter.Position = .Zero;
		emitter.Rotation = .Identity;
		emitter.Scale = .One;
		emitter.PrevPosition = .Zero;
		emitter.SimulationSpace = .World;
		emitter.BlendMode = .Alpha;
		emitter.RenderMode = .Billboard;
		emitter.MaxParticles = 1000;
		emitter.SpawnRate = 100.0f;
		emitter.ParticleLifetime = 2.0f;
		emitter.StartSize = .(0.1f, 0.1f);
		emitter.EndSize = .(0.05f, 0.05f);
		emitter.StartColor = .(1, 1, 1, 1);
		emitter.EndColor = .(1, 1, 1, 0);
		emitter.InitialVelocity = .(0, 1, 0);
		emitter.VelocityRandomness = .(0.5f, 0.5f, 0.5f);
		emitter.GravityMultiplier = 0.0f;
		emitter.Drag = 0.0f;
		emitter.StretchFactor = 1.0f;
		emitter.SortParticles = true;
		emitter.IsEnabled = true;
		emitter.IsEmitting = true;
		emitter.LayerMask = 0xFFFFFFFF;
		return emitter;
	}

	/// Resets the proxy for reuse.
	public void Reset() mut
	{
		Position = .Zero;
		Rotation = .Identity;
		Scale = .One;
		PrevPosition = .Zero;
		SimulationSpace = .World;
		BlendMode = .Alpha;
		RenderMode = .Billboard;
		ParticleBuffer = null;
		IndirectBuffer = null;
		ParticleTexture = null;
		Material = null;
		MaxParticles = 0;
		AliveCount = 0;
		SpawnRate = 0;
		ParticleLifetime = 1.0f;
		StartSize = .(0.1f, 0.1f);
		EndSize = .(0.1f, 0.1f);
		StartColor = .(1, 1, 1, 1);
		EndColor = .(1, 1, 1, 1);
		InitialVelocity = .Zero;
		VelocityRandomness = .Zero;
		GravityMultiplier = 1.0f;
		Drag = 0.0f;
		StretchFactor = 1.0f;
		SortParticles = false;
		IsEnabled = false;
		IsEmitting = false;
		LayerMask = 0xFFFFFFFF;
		IsActive = false;
	}
}
