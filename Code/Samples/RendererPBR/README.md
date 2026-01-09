# RendererPBR

Physically-based rendering sample with material system.

## Features

- ShaderLibrary for shader management
- GPUResourceManager for mesh/texture upload
- Procedural PBR textures (albedo, normal, metallic/roughness, AO)
- Procedural sphere mesh generation
- Camera with first-person controls

## Controls

| Key | Action |
|-----|--------|
| WASD | Move camera |
| Q/E | Move down/up |
| Right-click + Drag | Look around |
| Tab | Toggle mouse capture |
| Shift | Move faster |

## Technical Details

- PBR material uniforms: base color, metallic, roughness, AO, emissive
- Sphere mesh with 48x24 segments
- View and projection matrices with Vulkan Y-flip
- Depth testing enabled

## Dependencies

- Sedulous.Engine.Renderer
- Sedulous.Geometry
- Sedulous.Imaging
- RHI.SampleFramework
