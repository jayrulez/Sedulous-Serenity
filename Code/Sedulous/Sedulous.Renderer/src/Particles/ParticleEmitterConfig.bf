namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.RHI;

typealias ParticleTexture = ITextureView;

/// Configuration for a particle emitter.
/// This class defines all properties that control particle behavior and rendering.
class ParticleEmitterConfig
{
	// ==================== Emission ====================

	/// Particles emitted per second (continuous emission).
	public float EmissionRate = 10;

	/// Number of particles to emit in a burst.
	public int32 BurstCount = 0;

	/// Interval between bursts in seconds (0 = single burst).
	public float BurstInterval = 0;

	/// Shape from which particles are emitted.
	public EmissionShape EmissionShape = .Point;

	/// Maximum number of particles this emitter can have alive at once.
	public int32 MaxParticles = 1000;

	// ==================== Lifetime ====================

	/// Random range for particle lifetime in seconds.
	public RangeFloat Lifetime = .(1, 2);

	// ==================== Initial State ====================

	/// Random range for initial particle speed.
	public RangeFloat InitialSpeed = .(1, 5);

	/// Random range for initial particle size.
	public RangeFloat InitialSize = .(0.1f, 0.5f);

	/// Random range for initial particle rotation in radians.
	public RangeFloat InitialRotation = .(0, Math.PI_f * 2);

	/// Random range for particle rotation speed in radians per second.
	public RangeFloat InitialRotationSpeed = .(0, 0);

	/// Starting color for particles.
	public RangeColor StartColor = .(Color.White);

	/// Ending color for particles (used when ColorOverLifetime is not set).
	public RangeColor EndColor = .(Color.White);

	// ==================== Rendering ====================

	/// How particles are rendered (billboard, stretched, trail, etc.).
	public ParticleRenderMode RenderMode = .Billboard;

	/// Blend mode for particle rendering.
	public ParticleBlendMode BlendMode = .AlphaBlend;

	/// Optional texture for particles (null = use procedural shape).
	public ParticleTexture Texture = null;

	/// Number of rows in the texture atlas (for sprite sheets).
	public int32 TextureSheetRows = 1;

	/// Number of columns in the texture atlas (for sprite sheets).
	public int32 TextureSheetColumns = 1;

	/// Whether to animate through texture sheet frames over particle lifetime.
	public bool AnimateTextureSheet = false;

	/// Starting frame index for texture animation (0-based).
	public int32 StartFrame = 0;

	/// Frame rate for texture animation (frames per second). 0 = spread over lifetime.
	public float AnimationFrameRate = 0;

	/// Sort particles back-to-front for proper alpha blending.
	public bool SortParticles = false;

	// ==================== Physics ====================

	/// Gravity acceleration applied to particles.
	public Vector3 Gravity = .(0, -9.81f, 0);

	/// Drag coefficient (0 = no drag, 1 = full drag).
	public float Drag = 0;

	/// Whether particles inherit velocity from the emitter.
	public bool InheritVelocity = false;

	/// Fraction of emitter velocity to inherit (0-1).
	public float InheritVelocityFactor = 1.0f;

	// ==================== Curves Over Lifetime ====================

	/// Size multiplier curve over particle lifetime (0-1).
	/// If set, overrides linear interpolation between start/end size.
	public ParticleCurveFloat SizeOverLifetime ~ delete _;

	/// Color curve over particle lifetime (0-1).
	/// If set, overrides linear interpolation between start/end color.
	public ParticleCurveColor ColorOverLifetime ~ delete _;

	/// Speed multiplier curve over particle lifetime (0-1).
	/// Multiplies the current velocity magnitude.
	public ParticleCurveFloat SpeedOverLifetime ~ delete _;

	/// Alpha/opacity curve over particle lifetime (0-1).
	/// Applied on top of color alpha.
	public ParticleCurveFloat AlphaOverLifetime ~ delete _;

