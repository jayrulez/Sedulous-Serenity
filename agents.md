# Sedulous Framework - LLM Development Guide

This document provides essential information for AI assistants working on the Sedulous game framework.

## Quick Reference

### Building and Testing

```bash
# Build the workspace
BeefBuild.exe -workspace=Code/ -verbosity=normal

# Run all tests
BeefBuild.exe -workspace=Code/ -test

# Build specific configuration
BeefBuild.exe -workspace=Code/ -config=Release
```

### Project Layout

```
Sedulous-Serenity/
├── Code/
│   ├── BeefSpace.toml          # Workspace configuration
│   ├── Dependencies/           # Third-party bindings
│   ├── Sedulous/               # Framework libraries
│   └── Samples/                # Example applications
├── OpenDDL/                    # OpenDDL spec and reference implementation
├── ReferenceSedulous/          # Previous framework iteration (for reference)
└── agents.md                   # This file
```

### Dependencies (Code/Dependencies/)

Third-party bindings used by the framework:
- **Bulkan** - Vulkan graphics API bindings
- **cgltf-Beef** - GLTF/GLB model file parser bindings
- **Dxc-Beef** - DirectX Shader Compiler bindings for HLSL compilation
- **SDL3-Beef** - SDL3 windowing, input, and platform abstraction bindings
- **SDL3_mixer-Beef** - SDL3_mixer audio playback bindings
- **SDL3_image-Beef** - SDL3_image file format loading bindings
- **Win32-Beef** - Windows API bindings (for DX12 backend)

---

## Project Status

### Library Status

| Layer | Library | Status | Description |
|-------|---------|--------|-------------|
| **Foundation** | Sedulous.Foundation | Complete | Type extensions, Contract assertions, EventAccessor |
| | Sedulous.Collections | Complete | Custom collections (FixedList) |
| | Sedulous.Logging | Complete | Logging abstractions |
| | Sedulous.Mathematics | Complete | Vector, Matrix, Quaternion, BoundingBox, Color |
| | Sedulous.OpenDDL | Complete | OpenDDL parser and writer |
| **Serialization** | Sedulous.Serialization | Complete | Abstract serialization framework |
| | Sedulous.Serialization.OpenDDL | Complete | OpenDDL serializer implementation |
| | Sedulous.Framework.Serialization | Complete | Math type serialization extensions |
| **Assets** | Sedulous.Imaging | Complete | Image loading/manipulation |
| | Sedulous.Geometry | Complete | Mesh creation, VertexBuffer, IndexBuffer, SkinnedMesh |
| | Sedulous.Models | Complete | Model representation with bones, materials, animations |
| | Sedulous.Models.GLTF | Complete | GLTF/GLB loader |
| **Runtime** | Sedulous.Jobs | Complete | Multi-threaded job system |
| | Sedulous.Resources | Complete | Async resource loading with caching |
| | Sedulous.Shell | Complete | Window management, input abstraction |
| | Sedulous.Shell.SDL3 | Complete | SDL3 implementation |
| **Framework** | Sedulous.Framework.Core | Complete | Context, ECS, Scene management |
| | Sedulous.Framework.Audio | Complete | Audio system interfaces |
| | Sedulous.Framework.Audio.SDL3 | Complete | SDL3_mixer implementation |
| | Sedulous.Framework.Input | Not Started | High-level input processing |
| | Sedulous.Framework.Renderer | **In Progress** | High-level rendering (Phases 1-5 complete) |
| **RHI** | Sedulous.RHI | Complete | Graphics API abstraction |
| | Sedulous.RHI.Vulkan | Complete | Vulkan backend |
| | Sedulous.RHI.DX12 | Not Started | DirectX 12 backend |
| | Sedulous.RHI.HLSLShaderCompiler | Complete | HLSL compilation via DXC |
| **Integration** | Sedulous.Runtime | Not Started | Application framework |
| | Sedulous.Runtime.SDL3 | Not Started | SDL-based runtime |

### Renderer Implementation Progress

#### Phase 1: Foundation + Render Graph Core
- [x] Create `Sedulous.Renderer` project with dependencies
- [x] RenderGraph core (pass declaration, resource nodes, compile, execute)
- [x] TransientResourcePool (texture/buffer pooling)
- [x] GPUResourceManager basics (mesh/texture upload)
- [x] Simple forward pass (not through render graph yet)
- [x] Basic camera (view/projection, reverse-Z, Vulkan Y-flip)
- [x] Sample: `RendererTriangle`

