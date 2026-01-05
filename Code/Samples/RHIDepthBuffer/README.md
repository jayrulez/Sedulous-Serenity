# RHIDepthBuffer

Demonstrates depth buffer functionality with overlapping quads.

## Features

- Depth texture creation
- Depth testing with Less compare function
- 3D perspective projection
- Overlapping geometry at different Z depths

## Technical Details

- Depth format: Depth24PlusStencil8
- Two quads: red (front, z=0) and blue (back, z=0.5)
- Rotating around Y axis to show depth occlusion
- Vulkan Y-flip applied to projection matrix

## Dependencies

- Sedulous.RHI
- RHI.SampleFramework
