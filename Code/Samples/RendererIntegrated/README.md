# RendererIntegrated

Demonstrates the integration between Framework.Core (entity/component system) and Framework.Renderer (proxy-based rendering).

## Features

- Context with RendererService for shared GPU resources
- Scene with RenderSceneComponent for per-scene rendering
- Entities with MeshRendererComponent, LightComponent, and CameraComponent
- Automatic transform synchronization (entity transforms flow to render proxies)
- Visibility culling through the scene component

## Architecture

```
Context
├── RendererService (shared GPU resources)
└── SceneManager
    └── Scene
        ├── RenderSceneComponent (RenderWorld, VisibilityResolver)
        └── Entities
            ├── Camera Entity + CameraComponent
            ├── Light Entities + LightComponent
            └── Mesh Entities + MeshRendererComponent
```

## Key Classes

- `RendererService` - Context service owning Device, ShaderLibrary, etc.
- `RenderSceneComponent` - Scene component owning RenderWorld
- `MeshRendererComponent` - Entity component for static meshes
- `LightComponent` - Entity component for lights
- `CameraComponent` - Entity component for cameras

## Controls

| Key | Action |
|-----|--------|
| WASD | Move camera |
| Q/E | Move down/up |
| Tab | Toggle mouse capture |
| Shift | Move faster |
| Right-click + Drag | Look around |

## Technical Details

- Uses entity-to-proxy mapping (EntityId -> ProxyHandle)
- Transform sync happens in RenderSceneComponent.OnUpdate()
- Visibility resolved before rendering each frame
- Context.Update() drives the entire update pipeline

## Dependencies

- Sedulous.Framework.Core
- Sedulous.Framework.Renderer
- SampleFramework