#### Phase 2: Materials & Shaders
- [x] ShaderLibrary (load shaders, reflection)
- [x] Material/MaterialInstance system
- [x] PipelineCache (hash-based lookup)
- [x] Standard PBR shader
- [x] Shader variant system (SKINNED, INSTANCED)
- [x] Sample: `RendererPBR`

#### Phase 3: Geometry Types
- [x] Static mesh rendering
- [x] Skinned mesh rendering (bone transforms, vertex skinning)
- [x] Sprite rendering (billboards, instancing)
- [x] Particle system
- [ ] Decal rendering
- [x] Skybox rendering
- [x] GLTF model loading
- [ ] Sample: `RendererGeometry` complete (missing: decals)

#### Phase 4: Visibility & Scene
- [x] RenderWorld and proxy system (MeshProxy, LightProxy, CameraProxy)
- [x] FrustumCuller (geometric plane computation, working correctly)
- [x] VisibilityResolver with draw sorting
- [x] LOD selection (distance-based)
- [x] Instancing support (instance buffer, DrawIndexedInstanced)
- [ ] Depth pre-pass
- [x] Sample: `RendererScene` - 1200 instanced cubes with frustum culling

#### Phase 5: Lighting & Shadows
- [x] ClusterGrid (16x9x24 clusters) - CPU implementation
- [x] Light types (directional, point, spot) with attenuation
- [x] LightingSystem wrapper class
- [x] Clustered lighting shader include (clustered_lighting.hlsli)
- [x] PBR shader variant for dynamic lights (pbr_clustered.frag.hlsl)
- [x] Cascaded shadow maps (4 cascades) - frustum fitting, texel snapping
- [x] Shadow atlas (point/spot tiles) - VP matrices, tile allocation, 6-face point lights
- [x] PCF shadow filtering (3x3 kernel)
- [x] Shadow depth shaders (shadow_depth.vert.hlsl, instanced/skinned variants)
- [x] Shadow uniform buffer and comparison sampler
- [x] Sample: `RendererLighting` - clustered lighting with cascaded shadows

#### Phase 6: Post-Processing (Next)
- [ ] HDR render target (RGBA16F)
- [ ] Exposure control
- [ ] Bloom (downsample + blur + composite)
- [ ] Tonemapping (ACES)
- [ ] TAA (jitter + velocity + history)
- [ ] FXAA fallback
- [ ] Color grading (3D LUT)
- [ ] Sample: `RendererPostFX`

#### Phase 7: Polish & Integration
- [ ] Hi-Z occlusion culling
- [ ] GPU profiling markers
- [ ] Debug visualization modes
- [ ] Shader hot-reload
- [ ] Framework.Core integration
- [ ] RenderSceneComponent
- [ ] Documentation
- [ ] Sample: `RendererIntegrated`

#### Known Issues / TODO
- Decal rendering not yet implemented
- Frustum-fitted cascade bounds produce offset shadows (using fixed bounds workaround)

---

## Beef Language Patterns

### Value Types vs Reference Types

```beef
// Structs are value types - use for small, frequently copied data
struct Vector3 { public float X, Y, Z; }
struct EntityId { public uint32 Index, Generation; }

// Classes are reference types - use for entities, components, systems
class Entity { ... }
class Scene : ISerializable { ... }
```

### Memory Management

```beef
// Owned pointer with automatic deletion
private Scene mScene ~ delete _;

// Owned container that deletes contents
private List<Entity> mEntities = new .() ~ DeleteContainerAndItems!(_);

// Owned dictionary with key and value deletion
private Dictionary<String, ComponentFactory> mFactories = new .() ~ DeleteDictionaryAndKeysAndValues!(_);

// Non-owning reference (no destructor)
private ComponentRegistry mComponentRegistry;
```

### Struct Methods and Mutability

```beef
struct Transform
{
    public Vector3 Position;

    // Methods that modify struct state need 'mut'
    public void SetPosition(Vector3 pos) mut
    {
        Position = pos;
    }

    // Getters that compute values also need 'mut' if they cache results
    public Matrix4x4 LocalMatrix
    {
        get mut
        {
            if (mDirty) { mCachedMatrix = ComputeMatrix(); mDirty = false; }
            return mCachedMatrix;
        }
    }
}
```

### Scope Allocations