	// ==================== Trail Settings ====================

	/// Number of trail segments (for Trail render mode).
	public int32 TrailLength = 10;

	/// Minimum distance before adding a new trail vertex.
	public float TrailMinVertexDistance = 0.1f;

	/// Trail width at the head (particle position).
	public float TrailWidthStart = 1.0f;

	/// Trail width at the tail.
	public float TrailWidthEnd = 0.0f;

	/// Per-particle trail settings.
	/// When Enabled is true, each particle leaves a trail behind it.
	public TrailSettings ParticleTrails = .() { Enabled = false };

	/// Maximum age of trail points in seconds.
	public float TrailMaxAge = 1.0f;

	// ==================== Stretched Billboard Settings ====================

	/// Base stretch factor for stretched billboards.
	public float StretchFactor = 1.0f;

	/// Velocity-based length scale (higher = more stretch at high speed).
	public float LengthScale = 1.0f;

	/// Minimum billboard length (prevents zero-length at rest).
	public float MinStretchLength = 0.1f;

	// ==================== Soft Particles ====================

	/// Enable soft particle depth fade (requires depth buffer access).
	public bool SoftParticles = false;

	/// Distance over which particles fade near surfaces.
	public float SoftParticleDistance = 0.5f;

	// ==================== Lighting ====================

	/// Whether particles receive scene lighting.
	public bool LitParticles = false;

	/// Normal bias for lit particles (0 = camera-facing, 1 = velocity-facing).
	public float NormalBias = 0.5f;

	/// Ambient light contribution for lit particles (0-1).
	public float AmbientContribution = 0.3f;

	// ==================== World Space ====================

	/// Whether particles simulate in world space (true) or local space (false).
	public bool WorldSpace = true;

	// ==================== Modules ====================

	/// Particle behavior modules (turbulence, vortex, attractors, etc.).
	/// Modules are executed in order during particle update.
	public List<IParticleModule> Modules ~ DeleteContainerAndItems!(_);

	// ==================== Sub-Emitters ====================

	/// Sub-emitters that spawn child particles on events (birth, death, collision).
	/// Each sub-emitter has its own config and trigger condition.
	public List<SubEmitter> SubEmitters ~ DeleteContainerAndItems!(_);

	// ==================== Methods ====================

	/// Creates a default config.
	public this()
	{
	}

	/// Creates a config with basic settings.
	public this(float emissionRate, RangeFloat lifetime, RangeFloat size)
	{
		EmissionRate = emissionRate;
		Lifetime = lifetime;
		InitialSize = size;
	}

	/// Sets up a size curve that scales from start to end over lifetime.
	public void SetSizeOverLifetime(float startScale, float endScale)
	{
		if (SizeOverLifetime != null)
			delete SizeOverLifetime;
		SizeOverLifetime = ParticleCurveFloat.CreateLinear(startScale, endScale);
	}

	/// Sets up a color curve from start to end over lifetime.
	public void SetColorOverLifetime(Color start, Color end)
	{
		if (ColorOverLifetime != null)
			delete ColorOverLifetime;
		ColorOverLifetime = ParticleCurveColor.CreateLinear(start, end);
	}

	/// Sets up an alpha fade curve over lifetime.
	public void SetAlphaOverLifetime(float startAlpha, float endAlpha)
	{
		if (AlphaOverLifetime != null)
			delete AlphaOverLifetime;
		AlphaOverLifetime = ParticleCurveFloat.CreateLinear(startAlpha, endAlpha);
	}

	/// Configures for additive blend mode (fire, glow, lasers).
	public void SetAdditive()
	{
		BlendMode = .Additive;
		SortParticles = false; // Additive doesn't need sorting
	}

	/// Configures for stretched billboard mode.
	public void SetStretchedBillboard(float stretch = 1.0f, float lengthScale = 1.0f)
	{
		RenderMode = .StretchedBillboard;
		StretchFactor = stretch;
		LengthScale = lengthScale;
	}

