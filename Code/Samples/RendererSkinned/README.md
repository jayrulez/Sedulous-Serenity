# RendererSkinned

Skeletal animation sample demonstrating skinned mesh rendering with the Sedulous renderer.

## Features

- GLTF skeletal mesh loading (Fox model)
- Real-time bone animation playback
- Animation cycling with keyboard controls
- Cached mesh resource serialization for fast loading
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
| Left/Right or ,/. | Cycle through animations |

## Screenshot

![RendererSkinned Screenshot](screenshot.png)

## Technical Details

- GLTF skeleton and animation parsing
- `SkinnedMeshResource` for CPU mesh + skeleton + animations
- `AnimationPlayer` for animation playback and bone matrix calculation
- Skinned vertex format: Position, Normal, TexCoord, Color, Tangent, Joints, Weights (72 bytes)
- Bone matrices uploaded to GPU uniform buffer (128 bones max)
- Resource caching via `ResourceSerializer` for faster subsequent loads

## Model Credits

Fox model from [glTF-Sample-Models](https://github.com/KhronosGroup/glTF-Sample-Models) repository.

## Dependencies

- Sedulous.Engine.Renderer
- Sedulous.Geometry
- Sedulous.Geometry.Tooling
- Sedulous.Imaging
- Sedulous.Models
- Sedulous.Models.GLTF
- Sedulous.Resources
- SampleFramework