Beef's `scope` keyword allocates memory on the stack that's automatically freed when the scope exits. **Important:** The allocation is only valid within the current block scope, not the entire function.

```beef
// WRONG - scoped array freed when 'if' block exits
void Example()
{
    int* data = null;
    if (condition)
    {
        data = scope int[10]*;  // Allocated here
        data[0] = 42;
    }  // <-- FREED HERE! data is now dangling

    UseData(data);  // BUG: accessing freed memory
}

// CORRECT - use `scope ::` to extend lifetime to function scope
void Example()
{
    int* data = null;
    if (condition)
    {
        data = scope :: int[10]*;  // `::` = function scope
        data[0] = 42;
    }

    UseData(data);  // OK: still valid
}
```

**Debug symptom:** Accessing freed scoped memory often shows `0xdddddddddddddddd` (Windows debug heap freed memory pattern).

### Spans and Stack-Allocated Arrays

`Span<T>` is a view into contiguous memory. When a `Span` is created from a stack-allocated array, the span becomes invalid when that array goes out of scope.

```beef
// WRONG - returning a struct containing a Span to stack data
VertexBufferLayout GetLayout()
{
    VertexAttribute[2] attributes = .(...);  // Stack-allocated
    return .((uint64)sizeof(Vertex), attributes);  // Span points to 'attributes'
}  // <-- 'attributes' freed here, Span is now dangling!

// CORRECT - keep arrays in same scope as their consumers
void CreatePipeline()
{
    VertexAttribute[2] vertexAttributes = .(...);
    VertexBufferLayout[1] vertexBuffers = .(
        .((uint64)sizeof(Vertex), vertexAttributes)  // OK: same scope
    );
    device.CreateRenderPipeline(&pipelineDesc);  // OK
}
```

**Debug symptom:** Garbage values like `1586493504` instead of expected small integers for vertex attribute locations.

### Result Types and Error Handling

```beef
// Use Result<T, E> for operations that can fail
public Result<SceneResource, ResourceLoadError> LoadFromMemory(MemoryStream memory)
{
    if (memory.TryRead(data) case .Err)
        return .Err(.ReadError);
    return .Ok(resource);
}

// Use Result<void> for operations without a return value
public Result<void> SaveToFile(StringView path)
{
    if (stream.Create(path) case .Err)
        return .Err;
    return .Ok;
}
```

### Lambda Captures

```beef
// Value capture (copies value)
delegate void(int x) fn = new (x) => { ... };

// Reference capture (captures by reference)
int counter = 0;
delegate void() fn = new [&] () => { counter++; };
```

### Friend Access

```beef
// Access private/internal members using [Friend]
mOnSceneLoaded.[Friend]Invoke(scene);
```

---

## Framework Architecture

### Dependency Hierarchy

```
Foundation Layer (no dependencies):
  Sedulous.Foundation, Collections, Logging, Mathematics, OpenDDL
      ↓
Serialization Layer:
  Sedulous.Serialization, Serialization.OpenDDL
      ↓
Asset Layer:
  Sedulous.Imaging, Geometry, Models
      ↓
System Layer:
  Sedulous.Jobs, Resources, Shell
      ↓
Framework Layer:
  Sedulous.Framework.Core, Audio, Renderer
      ↓
RHI Layer:
  Sedulous.RHI, RHI.Vulkan
```

### Key Types Reference

#### Sedulous.Framework.Core

| Type | Purpose |
|------|---------|
| `Context` | Central access point, owns JobSystem, ResourceSystem, SceneManager |
| `EntityId` | uint32 index + uint32 generation for stale detection |
| `Entity` | Has Transform (always present), optional components via `IEntityComponent` |
| `EntityManager` | Entity lifecycle, parent-child hierarchy, transform propagation |
| `Transform` | Position, Rotation (Quaternion), Scale with lazy matrix computation |
| `Scene` | Contains EntityManager, scene components (`ISceneComponent`), serializable via OpenDDL |
| `SceneManager` | Scene creation, activation, transitions, lifecycle events |
| `SceneResource` | Scene as a loadable resource |
| `ComponentRegistry` | Type name ↔ factory mapping for component serialization |

**Context** owns and manages:
- `JobSystem` - Background job execution
- `ResourceSystem` - Async resource loading
- `SceneManager` - Scene lifecycle management
- `ComponentRegistry` - Type registry for component serialization
- Type-keyed service registration via `IContextService`

#### Sedulous.Framework.Audio

