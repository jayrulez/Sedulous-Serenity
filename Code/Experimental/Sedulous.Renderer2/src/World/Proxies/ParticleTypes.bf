namespace Sedulous.Renderer;

using Sedulous.Core.Mathematics;

/// Stub types for particle/trail system integration.
/// These will be fully implemented when particle features are ported.

public enum ParticleSimulationBackend : uint8
{
	CPU,
	GPU
}

public class CPUParticleEmitter
{
}

public struct ParticleCurveFloat
{
	public float DefaultValue;
}

public struct ParticleCurveVector2
{
	public Vector2 DefaultValue;
}

public struct ParticleCurveColor
{
	public Color DefaultValue;
}

public struct ParticleForceModules
{
}

public struct SubEmitterEntry
{
}

public static class SubEmitterConstants
{
	public const int32 MaxSubEmitters = 4;
}

public struct TrailSettings
{
	public static Self Default() => .();
}

public struct EmissionShape
{
	public static Self Point() => .();
}

public class TrailEmitter
{
}
