# RendererStaticMesh

GLTF static mesh loading sample demonstrating textured model rendering with the Sedulous renderer.

## Features

- GLTF model loading using `GltfLoader`
- Textured mesh rendering (Duck model from glTF-Sample-Models)
- Automatic slow rotation animation
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

![RendererStaticMesh Screenshot](screenshot.png)

## Technical Details

- GLTF parsing via `Sedulous.Models.GLTF`
- Texture loading via `SDLImageLoader`
- Vertex format: Position, Normal, TexCoord, Color, Tangent (48 bytes)
- Supports both 16-bit and 32-bit index buffers

## Model Credits

Duck model from [glTF-Sample-Models](https://github.com/KhronosGroup/glTF-Sample-Models) repository.

## Dependencies

- Sedulous.Framework.Renderer
- Sedulous.Geometry
- Sedulous.Imaging
- Sedulous.Models
- Sedulous.Models.GLTF
- SampleFramework