| Type | Purpose |
|------|---------|
| `IAudioSystem` | Main interface: CreateSource, PlayOneShot, PlayOneShot3D, LoadClip, Listener |
| `IAudioSource` | Play/Pause/Resume/Stop, Volume, Pitch, Loop, Position, MinDistance, MaxDistance |
| `IAudioClip` | Loaded audio data (duration, sample rate, channels) |
| `IAudioListener` | Position, Forward, Up - listener orientation in world space |
| `AudioClipResource` | Audio clip as a loadable resource |
| `AudioClipResourceManager` | Integrates with ResourceSystem for async loading |

#### Sedulous.Resources

| Type | Purpose |
|------|---------|
| `Resource` | Base class for loadable resources |
| `ResourceManager<T>` | Abstract manager for specific resource types |
| `ResourceHandle<T>` | Reference-counted handle to a resource |
| `ResourceSystem` | Coordinates async loading across managers |

#### Sedulous.Jobs

| Type | Purpose |
|------|---------|
| `Job` | Base class for background work |
| `JobGroup` | Collection of jobs that complete together |
| `JobSystem` | Schedules and executes jobs on worker threads |
| `JobPriority` | Low, Normal, High, Critical |

### Key Design Patterns

1. **Struct vs Class**: Use structs for small value types (Vector3, EntityId, Transform). Use classes for entities, components, and systems.

2. **Ownership**: Objects are typically owned by their containers. Destructors use `DeleteContainerAndItems!(_)` for owned lists.

3. **Reference Counting**: Resources use reference counting via `ResourceHandle<T>`.

4. **Event System**: `EventAccessor<T>` provides thread-safe event subscription with Friend access for invocation.

5. **Serialization**: Types implement `ISerializable` with version support. Polymorphic types use `ISerializableFactory`.

---

## RHI (Render Hardware Interface)

### Architecture

```
Sedulous.RHI              - Core interfaces and descriptors
Sedulous.RHI.Vulkan       - Vulkan backend implementation
Sedulous.RHI.HLSLShaderCompiler - HLSL→SPIRV compilation via DXC
RHI.SampleFramework       - Base class for samples
```

### Key Types

| Type | Purpose |
|------|---------|
| `IBackend` | Creates adapters, enumerates GPUs |
| `IDevice` | Resource factory, main entry point |
| `ISwapChain` | Presentation to window |
| `IBuffer` | GPU buffer (vertex, index, uniform, storage) |
| `ITexture`, `ITextureView` | GPU textures and views |
| `IShaderModule` | Compiled shader bytecode |
| `IBindGroupLayout`, `IBindGroup` | Resource binding |
| `IRenderPipeline`, `IComputePipeline` | Pipeline state objects |
| `ICommandEncoder`, `IRenderPassEncoder` | Command recording |

### Shader Bindings

The RHI automatically applies Vulkan binding shifts. Use **HLSL register numbers** directly:

```beef
// HLSL: cbuffer Uniforms : register(b0), Texture2D tex : register(t0), SamplerState samp : register(s0)

BindGroupLayoutEntry[3] layoutEntries = .(
    BindGroupLayoutEntry.UniformBuffer(0, .Vertex),    // b0
    BindGroupLayoutEntry.SampledTexture(0, .Fragment), // t0
    BindGroupLayoutEntry.Sampler(0, .Fragment)         // s0
);
```

Internal Vulkan shifts (DO NOT use manually): b+0, t+1000, u+2000, s+3000

### Matrix Convention (Row-vector)

```beef
// Beef uses row-vector convention: vector * matrix
// Multiplication order reads left-to-right
MVP = Model * View * Projection;

// Transform composition: Scale → Rotate → Translate
WorldMatrix = Scale * Rotation * Translation;

// HLSL uses mul(matrix, vector) - cbuffer matrices get implicit transpose
// This makes Beef's view * proj work with HLSL's mul(viewProj, position)
```

### RHI Sample Framework

```beef
class MySample : RHISampleApp
{
    public this() : base(.() {
        Title = "My Sample",
        Width = 800, Height = 600,
        ClearColor = .(0.1f, 0.1f, 0.1f, 1.0f),
        EnableDepth = true
    }) { }

    protected override bool OnInitialize() { return true; }
    protected override void OnUpdate(float dt, float total) { }
    protected override void OnPrepareFrame(int32 frameIndex) { /* Write per-frame buffers here */ }
    protected override bool OnRenderFrame(ICommandEncoder encoder, int32 frameIndex) { return false; }
    protected override void OnRender(IRenderPassEncoder pass) { }
    protected override void OnCleanup() { }
}
```

