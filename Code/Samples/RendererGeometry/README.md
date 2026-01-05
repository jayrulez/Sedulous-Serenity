# RendererGeometry

Basic geometry rendering sample demonstrating procedural mesh creation with the Sedulous renderer.

## Features

- Procedural cube mesh generation using `Mesh.CreateCube()`
- Two rotating cubes with different colors (red and blue)
- Gradient skybox background
- First-person camera controls

## Controls

| Key | Action |
|-----|--------|
| WASD | Move camera |
| Q/E | Move down/up |
| Right-click + Drag | Look around |
| Tab | Toggle mouse capture |
| Shift | Move faster |

## Screenshot

![RendererGeometry Screenshot](screenshot.png)

## Technical Details

- Uses `GPUResourceManager` for mesh creation
- `SkyboxRenderer` for gradient sky cubemap
- Simple vertex/fragment shader with per-object color uniform
- Depth testing enabled

## Dependencies

- Sedulous.Framework.Renderer
- Sedulous.Geometry
- SampleFramework
