# RHIWireframe

Demonstrates wireframe rendering mode.

## Features

- FillMode.Wireframe pipeline state
- Toggle between solid and wireframe
- 3D rotating cube

## Controls

| Key | Action |
|-----|--------|
| Space | Toggle wireframe mode |

## Technical Details

- Two pipelines: solid (FillMode.Solid) and wireframe (FillMode.Wireframe)
- Wireframe disables backface culling for visibility
- Colored cube vertices show edge connectivity

## Dependencies

- Sedulous.RHI
- RHI.SampleFramework
