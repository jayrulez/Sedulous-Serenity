# Sedulous.Engine.Renderer

Engine-level integration for 3D rendering. Provides context services, scene components, and entity components that bridge the ECS with the low-level renderer.

## Overview

```
Sedulous.Engine.Renderer          - Engine integration layer
├── RendererService               - Context service (shared GPU resources)
├── RenderSceneComponent          - Per-scene rendering management
├── DebugDrawService              - Debug visualization service
└── Components/                   - Entity components
    ├── StaticMeshComponent
    ├── SkinnedMeshComponent
    ├── LightComponent
    ├── CameraComponent
    ├── SpriteComponent
    └── ParticleEmitterComponent
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                          Context                                 │
│  ├── RendererService (owns shared resources)                    │
│  │   ├── GPUResourceManager                                     │
│  │   ├── ShaderLibrary                                          │
│  │   ├── MaterialSystem                                         │
│  │   ├── PipelineCache                                          │
│  │   └── RenderPipeline                                         │
│  └── DebugDrawService (debug visualization)                     │
├─────────────────────────────────────────────────────────────────┤
│                          Scene                                   │
│  └── RenderSceneComponent (per-scene rendering)                 │
│      ├── RenderContext                                          │
│      │   ├── RenderWorld (proxy storage)                        │
│      │   ├── LightingSystem                                     │
│      │   └── VisibilityResolver                                 │
│      └── Entity ↔ Proxy Mappings                                │
├─────────────────────────────────────────────────────────────────┤
│                         Entities                                 │
│  └── Entity                                                     │
│      ├── Transform (Position, Rotation, Scale)                  │
│      ├── StaticMeshComponent    → StaticMeshProxy               │
│      ├── LightComponent         → LightProxy                    │
│      └── CameraComponent        → CameraProxy                   │
└─────────────────────────────────────────────────────────────────┘
```

## Quick Start

```beef
// 1. Create and register RendererService
let rendererService = new RendererService();
context.RegisterService<RendererService>(rendererService);

// 2. Initialize with device after context startup
rendererService.Initialize(device, "Assets/shaders");

// 3. Create scene - RenderSceneComponent is auto-added
let scene = context.SceneManager.CreateScene("MainScene");
let renderComponent = scene.GetSceneComponent<RenderSceneComponent>();

// 4. Create entities with rendering components
let meshEntity = scene.CreateEntity("Cube");
meshEntity.Transform.Position = .(0, 0, 0);

let meshComp = new StaticMeshComponent();
meshComp.SetMesh(gpuMeshHandle, boundingBox);
meshComp.SetMaterialInstance(0, materialHandle);
meshEntity.AddComponent(meshComp);

// 5. Create camera
let cameraEntity = scene.CreateEntity("Camera");
cameraEntity.Transform.Position = .(0, 5, 10);
let camera = new CameraComponent(Math.PI_f / 4, 0.1f, 1000f, isMain: true);
cameraEntity.AddComponent(camera);

// 6. Create light
let lightEntity = scene.CreateEntity("Sun");
lightEntity.Transform.Rotation = Quaternion.CreateFromYawPitchRoll(0, -0.5f, 0);
let light = LightComponent.CreateDirectional(.(1, 1, 1), 1.0f, castShadows: true);
lightEntity.AddComponent(light);
```

## RendererService

Context service that owns shared GPU resources. Register with Context to enable rendering.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `Device` | `IDevice` | The graphics device |
| `ResourceManager` | `GPUResourceManager` | Mesh and texture management |
| `ShaderLibrary` | `ShaderLibrary` | Shader loading and caching |
| `MaterialSystem` | `MaterialSystem` | Materials and instances |
| `PipelineCache` | `PipelineCache` | Render pipeline caching |
| `Pipeline` | `RenderPipeline` | Shared rendering orchestrator |
| `RenderGraph` | `RenderGraph` | Automatic pass management |
| `ColorFormat` | `TextureFormat` | Color buffer format |
| `DepthFormat` | `TextureFormat` | Depth buffer format |
| `IsInitialized` | `bool` | Whether service is ready |

### Methods

```beef
// Initialize the service
Result<void> Initialize(IDevice device, StringView shaderBasePath);

// Set render formats before initialization
void SetFormats(TextureFormat colorFormat, TextureFormat depthFormat);

// Frame lifecycle (called by framework)
void BeginFrame(uint32 frameIndex, float deltaTime, float totalTime,
                ITextureView swapChainView, ITextureView depthView,
                uint32 width, uint32 height);
void EndFrame();

// Execute the render graph
void ExecuteRenderGraph(ICommandEncoder encoder);

// Debug draw pass (auto-added when DebugDrawService present)
void AddDebugDrawPass(RenderGraph graph, ResourceHandle color, ResourceHandle depth,
                      Matrix viewProjection, uint32 width, uint32 height, int32 frameIndex);
```

## RenderSceneComponent