**Frame Lifecycle:**
1. `OnUpdate()` - Game logic only, NO buffer writes
2. `AcquireNextImage()` - Waits for fence, gets frame slot
3. `OnPrepareFrame(frameIndex)` - Safe to write per-frame buffers
4. `OnRenderFrame(encoder, frameIndex)` - Record render commands

---

## Renderer Architecture

**Project:** `Sedulous.Framework.Renderer`

**Dependencies:** corlib, Sedulous.Foundation, Sedulous.Mathematics, Sedulous.Logging, Sedulous.RHI, Sedulous.Resources, Sedulous.Geometry, Sedulous.Imaging

**Note:** No dependency on Sedulous.Models. The renderer defines its own mesh/material representations. CPU assets come from Sedulous.Geometry (Mesh) and Sedulous.Imaging (Image).

### Architecture Layers

```
+------------------------------------------------------------------+
|                    Application / Game Layer                       |
+------------------------------------------------------------------+
|                      Sedulous.Renderer                            |
|  +------------------------------------------------------------+  |
|  |  RenderSystem (IContextService)                            |  |
|  |  - Orchestrates frame rendering, manages views/cameras     |  |
|  +------------------------------------------------------------+  |
|  |  RenderWorld (Proxies)  |   RenderGraph                    |  |
|  |  - MeshProxy            |   - Pass dependencies            |  |
|  |  - LightProxy           |   - Resource lifetime/aliasing   |  |
|  |  - CameraProxy          |   - Automatic barriers           |  |
|  +------------------------------------------------------------+  |
|  |  GPUResourceManager     |   MaterialSystem                 |  |
|  |  - GPUMesh, GPUTexture  |   - ShaderLibrary               |  |
|  |  - Staging uploads      |   - PipelineCache               |  |
|  +------------------------------------------------------------+  |
|  |  VisibilityResolver     |   LightingSystem                 |  |
|  |  - Frustum culling      |   - ClusterGrid                 |  |
|  |  - Hi-Z occlusion       |   - ShadowRenderer              |  |
|  +------------------------------------------------------------+  |
|  |  PostProcessStack                                          |  |
|  |  - HDR, Bloom, TAA, Tonemapping                           |  |
|  +------------------------------------------------------------+  |
+------------------------------------------------------------------+
|                         Sedulous.RHI                              |
+------------------------------------------------------------------+
```

### Core Subsystems

**1. RenderSystem (IContextService)** - Entry point registered with Context. Owns:
- IDevice, ISwapChain references
- GPUResourceManager, MaterialSystem, ShaderLibrary
- RenderGraph, RenderWorld
- ShadowRenderer, PostProcessStack
- FrameContext[3] for triple-buffering

**2. RenderWorld** - Manages render proxies decoupled from gameplay entities:
- `MeshProxy` - transform, bounds, GPU mesh/material handles, LOD, shadow flags
- `LightProxy` - type, position, color, intensity, range, shadow map index
- `CameraProxy` - view/projection matrices, frustum, jitter for TAA

**3. RenderGraph** - Frame-based pass management:
- `AddPass()` declares passes with read/write dependencies
- `CreateTransientTexture/Buffer()` for per-frame resources
- `ImportTexture()` for external resources (swapchain)
- `Compile()` - topological sort, aliasing, barrier insertion
- `Execute()` - run all passes in order

**4. GPUResourceManager** - Creates GPU resources from CPU assets:
- `GetOrCreateMesh(Sedulous.Geometry.Mesh)` → GPUMeshHandle
- `GetOrCreateTexture(Sedulous.Imaging.Image)` → GPUTextureHandle
- Staging buffer pool for async uploads
- Reference counting + garbage collection

**5. MaterialSystem:**
- `Material` - base shader, parameters, blend/cull modes
- `MaterialInstance` - per-object parameter values
- `ShaderLibrary` - loads shaders, manages variants
- `PipelineCache` - caches IRenderPipeline by key

**6. VisibilityResolver:**
- `FrustumCuller` - AABB-frustum tests
- `HiZOcclusionCuller` - GPU-driven occlusion (compute)
- `VisibilityList` - opaque/transparent/shadow caster indices
- LOD selection based on distance

