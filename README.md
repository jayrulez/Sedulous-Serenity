# Sedulous

A modular game framework for the [Beef programming language](https://www.beeflang.org/).

## Overview

Sedulous is a layered game framework featuring:

- **RHI (Rendering Hardware Interface)** - Cross-platform graphics abstraction with Vulkan backend
- **Framework.Renderer** - High-level rendering with clustered lighting, PBR materials, and shadow mapping
- **Framework.Audio** - Audio system with SDL3_mixer implementation
- **Framework.Core** - ECS, scenes, and context management
- **Resources** - Async resource loading with caching
- **Jobs** - Multi-threaded job system
- **Geometry/Models** - Mesh generation and GLTF model loading

## Building

Requirements:
- [Beef IDE](https://www.beeflang.org/) or BeefBuild CLI
- Vulkan SDK (for RHI.Vulkan backend)

```bash
# Build the workspace
BeefBuild.exe -workspace=Code/ -verbosity=normal

# Build release configuration
BeefBuild.exe -workspace=Code/ -config=Release

# Run tests
BeefBuild.exe -workspace=Code/ -test
```

## Project Structure

```
Sedulous-Serenity/
├── Code/
│   ├── BeefSpace.toml          # Workspace configuration
│   ├── Dependencies/           # Third-party bindings
│   │   ├── Bulkan/             # Vulkan bindings
│   │   ├── cgltf-Beef/         # GLTF parser
│   │   ├── Dxc-Beef/           # HLSL shader compiler
│   │   ├── SDL3-Beef/          # SDL3 bindings
│   │   ├── SDL3_mixer-Beef/    # SDL3_mixer bindings
│   │   └── SDL3_image-Beef/    # SDL3_image bindings
│   ├── Sedulous/               # Framework libraries
│   │   ├── Sedulous.Foundation/
│   │   ├── Sedulous.Mathematics/
│   │   ├── Sedulous.RHI/
│   │   ├── Sedulous.RHI.Vulkan/
│   │   ├── Sedulous.Engine.Renderer/
│   │   └── ...
│   └── Samples/                # Example applications
└── agents.md                   # Development documentation
```

## Samples

| Sample | Description |
|--------|-------------|
| [RendererGeometry](Code/Samples/RendererGeometry/) | Procedural cube mesh generation with gradient skybox |
| [RendererStaticMesh](Code/Samples/RendererStaticMesh/) | GLTF model loading with textured rendering (Duck) |
| [RendererSkinned](Code/Samples/RendererSkinned/) | Skeletal animation with bone transforms (Fox) |
| [RendererSprite](Code/Samples/RendererSprite/) | Billboard sprite rendering with instancing |
| [RendererParticles](Code/Samples/RendererParticles/) | GPU particle system with fountain effect |
| [RendererScene](Code/Samples/RendererScene/) | 1200 instanced cubes with frustum culling |
| [RendererLighting](Code/Samples/RendererLighting/) | Clustered lighting with cascaded shadow maps |
| [RendererIntegrated](Code/Samples/RendererIntegrated/) | Framework.Core + Renderer entity integration |

### Sample Controls

All renderer samples use consistent controls:

| Key | Action |
|-----|--------|
| WASD | Move camera |
| Q/E | Move down/up |
| Right-click + Drag | Look around |
| Tab | Toggle mouse capture |
| Shift | Move faster |

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                    Application                       │
├─────────────────────────────────────────────────────┤
│  Framework.Renderer  │  Framework.Audio  │  Core    │
├──────────────────────┴──────────────────┴──────────┤
│       Resources  │  Jobs  │  Shell  │  Geometry     │
├──────────────────┴───────┴─────────┴───────────────┤
│                RHI (Vulkan / DX12*)                  │
├─────────────────────────────────────────────────────┤
│    Foundation  │  Mathematics  │  Serialization     │
└─────────────────────────────────────────────────────┘
                    * DX12 not yet implemented
```

## Renderer Features

- **Clustered Forward Rendering** - Efficient light culling with 16x9x24 cluster grid
- **PBR Materials** - Physically-based rendering with albedo, metallic, roughness, normal maps
- **Shadow Mapping** - 4-cascade CSM for directional lights, shadow atlas for point/spot
- **Geometry Types** - Static meshes, skinned meshes, sprites, particles, skybox
- **Instancing** - Automatic batching of identical meshes
- **Frustum Culling** - CPU-side visibility determination

## License

See individual library licenses in their respective directories.
