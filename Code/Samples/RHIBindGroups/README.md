# RHIBindGroups

Demonstrates multiple bind groups and dynamic uniform buffer offsets.

## Features

- Two descriptor sets (Set 0: global, Set 1: per-object)
- Dynamic uniform buffer offsets
- 9 rotating quads in a grid

## Technical Details

- Set 0: Global uniforms (time) - static binding
- Set 1: Per-object uniforms (transform, color) - dynamic offset
- Object uniforms padded to 256 bytes for alignment
- Single uniform buffer holds all 9 objects
- Different dynamic offset per draw call

## Dependencies

- Sedulous.RHI
- RHI.SampleFramework