**7. ClusterGrid (Clustered Lighting):**
- 16x9x24 cluster grid
- Compute shader builds clusters from camera
- Compute shader assigns lights to clusters
- Provides lighting bind group for forward pass

**8. ShadowRenderer:**
- `CascadedShadowMaps` - 4 cascades for directional light
- `ShadowAtlas` - point/spot light shadow tiles
- PCF filtering in shader

**9. PostProcessStack:**
- HDR render target (RGBA16F)
- Bloom (downsample chain + blur)
- TAA (jittered projection + history reprojection)
- Tonemapping + color grading (LUT)

### Key Design Decisions

1. **Proxy System** - Render proxies decoupled from entities. Proxies store cached transform + GPU handles. Game thread updates proxies, render thread reads them. Enables future multi-threading.

2. **Resource Ownership** - CPU resources (Mesh, Image, Model) owned by ResourceSystem. GPU resources (GPUMesh, GPUTexture) owned by GPUResourceManager. Transient resources owned by RenderGraph. Clear lifetime boundaries.

3. **Render Graph Benefits** - Automatic barrier insertion (no manual TextureBarrier calls). Resource aliasing reduces memory. Clear pass dependencies enable parallelism. Frame-scoped transients auto-cleanup.

4. **Clustered Forward vs Deferred** - Forward chosen for: transparency support without extra passes, MSAA friendly, simpler material system, good for moderate light counts (hundreds).

5. **Reverse-Z Depth** - Use Depth32Float with reverse-Z (near=1, far=0). Better precision at distance. DepthCompare = .Greater for depth test.

### Implementation Strategy

- **Scope:** All 7 phases - complete renderer implementation
- **Geometry:** All types from the start (static, skinned, sprites, particles, decals)
- **Render Graph:** Built from Phase 1 (not retrofitted)
- **Integration:** Standalone sample app first, Framework.Core integration later

### Framework Integration (Phase 7)

Entity components bridge Framework.Core entities to the renderer's proxy system:

```beef
class MeshRendererComponent : IEntityComponent
{
    ResourceHandle<ModelResource> Model;
    List<MaterialInstanceHandle> Materials;
    ProxyId mProxyId;  // Created by RenderSceneComponent
}

class LightComponent : IEntityComponent
{
    LightType Type;
    Color Color;
    float Intensity, Range, SpotAngle;
    bool CastsShadows;
}

class CameraComponent : IEntityComponent
{
    float FieldOfView, NearPlane, FarPlane;
    bool UseReverseZ, IsMain;
}
```

Scene component manages render state per scene:

```beef
class RenderSceneComponent : ISceneComponent
{
    RenderWorld mRenderWorld;
    Dictionary<EntityId, ProxyId> mEntityProxies;

    void OnUpdate(float dt) { SyncProxies(); }
}
```

### File Structure

```
Sedulous.Framework.Renderer/src/
├── RenderSystem.bf              # IContextService, main orchestrator
├── FrameContext.bf              # Per-frame GPU state
├── World/                       # MeshProxy, LightProxy, CameraProxy
├── Graph/                       # RenderGraph, RenderPass, TransientResourcePool
├── Resources/                   # GPUResourceManager, GPUMesh, GPUTexture
├── Materials/                   # MaterialSystem, ShaderLibrary, PipelineCache
├── Visibility/                  # FrustumCuller, VisibilityResolver
├── Lighting/                    # ClusterGrid, LightingSystem, Shadows
├── PostProcess/                 # HDR, Bloom, TAA, Tonemapping
├── Passes/                      # DepthPrePass, ForwardOpaquePass, etc.
└── Components/                  # Framework.Core integration components
```

### Critical Files to Reference

- `Sedulous.RHI/src/IDevice.bf` - Resource creation patterns
- `Sedulous.Geometry/src/Mesh.bf` - CPU mesh structure (VertexBuffer, IndexBuffer)
- `Sedulous.Geometry/src/VertexBuffer.bf` - Vertex data layout
- `Sedulous.Imaging/src/Image.bf` - CPU image/texture data
- `Sedulous.Resources/src/ResourceManager.bf` - Resource loading pattern
- `Sedulous.Framework.Core/src/Context/Context.bf` - IContextService pattern (for Phase 7)
- `Sedulous.Framework.Core/src/Entity/IEntityComponent.bf` - Component pattern (for Phase 7)
- `RHI.SampleFramework/src/RHISampleApp.bf` - Frame loop reference

---

## GPU/CPU Buffer Synchronization