Per-scene component that manages rendering. Automatically created by RendererService when scenes are added.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `RenderWorld` | `RenderWorld` | Proxy storage for this scene |
| `Pipeline` | `RenderPipeline` | Shared render pipeline |
| `LightingSystem` | `LightingSystem` | Per-scene lighting |
| `VisibilityResolver` | `VisibilityResolver` | Frustum culling |
| `MainCamera` | `ProxyHandle` | Main camera proxy handle |
| `VisibleMeshes` | `List<StaticMeshProxy*>` | Meshes visible this frame |
| `ActiveLights` | `List<LightProxy*>` | Active lights this frame |

### Methods

```beef
// Initialize rendering for this scene
Result<void> InitializeRendering(TextureFormat colorFormat, TextureFormat depthFormat);

// Set render targets
void SetRenderTargets(ITextureView* colorTarget, ITextureView* depthTarget);

// Manual proxy management (usually automatic via components)
ProxyHandle CreateStaticMeshProxy(Entity entity, StaticMeshComponent component);
ProxyHandle CreateLightProxy(Entity entity, LightComponent component);
ProxyHandle CreateCameraProxy(Entity entity, CameraComponent component);
void RemoveProxy(ProxyHandle handle);

// Get camera proxy
CameraProxy* GetMainCameraProxy();
```

## Entity Components

### StaticMeshComponent

Renders a static mesh with materials.

```beef
let mesh = new StaticMeshComponent();
mesh.SetMesh(gpuMeshHandle, localBounds);
mesh.SetMaterialInstance(0, materialHandle);
mesh.CastShadows = true;
mesh.ReceiveShadows = true;
mesh.Visible = true;
entity.AddComponent(mesh);
```

| Property | Type | Description |
|----------|------|-------------|
| `MaterialInstances` | `MaterialInstanceHandle[8]` | Material per sub-mesh |
| `MaterialCount` | `uint8` | Number of materials |
| `CastShadows` | `bool` | Shadow casting (default true) |
| `ReceiveShadows` | `bool` | Shadow receiving (default true) |
| `Visible` | `bool` | Visibility (default true) |
| `LocalBounds` | `BoundingBox` | Local-space bounding box |

### SkinnedMeshComponent

Renders an animated skeletal mesh.

```beef
let skinned = new SkinnedMeshComponent();
skinned.SetMesh(gpuMeshHandle, skeleton, localBounds);
skinned.SetMaterialInstance(0, materialHandle);
skinned.SetAnimation(animationClip);
entity.AddComponent(skinned);
```

| Property | Type | Description |
|----------|------|-------------|
| `MaterialInstances` | `MaterialInstanceHandle[8]` | Material per sub-mesh |
| `CastShadows` | `bool` | Shadow casting |
| `Visible` | `bool` | Visibility |
| `CurrentAnimation` | `AnimationClip` | Current playing animation |
| `AnimationTime` | `float` | Current time in animation |
| `AnimationSpeed` | `float` | Playback speed multiplier |

### LightComponent

Adds a light source to the scene.

```beef
// Factory methods
let dirLight = LightComponent.CreateDirectional(.(1, 1, 1), 1.0f, castShadows: true);
let pointLight = LightComponent.CreatePoint(.(1, 0.8f, 0.6f), 2.0f, range: 10.0f);
let spotLight = LightComponent.CreateSpot(.(1, 1, 1), 5.0f, range: 20.0f,
                                          innerAngle: 15f * DEG2RAD, outerAngle: 30f * DEG2RAD);
```

| Property | Type | Description |
|----------|------|-------------|
| `Type` | `LightType` | Directional, Point, or Spot |
| `Color` | `Vector3` | Light color (linear RGB) |
| `Intensity` | `float` | Light intensity |
| `Range` | `float` | Attenuation range (Point/Spot) |
| `InnerConeAngle` | `float` | Spot inner angle (radians) |
| `OuterConeAngle` | `float` | Spot outer angle (radians) |
| `CastsShadows` | `bool` | Enable shadow casting |
| `Enabled` | `bool` | Light enabled state |

### CameraComponent

Adds a camera viewpoint.

```beef
let camera = new CameraComponent();
camera.FieldOfView = Math.PI_f / 4.0f;  // 45 degrees
camera.NearPlane = 0.1f;
camera.FarPlane = 1000.0f;
camera.IsMain = true;
camera.UseReverseZ = true;  // Recommended
entity.AddComponent(camera);
```

| Property | Type | Description |
|----------|------|-------------|
| `FieldOfView` | `float` | Vertical FOV in radians |
| `NearPlane` | `float` | Near clip distance |
| `FarPlane` | `float` | Far clip distance |
| `IsMain` | `bool` | Set as main camera |
| `UseReverseZ` | `bool` | Use reverse-Z depth |
| `LayerMask` | `uint32` | Visibility layer mask |
| `Priority` | `int32` | Render order priority |
| `Enabled` | `bool` | Camera enabled state |

### SpriteComponent

Renders a 2D sprite in 3D space.

```beef
let sprite = new SpriteComponent();
sprite.Texture = textureView;
sprite.Size = .(1, 1);
sprite.Color = Color.White;
sprite.Billboard = true;
entity.AddComponent(sprite);
```

