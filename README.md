# Sedulous

## ⚠️ Project Status

This version of Sedulous is **no longer actively developed**.

Development has moved to a new internal branch with a redesigned architecture. This repository remains available for reference, and many improvements from earlier experimental work have already been merged back into it.

---

## Architecture Evolution

To improve Sedulous, I explored a series of experimental forks:

- **Project Atlas** *(first private fork)*  
  Focused on evolving the existing architecture, particularly the renderer and engine-layer integration with Foundation.  
  Many successful changes from Atlas were backported into this repository.

- **Project Nova** *(second private fork)*  
  A clean-slate redesign. This fork removes the renderer and all higher-level systems, rebuilding the engine upward from the Foundation layer with a stronger architectural direction.

Both forks were developed in parallel for some time, but maintaining shared components between them became increasingly complex.

---

## Current Direction

Development is now fully focused on **Project Nova**.

While Nova has not yet reached feature parity with this repository or Project Atlas, it establishes a cleaner and more scalable foundation for the future of Sedulous.

Once Nova reaches a stage where it is capable of building a complete game, it will be made public.

---

## Summary

- This repository: **no longer actively developed**
- Project Atlas: **experimental evolution (partially merged here)**
- Project Nova: **future of Sedulous (private, in progress)**

---

If you're exploring Sedulous today, this repo is still useful for understanding the engine’s current capabilities—but it does not reflect the direction of ongoing development.

===========================================================================================================

