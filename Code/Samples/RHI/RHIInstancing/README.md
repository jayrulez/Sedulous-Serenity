# RHIInstancing

Demonstrates instanced rendering with many small triangles.

## Features

- Instance buffer with per-instance data
- 100 triangles in a 10x10 grid
- Per-instance color gradient
- Per-instance rotation animation

## Technical Details

- Per-vertex buffer: Position (Float2)
- Per-instance buffer: Offset (Float2) + Color (Float4) + Rotation (Float)
- Single draw call for all 100 instances
- Instance data updated each frame

## Dependencies

- Sedulous.RHI
- RHI.SampleFramework
