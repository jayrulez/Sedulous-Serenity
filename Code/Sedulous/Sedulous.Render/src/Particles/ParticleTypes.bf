namespace Sedulous.Render;

/// Particle simulation backend.
public enum ParticleSimulationBackend : uint8
{
	/// GPU compute shader simulation.
	GPU,

	/// CPU simulation with vertex buffer upload.
	CPU
}