A modular game engine for the [Beef programming language](https://www.beeflang.org/).

## Overview

Sedulous is a layered game engine with foundation libraries, an engine runtime, a forward+ renderer, tools, and sample games. It targets Vulkan and is built entirely in Beef.

## Building

Requirements:
- [Beef IDE](https://www.beeflang.org/) or BeefBuild CLI
- Vulkan SDK

```bash
cd Code && BeefBuild
```

## Project Structure

```
Sedulous-Serenity/
├── Code/
│   ├── BeefSpace.toml           # Workspace configuration
│   ├── Foundation/              # Low-level libraries (core, RHI, resources, etc.)
│   ├── Engine/                  # Engine subsystems (scenes, render, animation, etc.)
│   ├── Samples/                 # 57 sample applications
│   ├── Tools/                   # ModelViewer, SceneEditor
│   ├── Games/                   # TowerDefense, ImpactArena, StormTactics
│   ├── Dependencies/            # Third-party Beef bindings
│   └── Assets/                  # Shaders, textures, models
```

## Foundation Libraries

Low-level libraries that the engine is built on.

| Domain | Libraries |
|--------|-----------|
| **Core** | Core, Core.Collections, Core.Logging, Core.Mathematics, Core.Mathematics.Serialization |
| **RHI** | RHI (abstract API), RHI.Vulkan, RHI.DX12 (WIP) |
| **Rendering** | Render, RenderGraph, Shaders, Materials, Materials.Resources, Textures, Textures.Resources, Drawing, Drawing.Fonts, Drawing.Renderer, DebugFont |
| **Resources & Jobs** | Resources, Jobs |
| **Geometry & Models** | Geometry, Geometry.Resources, Geometry.Tooling, Models, Models.GLTF, Models.FBX |
| **Animation** | Animation, Animation.Resources |
| **Audio** | Audio, Audio.Decoders, Audio.Resources, Audio.SDL3 |
| **Physics** | Physics, Physics.Jolt |
| **Serialization** | Serialization, Serialization.OpenDDL, Serialization.Xml, OpenDDL, Xml, BJSON |
| **GUI & Drawing** | GUI, GUI.Shell, Fonts, Fonts.Resources, Fonts.TTF |
| **Imaging** | Imaging, Imaging.Resources, Imaging.SDL, Imaging.STB |
| **Shell** | Shell, Shell.SDL3 |
| **Networking** | Net, Net.HTTP |
| **Runtime** | Runtime, Runtime.Client |
| **Profiling** | Profiler |

All libraries are prefixed `Sedulous.` (e.g., `Sedulous.Core`, `Sedulous.RHI.Vulkan`).

## Engine Libraries

High-level engine subsystems built on the foundation.

| Library | Purpose |
|---------|---------|
| **Engine.Core** | Application lifecycle, context, subsystems |
| **Engine.Scenes** | Scene graph, ECS, component serialization |
| **Engine.Render** | Render subsystem, scene module, proxy management |
| **Engine.Animation** | Skeletal animation, property animation, animation graphs |
| **Engine.Audio** | Audio sources, listeners, spatial audio |
| **Engine.Input** | Input handling |
| **Engine.Physics** | Rigid bodies, collision, physics scene module |
| **Engine.Navigation** | Navmesh agents, obstacles, pathfinding |

## Renderer Features

Forward+ clustered renderer with PBR pipeline:

- **Lighting** — Clustered forward+ (16x9x24), PBR + IBL (irradiance, prefiltered, BRDF LUT), reflection probes (cubemap array, distance-blended), SH9 diffuse
- **Shadows** — 4-cascade CSM, shadow atlas for point/spot, contact shadows (screen-space ray march)
- **Post-Processing** — Bloom (5-level downsample/upsample), configurable tonemapping (ACES/Reinhard/Uncharted2), auto-exposure (histogram compute), SSAO (hemisphere sampling + bilateral blur), SSR (linear ray march + binary refinement), depth of field, motion blur, vignette, film grain, chromatic aberration, color grading (3D LUT)
- **Anti-Aliasing** — TAA (motion-vector reprojection, Halton jitter, neighborhood clamping), FXAA 3.11, CAS sharpening
- **Geometry** — Static meshes, skinned meshes (GPU skinning), sprites, particles, trails, box decals, curve decals, terrain (chunked, splatmap blending), water (wave displacement, refraction, foam), grass (instanced)
- **Sky** — Procedural gradient, environment map, solid color, IBL regeneration
- **Optimization** — GPU instancing (auto-batching by material/mesh/LOD), depth prepass, Hi-Z occlusion culling, LOD system, frustum culling, motion vectors
- **Infrastructure** — RenderGraph, thin GBuffer MRT (normal + roughness + metallic), PostProcessStack (priority-sorted, ping-pong buffers), volumetric fog

## Samples

### RHI Samples (15)

| Sample | Description |
|--------|-------------|
| RHITriangle | Basic triangle rendering |
| RHITexturedQuad | Textured quad with sampler |
| RHIDepthBuffer | Depth testing |
| RHIInstancing | Instanced rendering |
| RHIBindGroups | Bind group usage |
| RHIBlending | Alpha blending modes |
| RHIBlit | Blit/copy operations |
| RHIBorderSampler | Border sampler modes |
| RHICompute | Compute shaders |
| RHIMRT | Multiple render targets |
| RHIMSAA | Multi-sample anti-aliasing |
| RHIMipmaps | Mipmap generation |
| RHIQueries | GPU queries |
| RHIReadback | GPU-to-CPU readback |
| RHIWireframe | Wireframe rendering |

### Render Samples (23)

| Sample | Description |
|--------|-------------|
| RenderTriangle | Minimal renderer triangle |
| RenderGeometry | Procedural mesh generation |
| RenderStaticMesh | GLTF model loading (Duck) |
| RenderSkinned | Skeletal animation (Fox) |
| RenderSprite | Billboard sprite rendering |
| RenderParticles | GPU particle system |
| RenderScene | 5000 instanced objects with culling |
| RenderLighting | Clustered lighting + cascaded shadow maps |
| RenderShadow | Shadow mapping showcase |
| RenderPBR | PBR materials with IBL |
| RenderSky | Sky system and environment |
| RenderUnlit | Unlit material rendering |
| RenderMaterials | Material system |
| RenderMaterialsCustom | Custom material pipeline |
| RenderDecals | Box and curve decals |
| RenderMultiView | Multi-viewport rendering |
| RenderAsset | Asset import pipeline |
| RenderScreenEffects | SSAO, SSR, contact shadows (Sponza) |
| RenderTerrain | Terrain with heightmap and splatmap |
| RenderWater | Water with refraction and foam |
| RenderCinematic | DOF, motion blur, film grain, color grading |
| RenderIntegrated | Engine + renderer integration |
| RenderSandbox | Full-feature rendering sandbox |

### Engine Samples (5)

| Sample | Description |
|--------|-------------|
| EngineRender | Engine rendering pipeline |
| EngineAnimation | Skeletal and property animation |
| EngineNavigation | Navmesh pathfinding |
| EngineSerialization | Scene serialization |
| EngineSandbox | Engine feature sandbox |

### Networking Samples (3)

| Sample | Description |
|--------|-------------|
| NetEcho | TCP echo server/client |
| NetHttpClient | HTTP client requests |
| NetWebSocket | WebSocket communication |

### Other Samples (11)

| Sample | Description |
|--------|-------------|
| AudioSample | Audio playback |
| AudioSandbox | Engine audio subsystem |
| DrawingSandbox | 2D drawing API |
| FontRendering | Font rendering |
| GUISandbox | GUI system |
| ImGuiSample | Dear ImGui integration |
| NuklearSample | Nuklear UI integration |
| PhysicsSandbox | Jolt physics |
| ResourcesSample | Resource loading and caching |
| ShellSample | Windowing and input |
| BeefSandbox | Language/API experiments |

### Sample Controls

| Key | Action |
|-----|--------|
| WASD | Move camera |
| Q/E | Move down/up |
| Right-click + Drag | Look around |
| Tab | Toggle mouse capture |
| Shift | Move faster |
| T | Toggle tonemapping operator |
| B | Toggle bloom |
| F1 | Toggle auto-exposure |
| F2 | Cycle AA mode (None/FXAA/TAA) |
| F3 | Toggle CAS sharpening |
| I | Toggle GPU instancing |
| L | Toggle LOD |

## Tools

| Tool | Description |
|------|-------------|
| **Sedulous.Tools.ModelViewer** | 3D model and asset viewer |
| **Sedulous.Tools.SceneEditor** | Scene editor (experimental) |
| **Sedulous.Tools.Core** | Shared tool utilities |
| **Sedulous.Tools.AppFramework** | Tool application base |

## Games

| Game | Description |
|------|-------------|
| **TowerDefense** | Tower defense game |
| **ImpactArena** | Arena action game |
| **StormTactics** | Tactical RPG with client/server architecture |

## Dependencies

Third-party C/C++ libraries with Beef bindings:

| Library | Purpose |
|---------|---------|
| Bulkan | Vulkan API bindings |
| SDL3-Beef | Windowing, input, platform |
| SDL3_image-Beef | Image loading |
| SDL3_mixer-Beef | Audio mixing |
| Dxc-Beef | DirectX Shader Compiler (HLSL) |
| cgltf-Beef | GLTF/GLB parser |
| ufbx-Beef | FBX file loader |
| joltc-Beef | Jolt Physics engine |
| recastnavigation-Beef | Navigation mesh generation |
| stb_image-Beef | Image loading (STB) |
| stb_truetype-Beef | TrueType font rasterizer |
| stb_vorbis-Beef | Ogg Vorbis audio decoder |
| dr_libs-Beef | Audio decoders (WAV, MP3, FLAC) |
| cimgui-Beef | Dear ImGui bindings |
| Nuklear-Beef | Nuklear UI bindings |
| Win32-Beef | Windows API bindings |
| BJSON | Binary JSON serialization |

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                        Application                           │
│              (Games, Tools, Samples)                         │
├──────────────────────────────────────────────────────────────┤
│                     Engine Libraries                         │
│  Scenes │ Render │ Animation │ Audio │ Physics │ Navigation  │
├──────────────────────────────────────────────────────────────┤
│                   Foundation Libraries                       │
│  Render │ RenderGraph │ Resources │ Materials │ Geometry     │
│  Audio  │ Animation   │ Physics   │ GUI       │ Drawing      │
│  Shell  │ Net         │ Serialization │ Imaging │ Fonts      │
├──────────────────────────────────────────────────────────────┤
│                    RHI  (Vulkan)                              │
├──────────────────────────────────────────────────────────────┤
│             Core  │  Mathematics  │  Jobs                    │
└──────────────────────────────────────────────────────────────┘
```

## License

See individual library licenses in their respective directories.

[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/jayrulez/Sedulous-Serenity)