	/// Configures for trail/ribbon mode.
	public void SetTrailMode(int32 length = 10, float minDistance = 0.1f)
	{
		RenderMode = .Trail;
		TrailLength = length;
		TrailMinVertexDistance = minDistance;
	}

	/// Enables per-particle trails (each particle leaves a ribbon behind it).
	public void EnableParticleTrails(int32 maxPoints = 20, float minDistance = 0.1f, float maxAge = 1.0f)
	{
		ParticleTrails = .()
		{
			Enabled = true,
			MaxPoints = maxPoints,
			MinVertexDistance = minDistance,
			WidthStart = InitialSize.Min,
			WidthEnd = 0.0f,
			MaxAge = maxAge,
			InheritParticleColor = true
		};
		TrailMaxAge = maxAge;
	}

	/// Enables per-particle trails with custom settings.
	public void EnableParticleTrails(TrailSettings settings)
	{
		ParticleTrails = settings;
		TrailMaxAge = settings.MaxAge;
	}

	/// Adds a particle behavior module.
	public void AddModule(IParticleModule module)
	{
		if (Modules == null)
			Modules = new .();
		Modules.Add(module);
	}

	/// Adds turbulence effect.
	public void AddTurbulence(float strength = 1.0f, float frequency = 1.0f)
	{
		AddModule(new TurbulenceModule(strength, frequency));
	}

	/// Adds a vortex effect.
	public void AddVortex(float strength = 2.0f, Vector3 axis = default)
	{
		AddModule(new VortexModule(strength, axis));
	}

	/// Adds wind effect.
	public void AddWind(Vector3 direction, float turbulence = 0)
	{
		let wind = new WindModule(direction);
		wind.Turbulence = turbulence;
		AddModule(wind);
	}

	/// Adds an attractor point.
	public void AddAttractor(Vector3 position, float strength = 5.0f)
	{
		AddModule(new AttractorModule(position, strength));
	}

	/// Adds a force field module that responds to scene-level force fields.
	public void AddForceFieldResponse(RenderWorld world, float strengthMultiplier = 1.0f)
	{
		let module = new ForceFieldModule(world);
		module.StrengthMultiplier = strengthMultiplier;
		AddModule(module);
	}

	/// Adds a sub-emitter to this config.
	public void AddSubEmitter(SubEmitter subEmitter)
	{
		if (SubEmitters == null)
			SubEmitters = new .();
		SubEmitters.Add(subEmitter);
	}

	/// Adds a sub-emitter that triggers when particles die.
	/// Useful for explosions, impact effects, etc.
	public void AddOnDeathSubEmitter(ParticleEmitterConfig childConfig, int32 emitCount = 10, float probability = 1.0f, bool inheritColor = false)
	{
		let sub = SubEmitter.OnDeath(childConfig, emitCount);
		sub.Probability = probability;
		sub.InheritColor = inheritColor;
		AddSubEmitter(sub);
	}

	/// Adds a sub-emitter that triggers when particles are born.
	/// Useful for spawn effects, trails, etc.
	public void AddOnBirthSubEmitter(ParticleEmitterConfig childConfig, int32 emitCount = 5, float probability = 1.0f, bool inheritColor = false)
	{
		let sub = SubEmitter.OnBirth(childConfig, emitCount);
		sub.Probability = probability;
		sub.InheritColor = inheritColor;
		AddSubEmitter(sub);
	}

	/// Gets sub-emitters for a specific trigger type.
	public void GetSubEmittersForTrigger(SubEmitterTrigger trigger, List<SubEmitter> outList)
	{
		outList.Clear();
		if (SubEmitters == null)
			return;
		for (let sub in SubEmitters)
		{
			if (sub.Trigger == trigger)
				outList.Add(sub);
		}
	}

