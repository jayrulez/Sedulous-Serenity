namespace Sedulous.Engine.Render;

using System;
using Sedulous.Engine.Scenes;
using Sedulous.Foundation.Mathematics;
using Sedulous.Render;
using Sedulous.Serialization;

/// Component for particle emitter entities.
/// Stores the core particle emitter configuration for serialization and proxy creation.
[Component]
struct ParticleEmitterComponent : ISerializableComponent
{
	// Simulation
	[Property] public ParticleSimulationBackend Backend;
	[Property] public ParticleSpace SimulationSpace;
	[Property] public ParticleBlendMode BlendMode;
	[Property] public ParticleRenderMode RenderMode;
	[Property] public uint32 MaxParticles;
	// Emission
	[Property] public float SpawnRate;
	[Property] public float ParticleLifetime;
	[Property] public int32 BurstCount;
	[Property] public float BurstInterval;
	[Property] public int32 BurstCycles;
	// Size & color
	[Property] public Vector2 StartSize;
	[Property] public Vector2 EndSize;
	[Property] public Vector4 StartColor;
	[Property] public Vector4 EndColor;
	// Motion
	[Property] public Vector3 InitialVelocity;
	[Property] public Vector3 VelocityRandomness;
	[Property] public float GravityMultiplier;
	[Property] public float Drag;
	[Property] public float VelocityInheritance;
	// Rendering
	[Property] public float SoftParticleDistance;
	[Property] public float StretchFactor;
	[Property] public bool SortParticles;
	[Property] public bool Lit;
	// Atlas
	[Property] public int32 AtlasColumns;
	[Property] public int32 AtlasRows;
	[Property] public float AtlasFPS;
	[Property] public bool AtlasLoop;
	// Curves over lifetime (complex types, no [Property] — need custom editors)
	public ParticleCurveVector2 SizeOverLifetime;
	public ParticleCurveColor ColorOverLifetime;
	public ParticleCurveFloat SpeedOverLifetime;
	public ParticleCurveFloat AlphaOverLifetime;
	public ParticleCurveFloat RotationSpeedOverLifetime;
	// Force modules (complex struct, no [Property])
	public ParticleForceModules ForceModules;
	// LOD
	[Property] public float LODStartDistance;
	[Property] public float LODCullDistance;
	[Property] public float LODMinRateMultiplier;
	// Lifetime variance
	[Property] public float LifetimeVarianceMin;
	[Property] public float LifetimeVarianceMax;
	// Trail (nested struct, no [Property])
	public TrailSettings Trail;
	// Emission shape (nested struct, no [Property])
	public EmissionShape Shape;
	// Sub-emitter
	[Property] public bool SubEmitterOnly;
	// General
	[Property] public uint32 LayerMask;
	[Property] public bool Enabled;

	public void Dispose() mut { }

	public int32 SerializationVersion => 2;

