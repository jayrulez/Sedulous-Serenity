namespace Sedulous.Render;

using System;

/// Particle simulation backend.
[Reflect]
public enum ParticleSimulationBackend : uint8
{
	/// GPU compute shader simulation.
	GPU,

	/// CPU simulation with vertex buffer upload.
	CPU
}
