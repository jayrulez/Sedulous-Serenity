namespace Sedulous.Engine.Renderer;

using System;
using Sedulous.Engine.Core;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.Serialization;
using Sedulous.Renderer;

/// Entity component that emits particles.
/// Uses the proxy pattern to integrate with the render world.
class ParticleEmitterComponent : IEntityComponent
{
	private Entity mEntity;
	private RenderSceneComponent mRenderScene;
	private ParticleSystem mParticleSystem ~ delete _;
	private ProxyHandle mProxyHandle = .Invalid;
	private Vector3 mLastPosition = .Zero;

	/// Emitter configuration (owned by this component).
	public ParticleEmitterConfig Config ~ delete _ ;

	/// Whether the emitter is actively emitting.
	public bool Emitting = true;

	/// Whether particles are visible.
	public bool Visible = true;

	/// Gets the particle count.
	public int32 ParticleCount => mParticleSystem?.ParticleCount ?? 0;

	/// Gets the underlying particle system.
	public ParticleSystem ParticleSystem => mParticleSystem;

	/// Gets the proxy handle for this emitter.
	public ProxyHandle ProxyHandle => mProxyHandle;

	/// Gets whether the emitter has been initialized.
	public bool IsInitialized => mParticleSystem != null;

	/// Creates a new ParticleEmitterComponent with default configuration.
	public this()
	{
		Config = new ParticleEmitterConfig();
	}

	/// Creates a particle emitter with custom config (takes ownership).
	public this(ParticleEmitterConfig config)
	{
		Config = config ?? new ParticleEmitterConfig();
	}

	// ==================== Configuration Helpers ====================

	/// Sets up a fire-like effect.
	public void ConfigureAsFire()
	{
		if (Config != null) delete Config;
		Config = ParticleEmitterConfig.CreateFire();
	}

	/// Sets up a smoke-like effect.
	public void ConfigureAsSmoke()
	{
		if (Config != null) delete Config;
		Config = ParticleEmitterConfig.CreateSmoke();
	}

	/// Sets up a spark effect.
	public void ConfigureAsSparks()
	{
		if (Config != null) delete Config;
		Config = ParticleEmitterConfig.CreateSparks();
	}

	/// Sets up a magic sparkle effect.
	public void ConfigureAsMagicSparkle()
	{
		if (Config != null) delete Config;
		Config = ParticleEmitterConfig.CreateMagicSparkle();
	}

	// ==================== Control Methods ====================

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

	/// Starts emitting particles.
	public void StartEmitting()
	{
		Emitting = true;
		if (mParticleSystem != null)
			mParticleSystem.IsEmitting = true;
	}

	/// Stops emitting new particles (existing particles continue).
	public void StopEmitting()
	{
		Emitting = false;
		if (mParticleSystem != null)
			mParticleSystem.IsEmitting = false;
	}

