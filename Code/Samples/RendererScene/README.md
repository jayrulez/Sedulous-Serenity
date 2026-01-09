# RendererScene

Large scene sample demonstrating RenderWorld proxy system and frustum culling.

## Features

- RenderWorld with mesh and light proxies
- VisibilityResolver for frustum culling
- 1200 instanced cubes (20x20x3 grid)
- 16 point lights + directional sun
- Per-instance color via material ID
- First-person camera controls

## Controls

| Key | Action |
|-----|--------|
| WASD | Move camera |
| Q/E | Move down/up |
| Right-click + Drag | Look around |
| Tab | Toggle mouse capture |
| Shift | Move faster |

## Technical Details

- MeshProxy stores transform, bounds, and material slots
- LightProxy for point and directional lights
- CameraProxy tracks view/projection and frustum
- Instance data: Transform (64 bytes) + Color (16 bytes) = 80 bytes
- Single instanced draw call for all visible cubes
- Console output shows visible/culled counts each second

## Dependencies

- Sedulous.Engine.Renderer
- Sedulous.Geometry
- RHI.SampleFramework
