namespace Sedulous.Engine.Render;

using System;
using Sedulous.Core.Mathematics;
using Sedulous.Engine.Scenes;
using Sedulous.Render;
using Sedulous.Serialization;

/// Transient data struct for ParticleEmitterComponent serialization/deserialization.
/// Not stored on entities — only used by ParticleEmitterComponentSerializer during save/load.
struct ParticleEmitterComponentData : ISerializableComponentData
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
	// Curves over lifetime
	public ParticleCurveVector2 SizeOverLifetime;
	public ParticleCurveColor ColorOverLifetime;
	public ParticleCurveFloat SpeedOverLifetime;
	public ParticleCurveFloat AlphaOverLifetime;
	public ParticleCurveFloat RotationSpeedOverLifetime;
	// Force modules
	public ParticleForceModules ForceModules;
	// LOD
	public float LODStartDistance;
	public float LODCullDistance;
	public float LODMinRateMultiplier;
	// Lifetime variance
	public float LifetimeVarianceMin;
	public float LifetimeVarianceMax;
	// Trail
	public TrailSettings Trail;
	// Emission shape
	public EmissionShape Shape;
	// Sub-emitter
	public bool SubEmitterOnly;
	// General
	public uint32 LayerMask;
	public bool Enabled;

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

	public void Dispose() mut { }
}
