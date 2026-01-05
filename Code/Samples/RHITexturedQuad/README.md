# RHITexturedQuad

Demonstrates textured rendering with the RHI.

## Features

- Texture creation and upload
- Texture views and samplers
- Index buffer for quad rendering
- Procedural checkerboard texture generation

## Technical Details

- Vertex format: Position (Float2) + TexCoord (Float2)
- 256x256 checkerboard texture (RGBA8Unorm)
- Linear filtering sampler with repeat addressing
- Automatic HLSL register binding shifts (b0, t0, s0)

## Dependencies

- Sedulous.RHI
- Sedulous.Imaging
- RHI.SampleFramework