	/// Returns true if this config has any sub-emitters.
	public bool HasSubEmitters => SubEmitters != null && SubEmitters.Count > 0;

	/// Configures emission from a sphere.
	public void SetSphereEmission(float radius, bool surface = false)
	{
		EmissionShape = Sedulous.Renderer.EmissionShape.Sphere(radius, surface);
	}

	/// Configures emission from a cone.
	public void SetConeEmission(float angle, float radius = 0)
	{
		EmissionShape = Sedulous.Renderer.EmissionShape.Cone(angle, radius);
	}

	/// Configures emission from a box.
	public void SetBoxEmission(Vector3 halfExtents, bool surface = false)
	{
		EmissionShape = Sedulous.Renderer.EmissionShape.Box(halfExtents, surface);
	}

	// ==================== Factory Methods ====================

	/// Creates a fire-like emitter config.
	public static ParticleEmitterConfig CreateFire()
	{
		let config = new ParticleEmitterConfig();
		config.EmissionRate = 50;
		config.Lifetime = .(0.5f, 1.5f);
		config.InitialSpeed = .(2, 5);
		config.InitialSize = .(0.3f, 0.6f);
		config.SetConeEmission(15);
		config.BlendMode = .Additive;
		config.Gravity = .(0, 2, 0); // Rise up
		// End nearly invisible to avoid pop when particle dies
		config.SetColorOverLifetime(.(255, 200, 50, 255), .(200, 50, 0, 2));
		config.SetSizeOverLifetime(1.0f, 2.0f);
		return config;
	}

	/// Creates a smoke-like emitter config.
	public static ParticleEmitterConfig CreateSmoke()
	{
		let config = new ParticleEmitterConfig();
		config.EmissionRate = 10;
		config.Lifetime = .(3, 5);
		config.InitialSpeed = .(0.5f, 1.5f);
		config.InitialSize = .(0.5f, 1.0f);
		config.SetConeEmission(30);
		config.BlendMode = .AlphaBlend;
		config.Gravity = .(0, 0.5f, 0); // Slow rise
		config.Drag = 0.5f;
		config.SetColorOverLifetime(.(128, 128, 128, 200), .(64, 64, 64, 2));
		config.SetSizeOverLifetime(1.0f, 4.0f);
		config.SoftParticles = true;
		config.SortParticles = true;
		config.AddTurbulence(1.5f, 0.5f);
		return config;
	}

	/// Creates a spark-like emitter config.
	public static ParticleEmitterConfig CreateSparks()
	{
		let config = new ParticleEmitterConfig();
		config.EmissionRate = 100;
		config.Lifetime = .(0.2f, 0.8f);
		config.InitialSpeed = .(5, 15);
		config.InitialSize = .(0.02f, 0.05f);
		config.SetSphereEmission(0.1f);
		config.BlendMode = .Additive;
		config.SetStretchedBillboard(2.0f, 0.5f);
		config.Gravity = .(0, -9.81f, 0);
		config.SetColorOverLifetime(.(255, 255, 200, 255), .(255, 100, 0, 2));
		return config;
	}

	/// Creates a magic sparkle emitter config.
	public static ParticleEmitterConfig CreateMagicSparkle()
	{
		let config = new ParticleEmitterConfig();
		config.EmissionRate = 30;
		config.Lifetime = .(0.5f, 1.5f);
		config.InitialSpeed = .(0.5f, 2.0f);
		config.InitialSize = .(0.05f, 0.15f);
		config.SetSphereEmission(0.5f);
		config.BlendMode = .Additive;
		config.Gravity = .(0, 0.5f, 0); // Gentle float up
		config.SetColorOverLifetime(.(100, 200, 255, 255), .(200, 100, 255, 2));
		config.SetSizeOverLifetime(1.0f, 0.0f); // Shrink to nothing
		return config;
	}

