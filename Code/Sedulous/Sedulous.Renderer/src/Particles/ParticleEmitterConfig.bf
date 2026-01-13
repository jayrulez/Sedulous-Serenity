namespace Sedulous.Renderer;

using System;
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
		config.SetColorOverLifetime(.(255, 200, 50, 255), .(200, 50, 0, 0));
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
		config.SetColorOverLifetime(.(128, 128, 128, 200), .(64, 64, 64, 0));
		config.SetSizeOverLifetime(1.0f, 4.0f);
		config.SoftParticles = true;
		config.SortParticles = true;
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
		config.SetColorOverLifetime(.(255, 255, 200, 255), .(255, 100, 0, 0));
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
		config.SetColorOverLifetime(.(100, 200, 255, 255), .(200, 100, 255, 0));
		config.SetSizeOverLifetime(1.0f, 0.0f); // Shrink to nothing
		return config;
	}
}
