namespace Sedulous.Engine.Renderer;

using System;
using Sedulous.Engine.Core;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.Serialization;

/// Entity component that emits particles.
class ParticleEmitterComponent : IEntityComponent
{
	private Entity mEntity;
	private RenderSceneComponent mRenderScene;
	private ParticleSystem mParticleSystem ~ delete _;

	/// Emitter configuration.
	public ParticleEmitterConfig Config = .Default;

	/// Whether the emitter is actively emitting.
	public bool Emitting = true;

	/// Whether particles are visible.
	public bool Visible = true;

	/// Gets the particle count.
	public int32 ParticleCount => mParticleSystem?.ParticleCount ?? 0;

	/// Gets the underlying particle system.
	public ParticleSystem ParticleSystem => mParticleSystem;

	/// Creates a new ParticleEmitterComponent.
	public this()
	{
	}

	/// Creates a particle emitter with custom config.
	public this(ParticleEmitterConfig config)
	{
		Config = config;
	}

	/// Emits a burst of particles.
	public void Burst(int32 count)
	{
		mParticleSystem?.Burst(count);
	}

	/// Clears all particles.
	public void Clear()
	{
		mParticleSystem?.Clear();
	}

	// ==================== IEntityComponent Implementation ====================

	public void OnAttach(Entity entity)
	{
		mEntity = entity;

		if (entity.Scene != null)
		{
			mRenderScene = entity.Scene.GetSceneComponent<RenderSceneComponent>();
			if (mRenderScene?.RendererService?.Device != null)
			{
				mParticleSystem = new ParticleSystem(mRenderScene.RendererService.Device);
				mParticleSystem.Config = Config;
				mRenderScene.RegisterParticleEmitter(this);
			}
		}
	}

	public void OnDetach()
	{
		mRenderScene?.UnregisterParticleEmitter(this);
		delete mParticleSystem;
		mParticleSystem = null;
		mEntity = null;
		mRenderScene = null;
	}

	public void OnUpdate(float deltaTime)
	{
		if (mParticleSystem == null || !Visible)
			return;

		// Sync config
		mParticleSystem.Config = Config;
		mParticleSystem.IsEmitting = Emitting;

		// Update position from entity transform
		if (mEntity != null)
			mParticleSystem.Position = mEntity.Transform.WorldPosition;

		// Update particles
		mParticleSystem.Update(deltaTime);
	}

	// ==================== ISerializable Implementation ====================

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer serializer)
	{
		var version = SerializationVersion;
		var result = serializer.Version(ref version);
		if (result != .Ok)
			return result;

		// Serialize flags
		int32 flags = (Emitting ? 1 : 0) | (Visible ? 2 : 0);
		result = serializer.Int32("flags", ref flags);
		if (result != .Ok)
			return result;

		if (serializer.IsReading)
		{
			Emitting = (flags & 1) != 0;
			Visible = (flags & 2) != 0;
		}

		// Serialize config
		result = serializer.Float("emissionRate", ref Config.EmissionRate);
		if (result != .Ok) return result;
		result = serializer.Float("minLife", ref Config.MinLife);
		if (result != .Ok) return result;
		result = serializer.Float("maxLife", ref Config.MaxLife);
		if (result != .Ok) return result;
		result = serializer.Float("minSize", ref Config.MinSize);
		if (result != .Ok) return result;
		result = serializer.Float("maxSize", ref Config.MaxSize);
		if (result != .Ok) return result;

		return .Ok;
	}
}