	public SerializationResult Serialize(Serializer s) mut
	{
		var version = SerializationVersion;
		s.Version(ref version);
		if (version < 2)
			return .Ok;
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
		// Curves — [CRepr] structs with contiguous float layout
		SerializeCurveFloat(s, "sizeOverLifetimeKeys", "sizeOverLifetimeTimes", "sizeOverLifetimeValues", "sizeOverLifetimeTangentsIn", "sizeOverLifetimeTangentsOut", "sizeOverLifetimeKeyCount", ref SizeOverLifetime);
		SerializeCurveColor(s, "colorOverLifetimeKeys", "colorOverLifetimeKeyCount", ref ColorOverLifetime);
		SerializeCurveFloat(s, "speedOverLifetime", "speedOverLifetimeKeyCount", ref SpeedOverLifetime);
		SerializeCurveFloat(s, "alphaOverLifetime", "alphaOverLifetimeKeyCount", ref AlphaOverLifetime);
		SerializeCurveFloat(s, "rotationSpeedOverLifetime", "rotationSpeedOverLifetimeKeyCount", ref RotationSpeedOverLifetime);
		// Force modules — [CRepr] struct, 20 contiguous floats
		s.FixedFloatArray("forceModules", &ForceModules.TurbulenceStrength, 20);
		// LOD
		s.Float("lodStartDistance", ref LODStartDistance);
		s.Float("lodCullDistance", ref LODCullDistance);
		s.Float("lodMinRateMultiplier", ref LODMinRateMultiplier);
		// Lifetime variance
		s.Float("lifetimeVarianceMin", ref LifetimeVarianceMin);
		s.Float("lifetimeVarianceMax", ref LifetimeVarianceMax);
		// Trail
		s.Bool("trailEnabled", ref Trail.Enabled);
		s.Int32("trailMaxPoints", ref Trail.MaxPoints);
		s.Float("trailRecordInterval", ref Trail.RecordInterval);
		s.Float("trailLifetime", ref Trail.Lifetime);
		s.Float("trailWidthStart", ref Trail.WidthStart);
		s.Float("trailWidthEnd", ref Trail.WidthEnd);
		s.Float("trailMinVertexDistance", ref Trail.MinVertexDistance);
		s.Bool("trailUseParticleColor", ref Trail.UseParticleColor);
		s.FixedFloatArray("trailColor", &Trail.TrailColor.X, 4);
		// Emission shape
		var shapeType = (uint8)Shape.Type;
		s.UInt8("shapeType", ref shapeType);
		Shape.Type = (EmissionShapeType)shapeType;
		s.FixedFloatArray("shapeSize", &Shape.Size.X, 3);
		s.Float("shapeConeAngle", ref Shape.ConeAngle);
		s.Float("shapeArc", ref Shape.Arc);
		s.Bool("shapeEmitFromSurface", ref Shape.EmitFromSurface);
		// Sub-emitter
		s.Bool("subEmitterOnly", ref SubEmitterOnly);
		// General
		s.UInt32("layerMask", ref LayerMask);
		s.Bool("enabled", ref Enabled);
		return .Ok;
	}

	// Helpers for serializing [CRepr] curve structs as flat float arrays

	private static void SerializeCurveFloat(Serializer s, StringView keysName, StringView keyCountName, ref ParticleCurveFloat curve)
	{
		// CurveKeyFloat is 4 floats (Time, Value, TangentIn, TangentOut), 8 keys = 32 floats
		s.FixedFloatArray(keysName, &curve.Keys[0].Time, 32);
		s.Int32(keyCountName, ref curve.KeyCount);
	}

	private static void SerializeCurveFloat(Serializer s, StringView keysName, StringView timesName, StringView valuesName, StringView tangentsInName, StringView tangentsOutName, StringView keyCountName, ref ParticleCurveVector2 curve)
	{
		// ParticleCurveVector2 has separate arrays
		s.FixedFloatArray(timesName, &curve.Times[0], 8);
		s.FixedFloatArray(valuesName, &curve.Values[0].X, 16);
		s.FixedFloatArray(tangentsInName, &curve.TangentsIn[0].X, 16);
		s.FixedFloatArray(tangentsOutName, &curve.TangentsOut[0].X, 16);
		s.Int32(keyCountName, ref curve.KeyCount);
	}

	private static void SerializeCurveColor(Serializer s, StringView keysName, StringView keyCountName, ref ParticleCurveColor curve)
	{
		// CurveKeyColor is 5 floats (Time, Color.XYZW), 8 keys = 40 floats
		s.FixedFloatArray(keysName, &curve.Keys[0].Time, 40);
		s.Int32(keyCountName, ref curve.KeyCount);
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
		SizeOverLifetime = default,
		ColorOverLifetime = default,
		SpeedOverLifetime = default,
		AlphaOverLifetime = default,
		RotationSpeedOverLifetime = default,
		ForceModules = default,
		LODStartDistance = 0,
		LODCullDistance = 0,
		LODMinRateMultiplier = 0,
		LifetimeVarianceMin = 1.0f,
		LifetimeVarianceMax = 1.0f,
		Trail = .Default(),
		Shape = EmissionShape.Point(),
		SubEmitterOnly = false,
		LayerMask = 0xFFFFFFFF,
		Enabled = true
	};
}