### The Problem

With multiple frames in flight (typically 2), uniform buffers updated every frame can cause visual artifacts if not properly synchronized.

**Symptoms:**
- Artifacts appear "gradually" while holding a key that updates uniform data
- Artifacts disappear when the key is released
- Issue is intermittent and timing-dependent

**Root cause:** GPU may still be reading from a uniform buffer for frame N while CPU is writing new data for frame N+1 to the same buffer.

### Solution: Per-Frame Buffers

```beef
// Instead of:
private IBuffer mCameraBuffer;

// Use:
private IBuffer[MAX_FRAMES_IN_FLIGHT] mCameraBuffers;
```

Select the appropriate buffer using the current frame index:

```beef
let frameIndex = SwapChain.CurrentFrameIndex;
Device.Queue.WriteBuffer(mCameraBuffers[frameIndex], 0, data);
```

**Important:** Bind groups that reference per-frame buffers must also be per-frame.

### Quick Debugging

```beef
// Add this before buffer writes to verify if issue is synchronization:
Device.WaitIdle();  // Eliminates all races (but kills performance)
```

### When Single Buffers Are Fine

1. Static geometry (vertex/index buffers that don't change)
2. Textures (typically immutable after upload)
3. Buffers only written once during initialization

---

## Common Issues and Solutions

### "Cannot assign to read-only captured local variable"
Add `[&]` to lambda for reference capture:
```beef
int counter = 0;
delegate void() fn = new [&] () => { counter++; };
```

### "Unable to implicitly cast 'T' to 'Interface'"
Add explicit cast in generic factory:
```beef
delegate IEntityComponent() factory = new () => (IEntityComponent)new T();
```

### Type mismatch with serialization (int vs int32)
Use explicit `int32` type for serialized fields.

### Modifying collection while iterating
Copy collection before iteration:
```beef
List<EntityId> childrenToDestroy = scope .();
childrenToDestroy.AddRange(entity.ChildIds);
for (let childId in childrenToDestroy)
    DestroyEntity(childId);
```

---

## Samples

### RHI Samples
| Sample | Demonstrates |
|--------|-------------|
| `RHITriangle` | Basic triangle rendering |
| `RHITexturedQuad` | Texture sampling with UV coordinates |
| `RHIDepthBuffer` | Depth testing with 3D cubes |
| `RHIBlending` | Alpha blending modes |
| `RHIInstancing` | Hardware instancing |
| `RHIBindGroups` | Multiple bind groups demonstration |
| `RHIMipmaps` | Mipmap generation and sampling |
| `RHIMRT` | Multiple render targets (G-buffer style) |
| `RHICompute` | Compute shader execution |
| `RHIQueries` | Timestamp and occlusion queries |
| `RHIReadback` | GPU to CPU data readback |
| `RHIWireframe` | Wireframe rendering with FillMode toggle |
| `RHIMSAA` | 4x MSAA with manual ResolveTexture |
| `RHIBorderSampler` | Border color sampling with ClampToBorder |
| `RHIBlit` | Render-to-texture with Blit for texture scaling |

### Renderer Samples
| Sample | Demonstrates |
|--------|-------------|
| `RendererTriangle` | Render graph basics |
| `RendererPBR` | PBR materials and shaders |
| `RendererScene` | 1200 instanced cubes with frustum culling |
| `RendererLighting` | Clustered lighting with cascaded shadows |
| `RendererShadow` | Shadow mapping development/testing |

### Framework Samples
| Sample | Demonstrates |
|--------|-------------|
| `Sandbox` | Console program for framework experimentation |
| `ResourcesSample` | Resource system usage |
| `ShellSample` | Windowing and input |
| `AudioSample` | Audio system with 3D spatialization |

---

## File Naming Conventions

- One primary type per file: `Scene.bf`, `EntityManager.bf`
- Test files: `<TypeName>Tests.bf`
- Extension files: `<TypeName>Extensions.bf`
- Interfaces: `I<Name>.bf`

---

## Next Steps

Priority order for remaining work:

1. **Sedulous.Framework.Renderer** - Complete Phase 6 (Post-Processing) and Phase 7 (Polish & Integration)
2. **Sedulous.Framework.Input** - Input action mapping, gesture detection
3. **Sedulous.Runtime** - Application lifecycle, main loop integration
4. **Sedulous.RHI.DX12** - DirectX 12 backend (optional, Vulkan backend is complete)
