# RHICompute

Demonstrates compute shaders for GPU particle simulation.

## Features

- Compute pipeline and shader
- Storage buffer for read/write particle data
- GPU particle physics (position, velocity, bounds)
- Instanced rendering of particles

## Technical Details

- 256 particles simulated on GPU
- Particle struct: Position, Velocity, Color (32 bytes)
- 64 threads per workgroup
- Bouncing off screen edges
- Separate compute and render pipelines

## Dependencies

- Sedulous.RHI
- RHI.SampleFramework