	/// Creates a firework emitter with sub-emitter explosion on death.
	/// The main particle rises up and explodes into sparks when it dies.
	/// The explosion inherits the shell's color, so set StartColor before bursting
	/// to create different colored fireworks.
	public static ParticleEmitterConfig CreateFirework()
	{
		let config = new ParticleEmitterConfig();
		// Main rising particle (the "shell")
		config.EmissionRate = 0; // Manual burst only
		config.BurstCount = 1;
		config.Lifetime = .(1.0f, 1.5f);
		config.InitialSpeed = .(15, 20);
		config.InitialSize = .(0.15f, 0.2f);
		config.SetConeEmission(5); // Narrow cone upward
		config.BlendMode = .Additive;
		config.Gravity = .(0, -9.81f, 0);
		// Default color - will be overridden per-burst for variety
		config.StartColor = .(Color(255, 255, 200, 255));
		config.EndColor = .(Color(255, 200, 100, 200));

		// Create explosion sub-emitter config
		// Uses white base color that will be tinted by inherited shell color
		let explosionConfig = new ParticleEmitterConfig();
		explosionConfig.EmissionRate = 0;
		explosionConfig.Lifetime = .(0.5f, 1.5f);
		explosionConfig.InitialSpeed = .(8, 15);
		explosionConfig.InitialSize = .(0.05f, 0.12f);
		explosionConfig.SetSphereEmission(0.1f);
		explosionConfig.BlendMode = .Additive;
		explosionConfig.Gravity = .(0, -5.0f, 0);
		explosionConfig.Drag = 0.3f;
		// White base will be multiplied with inherited parent color
		explosionConfig.StartColor = .(Color(255, 255, 255, 255));
		explosionConfig.EndColor = .(Color(255, 220, 180, 2));
		explosionConfig.SetSizeOverLifetime(1.0f, 0.2f);

		// Add sub-emitter that triggers when main particle dies
		// Enable color inheritance so explosion takes on shell's color
		config.AddOnDeathSubEmitter(explosionConfig, 50, 1.0f, inheritColor: true);

		return config;
	}

	/// Creates a firework burst config (just the explosion, no shell).
	/// Useful for direct spawn of explosion effect.
	public static ParticleEmitterConfig CreateFireworkBurst()
	{
		let config = new ParticleEmitterConfig();
		config.EmissionRate = 0;
		config.BurstCount = 50;
		config.Lifetime = .(0.5f, 1.5f);
		config.InitialSpeed = .(8, 15);
		config.InitialSize = .(0.05f, 0.12f);
		config.SetSphereEmission(0.1f);
		config.BlendMode = .Additive;
		config.Gravity = .(0, -5.0f, 0);
		config.Drag = 0.3f;
		config.SetColorOverLifetime(.(255, 255, 100, 255), .(255, 50, 0, 2));
		config.SetSizeOverLifetime(1.0f, 0.2f);
		return config;
	}

	/// Creates fire with sparks that fly off when particles die.
	public static ParticleEmitterConfig CreateFireWithSparks()
	{
		let config = CreateFire();

		// Create spark sub-emitter config
		let sparkConfig = new ParticleEmitterConfig();
		sparkConfig.EmissionRate = 0;
		sparkConfig.Lifetime = .(0.3f, 0.6f);
		sparkConfig.InitialSpeed = .(3, 8);
		sparkConfig.InitialSize = .(0.02f, 0.04f);
		sparkConfig.SetSphereEmission(0.05f);
		sparkConfig.BlendMode = .Additive;
		sparkConfig.SetStretchedBillboard(1.5f, 0.3f);
		sparkConfig.Gravity = .(0, -9.81f, 0);
		sparkConfig.SetColorOverLifetime(.(255, 255, 200, 255), .(255, 100, 0, 2));

		// 20% chance to spawn sparks when fire particle dies
		config.AddOnDeathSubEmitter(sparkConfig, 3, 0.2f);

		return config;
	}
}