### ParticleEmitterComponent

Emits and renders particles.

```beef
let emitter = new ParticleEmitterComponent();
emitter.EmissionRate = 100;
emitter.ParticleLifetime = 2.0f;
emitter.StartSize = 0.1f;
emitter.EndSize = 0.0f;
emitter.StartColor = Color.White;
emitter.EndColor = Color(255, 255, 255, 0);
entity.AddComponent(emitter);
```

## DebugDrawService

Context service for debug visualization. Draw primitives during update; they render automatically.

### Setup

```beef
// Register after RendererService
let debugDraw = new DebugDrawService();
context.RegisterService<DebugDrawService>(debugDraw);
```

### Drawing Methods

```beef
// Lines
debugDraw.DrawLine(start, end, Color.Red);
debugDraw.DrawRay(origin, direction, Color.Green);

// Wireframe shapes
debugDraw.DrawWireBox(boundingBox, Color.Yellow);
debugDraw.DrawWireBox(min, max, Color.Yellow);
debugDraw.DrawWireSphere(center, radius, Color.Cyan);
debugDraw.DrawWireSphere(center, radius, Color.Cyan, segments: 16);

// Solid shapes
debugDraw.DrawSolidBox(min, max, Color(255, 0, 0, 128));

// Coordinate helpers
debugDraw.DrawAxes(origin, size: 1.0f);
debugDraw.DrawGrid(center, cellSize: 1.0f, cellCount: 10, Color.Gray);

// All methods support render mode parameter
debugDraw.DrawLine(start, end, Color.Red, .Overlay);  // Always on top
debugDraw.DrawLine(start, end, Color.Red, .DepthTest);  // Default, integrates with scene
```

### Render Modes

| Mode | Description |
|------|-------------|
| `DepthTest` | Primitives integrate with scene geometry (default) |
| `Overlay` | Primitives always render on top |

## Proxy System

Entity components automatically sync with render proxies:

```
Entity + Component            RenderWorld Proxy
─────────────────────────────────────────────────
StaticMeshComponent    →    StaticMeshProxy
SkinnedMeshComponent   →    SkinnedMeshProxy
LightComponent         →    LightProxy
CameraComponent        →    CameraProxy
SpriteComponent        →    SpriteProxy
ParticleEmitterComponent →  ParticleEmitterProxy
```

Proxies are GPU-friendly data structures used during rendering. The sync happens automatically in `RenderSceneComponent.Update()`.

## Frame Flow

```
Context.Update()
  ├── Scene.Update()
  │   └── RenderSceneComponent.Update()
  │       ├── Sync entity transforms → proxies
  │       ├── Update particle systems
  │       └── Prepare visibility data
  │
RendererService.BeginFrame()
  ├── Register render graph resources
  └── Set frame state
  │
RenderSceneComponent.Render() [via render graph]
  ├── Frustum culling (VisibilityResolver)
  ├── Shadow pass (LightingSystem)
  ├── Main pass (RenderPipeline)
  │   ├── StaticMeshRenderer
  │   ├── SkinnedMeshRenderer
  │   ├── SpriteRenderer
  │   └── ParticleRenderer
  └── Post-process passes
  │
DebugDrawService render pass
  │
RendererService.EndFrame()
```

## Sample Usage

```beef
class MyGame
{
    private Context mContext;
    private RendererService mRendererService;
    private DebugDrawService mDebugDraw;
    private Scene mScene;

    public void Initialize(IDevice device)
    {
        mContext = new Context(logger, workerThreads: 4);

        // Register services
        mRendererService = new RendererService();
        mRendererService.SetFormats(.BGRA8Unorm, .Depth32Float);
        mContext.RegisterService<RendererService>(mRendererService);

        mDebugDraw = new DebugDrawService();
        mContext.RegisterService<DebugDrawService>(mDebugDraw);

        mContext.Startup();

        // Initialize renderer
        mRendererService.Initialize(device, "Assets/shaders");

        // Create scene
        mScene = mContext.SceneManager.CreateScene("Main");

        // Setup scene...
        CreateCamera();
        CreateLights();
        CreateMeshes();
    }

    private void CreateCamera()
    {
        let entity = mScene.CreateEntity("Camera");
        entity.Transform.Position = .(0, 5, 10);
        entity.AddComponent(new CameraComponent(Math.PI_f / 4, 0.1f, 1000f, isMain: true));
    }

    public void Update(float dt)
    {
        mContext.Update(dt);

        // Debug visualization
        mDebugDraw.DrawAxes(.Zero, 1.0f);
        mDebugDraw.DrawGrid(.Zero, 1.0f, 10, Color.Gray);
    }

    public void Render(ICommandEncoder encoder, ITextureView swapChain, ITextureView depth,
                       uint32 width, uint32 height, uint32 frameIndex)
    {
        mRendererService.BeginFrame(frameIndex, mDeltaTime, mTotalTime,
                                    swapChain, depth, width, height);
        mRendererService.ExecuteRenderGraph(encoder);
        mRendererService.EndFrame();
    }
}
```
