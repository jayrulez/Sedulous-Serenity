namespace Sedulous.Framework.Render;

using Sedulous.Framework.Scenes;
using Sedulous.Mathematics;
using Sedulous.Render;
using Sedulous.Serialization;

/// Component for particle emitter entities.
/// Stores the core particle emitter configuration for serialization and proxy creation.
struct ParticleEmitterComponent : ISerializableComponent
{
	// Simulation
	public ParticleSimulationBackend Backend;
	public ParticleSpace SimulationSpace;
	public ParticleBlendMode BlendMode;
	public ParticleRenderMode RenderMode;
	public uint32 MaxParticles;
	// Emission
	public float SpawnRate;
	public float ParticleLifetime;
	public int32 BurstCount;
	public float BurstInterval;
	public int32 BurstCycles;
	// Size & color
	public Vector2 StartSize;
	public Vector2 EndSize;
	public Vector4 StartColor;
	public Vector4 EndColor;
	// Motion
	public Vector3 InitialVelocity;
	public Vector3 VelocityRandomness;
	public float GravityMultiplier;
	public float Drag;
	public float VelocityInheritance;
	// Rendering
	public float SoftParticleDistance;
	public float StretchFactor;
	public bool SortParticles;
	public bool Lit;
	// Atlas
	public int32 AtlasColumns;
	public int32 AtlasRows;
	public float AtlasFPS;
	public bool AtlasLoop;
	// General
	public uint32 LayerMask;
	public bool Enabled;

	public int32 SerializationVersion => 2;

	public SerializationResult Serialize(Serializer s) mut
	{
		var version = SerializationVersion;
		s.Version(ref version);
		if (version >= 2)
		{
			s.Enum<ParticleSimulationBackend>("backend", ref Backend);
			s.Enum<ParticleSpace>("simulationSpace", ref SimulationSpace);
			s.Enum<ParticleBlendMode>("blendMode", ref BlendMode);
			s.Enum<ParticleRenderMode>("renderMode", ref RenderMode);
			s.UInt32("maxParticles", ref MaxParticles);
			s.Float("spawnRate", ref SpawnRate);
			s.Float("particleLifetime", ref ParticleLifetime);
			s.Int32("burstCount", ref BurstCount);
			s.Float("burstInterval", ref BurstInterval);
			s.Int32("burstCycles", ref BurstCycles);
			s.FixedFloatArray("startSize", &StartSize.X, 2);
			s.FixedFloatArray("endSize", &EndSize.X, 2);
			s.FixedFloatArray("startColor", &StartColor.X, 4);
			s.FixedFloatArray("endColor", &EndColor.X, 4);
			s.FixedFloatArray("initialVelocity", &InitialVelocity.X, 3);
			s.FixedFloatArray("velocityRandomness", &VelocityRandomness.X, 3);
			s.Float("gravityMultiplier", ref GravityMultiplier);
			s.Float("drag", ref Drag);
			s.Float("velocityInheritance", ref VelocityInheritance);
			s.Float("softParticleDistance", ref SoftParticleDistance);
			s.Float("stretchFactor", ref StretchFactor);
			s.Bool("sortParticles", ref SortParticles);
			s.Bool("lit", ref Lit);
			s.Int32("atlasColumns", ref AtlasColumns);
			s.Int32("atlasRows", ref AtlasRows);
			s.Float("atlasFPS", ref AtlasFPS);
			s.Bool("atlasLoop", ref AtlasLoop);
			s.UInt32("layerMask", ref LayerMask);
			// TODO: Serialize curves (SizeOverLifetime, ColorOverLifetime, etc.)
			// TODO: Serialize ForceModules, SubEmitters, Trail settings
		}
		s.Bool("enabled", ref Enabled);
		return .Ok;
	}

	public static ParticleEmitterComponent Default => .() {
		Backend = .CPU,
		SimulationSpace = .World,
		BlendMode = .Alpha,
		RenderMode = .Billboard,
		MaxParticles = 1000,
		SpawnRate = 10.0f,
		ParticleLifetime = 2.0f,
		BurstCount = 0,
		BurstInterval = 0,
		BurstCycles = 0,
		StartSize = .(0.1f, 0.1f),
		EndSize = .(0.0f, 0.0f),
		StartColor = .(1, 1, 1, 1),
		EndColor = .(1, 1, 1, 0),
		InitialVelocity = .(0, 1, 0),
		VelocityRandomness = .(0.5f, 0.5f, 0.5f),
		GravityMultiplier = 0,
		Drag = 0,
		VelocityInheritance = 0,
		SoftParticleDistance = 0,
		StretchFactor = 0,
		SortParticles = false,
		Lit = false,
		AtlasColumns = 1,
		AtlasRows = 1,
		AtlasFPS = 0,
		AtlasLoop = false,
		LayerMask = 0xFFFFFFFF,
		Enabled = true
	};
}