	/// Stops emitting and clears all particles.
	public void Stop()
	{
		StopEmitting();
		Clear();
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
				// Create particle system with the config (config ownership stays with component)
				mParticleSystem = new ParticleSystem(mRenderScene.RendererService.Device, Config, Config.MaxParticles);
				mParticleSystem.IsEmitting = Emitting;
				mLastPosition = entity.Transform.WorldPosition;
				mParticleSystem.Position = mLastPosition;

				CreateOrUpdateProxy();
				mRenderScene.RegisterParticleEmitter(this);
			}
		}
	}

	public void OnDetach()
	{
		mRenderScene?.UnregisterParticleEmitter(this);
		DestroyProxy();
		delete mParticleSystem;
		mParticleSystem = null;
		mEntity = null;
		mRenderScene = null;
	}

	public void OnUpdate(float deltaTime)
	{
		if (mParticleSystem == null)
			return;

		// Sync emitting state
		mParticleSystem.IsEmitting = Emitting;

		// Update position from entity transform
		if (mEntity != null)
		{
			Vector3 newPosition = mEntity.Transform.WorldPosition;

			// Calculate velocity for emitter (for velocity inheritance)
			if (deltaTime > 0.0001f)
			{
				Vector3 velocity = (newPosition - mLastPosition) / deltaTime;
				mParticleSystem.Velocity = velocity;
			}

			mParticleSystem.Position = newPosition;
			mLastPosition = newPosition;
		}

		// Set camera position for LOD and sorting (needed before Update)
		if (mRenderScene?.RenderWorld != null)
		{
			if (let camera = mRenderScene.RenderWorld.MainCamera)
				mParticleSystem.CameraPosition = camera.Position;
		}

		// Update particles
		mParticleSystem.Update(deltaTime);

		// Upload to GPU (camera position already set above)
		mParticleSystem.Upload();

		// Update proxy state
		CreateOrUpdateProxy();
	}

	// ==================== ISerializable Implementation ====================

	public int32 SerializationVersion => 2;

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

		// Serialize basic config values
		float emissionRate = Config.EmissionRate;
		result = serializer.Float("emissionRate", ref emissionRate);
		if (result != .Ok) return result;
		if (serializer.IsReading) Config.EmissionRate = emissionRate;

		float lifetimeMin = Config.Lifetime.Min;
		float lifetimeMax = Config.Lifetime.Max;
		result = serializer.Float("lifetimeMin", ref lifetimeMin);
		if (result != .Ok) return result;
		result = serializer.Float("lifetimeMax", ref lifetimeMax);
		if (result != .Ok) return result;
		if (serializer.IsReading) Config.Lifetime = .(lifetimeMin, lifetimeMax);

		float sizeMin = Config.InitialSize.Min;
		float sizeMax = Config.InitialSize.Max;
		result = serializer.Float("sizeMin", ref sizeMin);
		if (result != .Ok) return result;
		result = serializer.Float("sizeMax", ref sizeMax);
		if (result != .Ok) return result;
		if (serializer.IsReading) Config.InitialSize = .(sizeMin, sizeMax);

		float speedMin = Config.InitialSpeed.Min;
		float speedMax = Config.InitialSpeed.Max;
		result = serializer.Float("speedMin", ref speedMin);
		if (result != .Ok) return result;
		result = serializer.Float("speedMax", ref speedMax);
		if (result != .Ok) return result;
		if (serializer.IsReading) Config.InitialSpeed = .(speedMin, speedMax);

		// Gravity
		Vector3 gravity = Config.Gravity;
		result = serializer.Float("gravityX", ref gravity.X);
		if (result != .Ok) return result;
		result = serializer.Float("gravityY", ref gravity.Y);
		if (result != .Ok) return result;
		result = serializer.Float("gravityZ", ref gravity.Z);
		if (result != .Ok) return result;
		if (serializer.IsReading) Config.Gravity = gravity;

		// Blend mode
		int32 blendMode = (int32)Config.BlendMode;
		result = serializer.Int32("blendMode", ref blendMode);
		if (result != .Ok) return result;
		if (serializer.IsReading) Config.BlendMode = (ParticleBlendMode)blendMode;

		// Render mode
		int32 renderMode = (int32)Config.RenderMode;
		result = serializer.Int32("renderMode", ref renderMode);
		if (result != .Ok) return result;
		if (serializer.IsReading) Config.RenderMode = (ParticleRenderMode)renderMode;

		return .Ok;
	}

	// ==================== Internal ====================

	private void CreateOrUpdateProxy()
	{
		if (mRenderScene == null || mEntity == null)
			return;

		// Create proxy if needed
		if (!mProxyHandle.IsValid && mParticleSystem != null)
		{
			mProxyHandle = mRenderScene.CreateParticleEmitterProxy(
				mEntity.Id, mParticleSystem, mEntity.Transform.WorldPosition);
		}

		// Update proxy state
		if (mRenderScene.RenderWorld != null)
		{
			if (let proxy = mRenderScene.RenderWorld.GetParticleEmitterProxy(mProxyHandle))
			{
				float boundsRadius = EstimateBoundsRadius();
				proxy.SetPosition(mEntity.Transform.WorldPosition, boundsRadius);
				proxy.System = mParticleSystem;

				// Update flags based on component state
				ParticleEmitterProxyFlags newFlags = .None;

				if (Visible)
					newFlags |= .Visible;
				if (Emitting)
					newFlags |= .Emitting;
				if (Config.SoftParticles)
					newFlags |= .SoftParticles;
				if (Config.WorldSpace)
					newFlags |= .WorldSpace;
				if (Config.LitParticles)
					newFlags |= .AffectsLighting;

				proxy.Flags = newFlags;
			}
		}
	}

	private float EstimateBoundsRadius()
	{
		// Estimate bounds based on particle lifetime and speed
		float maxSpeed = Config.InitialSpeed.Max;
		float maxLife = Config.Lifetime.Max;
		float maxSize = Config.InitialSize.Max;

		// Account for gravity influence
		float gravityMag = Config.Gravity.Length();
		float gravityContribution = 0.5f * gravityMag * maxLife * maxLife;

		// Rough estimate of particle spread
		return Math.Max(5.0f, maxSpeed * maxLife + gravityContribution + maxSize * 2);
	}

	private void DestroyProxy()
	{
		if (mRenderScene != null && mEntity != null)
		{
			mRenderScene.DestroyParticleEmitterProxy(mEntity.Id);
		}
		mProxyHandle = .Invalid;
	}
}
