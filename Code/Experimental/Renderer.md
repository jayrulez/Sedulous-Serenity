# Sedulous.Renderer — Comprehensive Implementation Plan

A production-quality renderer built on Sedulous RHI, RenderGraph, and ShaderCompiler. Designed for game engines, decoupled from any ECS, with all features of the legacy Sedulous.Render and architectural improvements.

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────┐
│                        Game / Application                        │
│              (ECS, Scene Graph, Editor, etc.)                    │
├──────────────────────────────────────────────────────────────────┤
│                      Sedulous.Renderer                            │
│  ┌────────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────────┐  │
│  │ RenderWorld│ │ Features │ │ PostFX   │ │ Resource Manager │  │
│  │  (Proxies) │ │ (Passes) │ │ (Stack)  │ │ (GPU Lifetime)   │  │
│  └─────┬──────┘ └────┬─────┘ └────┬─────┘ └────────┬─────────┘  │
│        │             │            │                 │            │
│  ┌─────┴─────────────┴────────────┴─────────────────┴─────────┐  │
│  │              RenderSystem (Frame Orchestrator)              │  │
│  └────────────────────────────┬────────────────────────────────┘  │
├───────────────────────────────┼──────────────────────────────────┤
│  ┌────────────────────────────┴────────────────────────────────┐  │
│  │              Sedulous.RenderGraph                             │  │
│  │   (Pass scheduling, barriers, transient resources, sync)    │  │
│  └────────────────────────────┬────────────────────────────────┘  │
│  ┌────────────────────────────┴────────────────────────────────┐  │
│  │              Sedulous.RHI (RHI)                              │  │
│  │   (IDevice, IQueue, Pipelines, Buffers, Textures, etc.)    │  │
│  └─────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

### Key Architectural Decisions

1. **Proxy-based ECS decoupling** — Game code creates/updates lightweight proxy handles in `RenderWorld`. The renderer never knows about entities, components, or scene graphs.

2. **Feature-based modular pipeline** — Rendering passes are encapsulated in `IRenderFeature` implementations with declared dependencies. Features add passes to the RenderGraph each frame.

3. **RenderGraph-driven execution** — All GPU work goes through the render graph. No manual barrier management, no ad-hoc command recording outside of passes.

4. **Self-contained material system** — Materials are defined entirely within the renderer (shader name + properties + render state). No dependency on external material libraries.

5. **GPU-driven rendering where practical** — GPU culling, indirect draw buffers, and instance merging for high object counts. CPU fallback for simpler scenes.

6. **Shader compilation integrated** — ShaderCompiler moves from SampleFramework into the renderer as a first-class subsystem with variant management and caching.

7. **Bindless-ready** — Design bind group layouts to support bindless descriptor indexing where hardware allows, with traditional binding fallback.

8. **Fully async initialization** — All GPU resource uploads during feature init go through a shared `ITransferBatch`. No feature may do synchronous GPU work during init. The entire init sequence is: create CPU-side data → queue into shared transfer batch → single `SubmitAsync` at the end of `RenderSystem.Initialize()` → first frame waits on the init fence. This eliminates the legacy problem where individual features did their own uploads (some synchronous) causing long startup times.

---

## Dependencies

```toml
[Dependencies]
corlib = "*"
"Sedulous.RHI" = "*"
"Sedulous.RenderGraph" = "*"
"Sedulous.Geometry" = "*"
```

The renderer depends on:
- **Sedulous.RHI** — GPU abstraction (interfaces only, no backend)
- **Sedulous.RenderGraph** — Pass scheduling, barriers, transient resources
- **Sedulous.Geometry** — Canonical mesh format (`StaticMesh`, `SkinnedMesh`, `MeshBuilder`). This is the universal mesh interchange format shared by the renderer, physics, navigation, and other consumers. The renderer owns the vertex layout definition through this dependency.

Backend selection (Vulkan, DX12, Null) is the application's responsibility.

ShaderCompiler (DXC-based) is an optional compile-time dependency — the renderer can accept pre-compiled shader bytecode or compile at runtime.

---

## Sedulous.Geometry — Canonical Mesh Format

`Sedulous.Geometry` is a standalone, GPU-agnostic mesh data library. It defines the canonical vertex formats consumed by the renderer, physics, navigation, and any other system that needs mesh data. No system depends on the renderer to use geometry — they all depend on `Sedulous.Geometry` directly.

```
Sedulous.Models (GLTF/FBX)
        ↓
Sedulous.Geometry.Tooling (convert to canonical format)
        ↓
Sedulous.Geometry (StaticMesh, SkinnedMesh, MeshBuilder)
      ↙     ↓      ↘
Renderer  Physics  Navigation
```

### Vertex Formats

- **StaticMeshVertex** (48 bytes, CRepr): `Position(Vector3)` + `Normal(Vector3)` + `TexCoord(Vector2)` + `Color(uint32)` + `Tangent(Vector3)`
- **SkinnedMeshVertex** (72 bytes): StaticMeshVertex + `JointIndices(uint16[4])` + `BoneWeights(float[4])`

### MeshBuilder

Factory methods for procedural primitives: `CreateCube`, `CreateSphere`, `CreateCylinder`, `CreateCone`, `CreateTorus`, `CreatePlane`, `CreateQuad`, `CreateTriangle`

Supports custom vertex formats via `Initialize(vertexSize)` + `SetVertexAttribute<T>()`, but the standard path is `SetupCommonVertexFormat()` which matches `StaticMeshVertex` layout.

All factory methods call `GenerateNormals()`, `GenerateTangents()`, `CalculateBounds()` automatically. Output is `StaticMesh` via `Build()`.

### Mesh Pipeline (Source → GPU)

```
MeshBuilder.CreateCube()  →  StaticMesh (CPU, 48B vertices)
  or
ModelLoader.Load("model.gltf")  →  Tooling.Convert()  →  StaticMesh

Then:
  GPUResourceManager.UploadMesh(staticMesh)  →  GPUMeshHandle
  RenderWorld.SetStaticMeshData(proxy, meshHandle, bounds)
```

`GPUResourceManager.UploadMesh()` has two overloads:
1. **`UploadMesh(StaticMesh)`** — Primary path. Reads vertex/index data directly from StaticMesh, uses known 48-byte stride and UInt32 index format.
2. **`UploadMesh(Span<uint8> vertexData, ...)`** — Raw byte path for custom vertex formats or external mesh sources.

---

## Foundation Library Integration

The following libraries are NOT dependencies of `Sedulous.Renderer` — the application/framework bridges them.

### Sedulous.Models — Model Loading (GLTF + FBX)

- **ModelLoaderFactory**: Loads `.gltf`, `.glb`, `.fbx` files → `Model` container
- **Model**: Contains meshes, materials, bones, skins, animations, textures
- **ModelMesh**: Flexible vertex format with semantic-based elements (Position, Normal, Tangent, TexCoord, Color, Joints, Weights)
- **ModelMaterial**: Albedo, normal, metallic, roughness, AO texture indices + color overrides
- **ModelAnimation**: Per-bone keyframe tracks with Linear/Step/CubicSpline interpolation
- **Integration**: Model → `Sedulous.Geometry.Tooling` converts to `StaticMesh`/`SkinnedMesh` → renderer uploads

### Sedulous.Geometry.Tooling — Format Conversion (not yet ported)

- Converts `Sedulous.Models.ModelMesh` (arbitrary vertex elements) → `Sedulous.Geometry.StaticMesh`/`SkinnedMesh` (canonical 48/72-byte format)
- Handles attribute remapping, tangent generation for missing tangents, vertex deduplication
- Needs refactor when ported to the new codebase
- **Integration**: Sits between Models and Geometry in the asset pipeline

### Sedulous.Imaging — Image/Texture Loading

- **Image**: CPU-side pixel buffer with format conversion (R8 through RGBA32F)
- **ImageLoaderFactory**: Loads PNG, JPG, BMP, TGA, HDR via stb_image
- **Factory methods**: `CreateSolidColor`, `CreateCheckerboard`, `CreateGradient`
- **Integration**: Image → `GPUResourceManager.UploadTexture()` → GPUTextureHandle → MaterialInstance

### Sedulous.Animation — Skeletal Animation

- **AnimationPlayer**: Simple clip playback with `GetSkinningMatrices()` / `GetPrevSkinningMatrices()`
- **AnimationGraphPlayer**: State machine with blend trees, layers, transitions
- **Skeleton**: Bone hierarchy with bind pose
- **Integration**: AnimationPlayer output → GPUBoneBuffer → GPUSkinningFeature compute shader

### Sedulous.Drawing — 2D Rendering

- **DrawContext**: CPU-side command recorder producing `DrawBatch` (vertices, indices, texture refs)
- **Operations**: Lines, rects, rounded rects, circles, ellipses, arcs, polygons, text, images, gradients
- **State stacks**: Transform, clip rect, opacity (all independent)
- **DrawVertex**: Position(8) + TexCoord(8) + Color(4, packed RGBA)
- **Integration**: DrawContext → DrawBatch → OverlayFeature consumes as 2D layer

### Sedulous.Fonts — Font Rendering

- **FontManager**: Registry for loaded fonts, per-size glyph atlases
- **IFont**: Glyph info, kerning, string measurement
- **IFontAtlas**: Texture atlas with UV lookup per glyph
- **Integration**: FontManager → glyph atlas GPU texture → DrawContext.DrawText() → overlay rendering

---

## Legacy Parity Assessment

The new Sedulous.Renderer must match or exceed the legacy Sedulous.Render in all areas. Current status:

| Area | Legacy | New Renderer | Status |
|------|--------|-------------|--------|
| **Architecture** | Partial render graph, some manual barriers | Full RenderGraph, automatic barriers | Better |
| **ECS Decoupling** | Proxy-based, but some ECS leakage | Fully proxy-based, zero ECS dependency | Better |
| **Initialization** | Mixed sync/async, per-feature uploads | Single shared TransferBatch, zero stalls | Better |
| **Frustum Culling** | AABB + Sphere, CPU | AABB + Sphere, CPU (Phase 4 done) | Parity |
| **LOD Selection** | Distance-based, 4 levels | Distance-based, 4 levels, bias control (Phase 4 done) | Parity+ |
| **Draw Batching** | Auto-instancing by material+mesh | Dictionary-based O(n) grouping (Phase 4 done) | Parity |
| **Instance Buffers** | Per-frame ring buffer | Per-frame ring buffer, persistent map (Phase 4 done) | Parity |
| **Sort Keys** | Material-first opaque, depth-first transparent | Same strategy, 64-bit packed keys (Phase 4 done) | Parity |
| **Depth Prepass** | Yes, with Hi-Z | Depth-only prepass (Phase 5 done), Hi-Z planned (Phase 17) | Partial |
| **Forward PBR** | Cook-Torrance, metallic/roughness | Cook-Torrance with hardcoded directional light (Phase 5 done) | Partial |
| **Clustered Lighting** | 16x9x24, 1024 lights | In progress (Phase 6) | Pending |
| **Shadows** | 4-cascade CSM + atlas | Step A (CSM) done, Step B (atlas) pending | In Progress |
| **Transparent** | Back-to-front, per-material blend | Planned (Phase 8) | Pending |
| **Motion Vectors** | Full-screen + per-object | Planned (Phase 8) | Pending |
| **Post-Processing** | 15 effects | Planned (Phase 9) | Pending |
| **Sky/IBL** | Preetham + HDRI + solid | Planned (Phase 10) | Pending |
| **GPU Skinning** | Compute-based | Planned (Phase 11) | Pending |
| **Particles** | CPU + GPU, trails | Planned (Phase 12) | Pending |
| **Terrain/Water/Grass** | All present | Planned (Phase 13) | Pending |
| **Decals/Sprites** | Box + curve decals, billboards | Planned (Phase 14) | Pending |
| **Volumetric Fog** | Froxel-based | Planned (Phase 15) | Pending |
| **Reflection Probes** | Parallax-corrected cubemaps | Planned (Phase 16) | Pending |
| **GPU-Driven** | Not present | Planned (Phase 17) | New |
| **Overlay/Debug** | Full overlay system | Planned (Phase 18) | Pending |
| **Pipeline Caching** | Yes | Yes, with disk serialization (Phase 3 done) | Better |
| **Shader Variants** | Define-based | Define-based with lazy compilation (Phase 3 done) | Parity |
| **Material System** | Properties + bind groups | Properties + bind groups + definitions (Phase 3 done) | Parity |
| **Resource Management** | Ref-counted, deferred delete | Ref-counted, deferred delete (Phase 2 done) | Parity |
| **Async Compute** | Not present | Planned (Phase 20) | New |

**Key improvements over legacy:**
1. GPU-driven indirect draw pipeline (200K+ objects at minimal CPU cost)
2. Async compute overlap (light culling, Hi-Z, particles parallel with rendering)
3. Full render graph integration (automatic barrier management, pass culling, resource aliasing)
4. Zero-stall initialization (single async transfer batch for all features)
5. Pipeline disk caching via IPipelineCache
6. Bindless-ready bind group design

---

## Per-Frame Data Flow (Phase 4 → Phase 6+)

Understanding how data flows each frame from the proxy world through visibility culling, batching, and finally into GPU draw calls.

### Pre-Graph vs Graph Work

GPU work is split into two phases on the command encoder:

**Pre-graph (raw encoder):** Fixed infrastructure work that produces buffers consumed by all subsequent passes. Runs unconditionally, has no transient resources, and uses simple fixed barriers. Not worth graph scheduling overhead.

**Graph passes:** Render/compute passes with texture dependencies that benefit from automatic barrier solving, transient resource allocation, and pass culling.

**Guideline:** If a compute dispatch produces a buffer read by multiple passes, runs every frame unconditionally, and has fixed barriers — it belongs pre-graph. If it produces textures, has conditional dependencies, or could be culled — it belongs in the graph.

| Pre-Graph | Graph |
|-----------|-------|
| Uniform upload (staging → GPU copy) | Depth prepass |
| Light data upload (staging → GPU copy) | Forward opaque |
| Cluster light culling (compute) | Forward transparent |
| Shadow cascade depth passes (render) | Post-processing |
| GPU skinning (compute, Phase 11) | Tonemap blit |
| GPU culling (compute, Phase 17) | |

**Exception — shadow cascade passes pre-graph:** Shadow cascade depth rendering writes to per-layer views of a `Texture2DArray`. Our render graph currently imports textures with a single view; per-layer sub-resource import would add complexity for a single use case. Since shadow passes run unconditionally when a shadow caster exists, always render to the same texture, and have fixed barriers (Undefined/ShaderRead → DepthWrite → ShaderRead per layer), they fit the pre-graph pattern. The legacy renderer used graph passes by importing each per-layer `ITextureView` as a separate resource — a valid approach, but one that could be adopted later if the graph gains native array layer support.

### Frame Sequence

```
┌─────────────────────────────────────────────────────────────────────────┐
│ RenderSystem.Render(view, swapChain)                                   │
│                                                                         │
│  1. CPU-side preparation                                               │
│     ViewContext.Update(view)             ← camera matrices, frustum    │
│     LightingSystem.Update(world)         ← write light data to staging │
│     ShadowSystem.Update(world, viewCtx)  ← cascade matrices → mapped  │
│     FrameContext.UploadUniforms()         ← SceneUniforms → mapped buf │
│     VisibilityResolver.Resolve()         ← frustum cull, LOD, sorting  │
│     DrawBatcher.Build()                  ← group draws by state        │
│                                                                         │
│  2. Features add graph passes                                          │
│     DepthPrepass, ForwardOpaque, BlitToScreen, etc.                    │
│                                                                         │
│  3. RenderGraph.Compile() + PrepareExecution()                         │
│                                                                         │
│  4. Pre-graph GPU work (raw encoder)                                   │
│     ┌──────────────────────────────────────────────────────────────┐    │
│     │ RecordUpload    CopyBufferToBuffer(staging → lightBuffer)   │    │
│     │ RecordCull      Clear atomic counter                        │    │
│     │                 Barrier: lightBuf CopyDst→ShaderRead        │    │
│     │                          cluster/index bufs →ShaderWrite    │    │
│     │                 BeginComputePass("LightCull")               │    │
│     │                   Dispatch(54) — 3456 clusters / 64 threads │    │
│     │                 End                                          │    │
│     │                 Barrier: cluster/index bufs →ShaderRead     │    │
│     │ (Phase 11)      RecordSkinning — bone transforms → verts   │    │
│     │ (Phase 17)      RecordGPUCull — indirect draw buffers      │    │
│     │                                                              │    │
│     │ RecordShadowPasses (per cascade 0..3):                      │    │
│     │   Barrier: layer[i] ShaderRead→DepthStencilWrite            │    │
│     │   BeginRenderPass(cascadeLayerView[i], clear depth=1.0)     │    │
│     │     Draw shadow casters (depth-only pipeline)               │    │
│     │   End                                                        │    │
│     │   Barrier: layer[i] DepthStencilWrite→ShaderRead            │    │
│     └──────────────────────────────────────────────────────────────┘    │
│                                                                         │
│  5. Graph pass execution (scheduled order)                             │
│     ┌──────────────────────────────────────────────────────────────┐    │
│     │ DepthPrepass  → SceneDepth texture                          │    │
│     │ ForwardOpaque → HDR color (reads cluster/light/index/       │    │
│     │                  shadow cascade texture + shadow uniforms)   │    │
│     │ BlitToScreen  → Tonemap HDR → swapchain                    │    │
│     └──────────────────────────────────────────────────────────────┘    │
│                                                                         │
│  6. Present swapchain                                                  │
└─────────────────────────────────────────────────────────────────────────┘
```

**Why `PrepareExecution()` + manual pass loop instead of `RenderGraph.Execute()`:**

`RenderGraph.Execute()` is a self-contained record+submit pipeline: it creates its own command pools/encoders (one per queue type), records all passes, handles cross-queue sync via timeline fences, and submits. The renderer can't use it because:

1. **Pre-graph GPU work** — Light upload, GPU culling, skinning, and shadow cascade passes must be recorded into the **same command list** before graph passes. `Execute()` creates fresh encoders with no way to prepend work.
2. **Command pool lifecycle** — The renderer owns per-frame command pools with fence-gated reset (and DX12 descriptor staging tied to pool lifetime). `Execute()` would create separate pools that bypass this.
3. **Present barrier** — The backbuffer → Present transition must happen after the last graph pass but before submit. `Execute()` doesn't know about present semantics.

Instead, the renderer calls `PrepareExecution()` (allocates transient resources, solves barriers) then manually iterates `GetScheduledPass(i)` + `GetBarriersForPass(i)` on its own encoder. Debug labels are emitted around each pass for RenderDoc visibility.

**Shared per-frame state** (owned by RenderSystem, passed to features):
- `LightingSystem` — light upload, cluster culling, exposes light/cluster/index buffers
- `ShadowSystem` — cascade shadow map rendering, exposes shadow uniforms/texture/sampler for scene bind group
- `VisibilityResolver` — single instance, results reused across depth prepass + forward opaque
- `DrawBatcher` — single instance, batches reused across passes that draw the same geometry
- `ObjectUniformManager` — single per-frame buffer, features allocate from it
- `InstanceBufferManager` — single per-frame ring buffer

---

## Feature Inventory (Legacy Parity + Improvements)

### From Legacy Renderer (Sedulous.Render)
- [x] Forward+ clustered lighting pipeline
- [x] Depth prepass with Hi-Z pyramid
- [x] Motion vector generation
- [x] Separate opaque and transparent passes
- [x] PBR metallic/roughness shading (Cook-Torrance)
- [x] Clustered light culling (16x9x24 grid, 1024 lights)
- [x] Directional light with 4-cascade shadow maps
- [x] Point/spot light shadow atlas
- [x] Area lights (rectangle, disc)
- [x] IBL (irradiance + prefiltered cubemap + BRDF LUT)
- [x] Reflection probes
- [x] GPU skeletal animation (bone matrices compute)
- [x] LOD selection (distance-based, 4 levels)
- [x] Frustum culling (AABB + sphere)
- [x] Hi-Z occlusion culling
- [x] Draw batching with auto-instancing
- [x] Dynamic pipeline caching
- [x] Multi-view rendering (split-screen, up to 4 views)
- [x] TAA (16-sample Halton jitter)
- [x] Post-processing stack: Bloom, SSAO, SSR, DOF, Motion Blur, Tonemapping, FXAA, Auto Exposure, Vignette, Film Grain, Chromatic Aberration, Color Grading, Contact Shadows, Sharpen
- [x] Procedural sky (Preetham/Hosek) + HDRI + solid color
- [x] Particle system (CPU + GPU)
- [x] Trail particles
- [x] Terrain rendering
- [x] Water surfaces
- [x] Grass/vegetation instancing
- [x] Volumetric fog
- [x] Deferred decals (box + curve-based)
- [x] Sprite billboards
- [x] Overlay rendering (lines, shapes, filled quads, 3D text, 2D text — both depth-tested and overlay modes)
- [x] Per-frame statistics
- [x] Deferred GPU resource deletion
- [x] Handle-based proxy pools with generation validation

### Architectural Improvements Over Legacy
- [ ] Full RenderGraph integration (legacy had partial)
- [ ] GPU-driven indirect draw pipeline (DrawIndirect/MultiDrawIndirect)
- [ ] GPU frustum + occlusion culling compute pass
- [ ] Merged instance buffer with GPU compaction
- [ ] Bindless texture/sampler support (where available)
- [ ] Shader variant system with compile-time permutations + runtime specialization constants
- [ ] Pipeline state object (PSO) pre-warming and disk caching via `IPipelineCache`
- [ ] Async compute for light culling, Hi-Z, particle simulation
- [ ] Better shadow quality: PCF, PCSS, or VSM options
- [ ] Improved temporal stability (TAA with neighborhood clamping, velocity rejection)
- [ ] Resource streaming hooks (texture/mesh LOD streaming)
- [ ] Fully async initialization — zero synchronous GPU uploads during startup
- [ ] Configurable render pipeline presets (Forward+, Deferred, Simple Forward)

---

## Phased Implementation Plan

---

### Phase 1: Core Framework

**Goal:** Establish the renderer skeleton — project structure, RenderSystem lifecycle, RenderWorld with basic proxies, FrameContext, and a minimal "clear screen" pass through the render graph.

**Files:**
```
Sedulous.Renderer/
  BeefProj.toml
  src/
    RenderSystem.bf          — Frame lifecycle orchestrator
    RenderConfig.bf          — All configuration constants
    RenderWorld.bf           — Proxy pool container
    RenderView.bf            — Camera/viewport with frustum + TAA jitter
    FrameContext.bf           — Per-frame data (timing, frame number) + multi-buffered uniform upload
    ViewContext.bf            — Per-view data (camera, dimensions, render target, uniforms)
    IRenderFeature.bf         — Feature interface + base class
    RenderStats.bf            — Per-frame statistics
    Proxies/
      ProxyPool.bf            — Generic handle-based pool (index + generation)
      ProxyHandle.bf          — Handle types for all proxy kinds
      MeshProxy.bf            — Static mesh (transform, bounds, flags, materials)
      LightProxy.bf           — Light (type, color, range, shadows, area shape)
      CameraProxy.bf          — Camera (perspective/ortho, frustum planes)
```

**RenderSystem API:**
```
SetShaderCompiler(IShaderCompiler)    — must be called before Initialize()
RegisterFeature(IRenderFeature)       — must be called before Initialize()
Initialize(IDevice, IQueue graphicsQueue, IQueue? computeQueue)
SetActiveWorld(RenderWorld)
BeginFrame(float totalTime, float deltaTime)
Render(RenderView view, ISwapChain)   — renders one view, submits, presents
RenderFromWorld(ISwapChain)           — convenience: renders from active world's main camera
Shutdown()
GetFeature<T>()
Stats → RenderStats
```

**Async Initialization Protocol:**

The legacy renderer suffered from slow startup because individual features would do their own GPU uploads during `OnInitialize()` — some synchronous (full GPU stall), some batched but submitted separately. The new design eliminates this entirely:

```
RenderSystem.Initialize():
  1. Create shared ITransferBatch (via graphicsQueue.CreateTransferBatch())
  2. Create shared IFence for init completion
  3. For each registered feature:
     feature.OnInitialize(InitContext)
       — InitContext provides: IDevice, ITransferBatch (shared), GPUResourceManager, ShaderLibrary, RenderPipelineCache
       — Features create CPU-side data and queue uploads via shared transfer batch
       — Features MUST NOT call Queue.Submit(), WaitIdle(), or create their own transfers
       — Features create pipelines, bind group layouts, etc. (these are CPU-only, no upload)
  4. Single TransferBatch.SubmitAsync(initFence, 1)  — ONE async submit for all features
  5. First BeginFrame() waits on initFence before proceeding
```

This means:
- **Zero synchronous GPU stalls during init** — all uploads batched into one async submit
- **Features cannot accidentally do sync work** — they only see `InitContext`, not raw queues
- **First frame pays the wait** — but the GPU has been working in parallel during any post-init CPU setup
- **Fallback textures** (1x1 white, 1x1 black, 1x1 normal, dummy shadow maps) are all queued through the same batch

**InitContext (passed to features during init):**
```
IDevice Device                    — For creating pipelines, layouts, buffers, textures
ITransferBatch TransferBatch      — For queueing uploads (shared, do NOT submit)
GPUResourceManager Resources      — For registering meshes/textures with lifecycle management
ShaderLibrary Shaders             — For registering/compiling shader variants
```

**IMPORTANT — ProxyPool and struct field initializers:**

`ProxyPool<T>.Allocate()` uses `mProxies.Add(default)` which zeroes all fields, ignoring Beef struct field initializers (e.g., `LightProxy.OuterConeAngle = 0.52f` becomes 0). Any `Create*` method in `RenderWorld` must explicitly initialize the proxy with `*ptr = T()` after allocation to apply the struct's field defaults. Failing to do this caused spot lights to be invisible (OuterConeAngle=0 → cos(0)=1.0 as smoothstep edge0 > edge1 → always returns 0).

**RenderWorld Proxy API (initial set):**
```
CreateMesh() → MeshProxyHandle
DestroyMesh(MeshProxyHandle)
SetMeshTransform(handle, Matrix4x4)
SetMeshData(handle, GPUMeshHandle, BoundingBox)
SetMeshMaterial(handle, int slot, MaterialHandle)
SetMeshFlags(handle, MeshFlags)

CreateLight(LightType) → LightProxyHandle
DestroyLight(LightProxyHandle)
SetLightTransform(handle, position, direction)
SetLightColor(handle, Vector3 color, float intensity)
SetLightRange(handle, float)
SetLightShadows(handle, bool enabled, float bias, float normalBias)

CreateCamera() → CameraProxyHandle
DestroyCamera(CameraProxyHandle)
SetCameraLookAt(handle, Vector3 pos, Vector3 target, Vector3 up)
SetCameraPerspective(handle, float fov, float near, float far)
SetMainCamera(handle)
```

**FrameContext (per-frame, constant across views):**
```
TotalTime, DeltaTime, FrameNumber
AdvanceFrame()                    — selects frame buffer slot
UploadUniforms(ViewContext) → SceneUniforms — builds + uploads per-view
CurrentUniformBuffer              — the active frame slot's UBO
```

**ViewContext (per-view, populated per Render() call):**
```
RenderWidth, RenderHeight         — render target dimensions
RenderTarget                      — RGTexture handle for output
CameraPosition, CameraForward     — camera world-space
ViewMatrix, ProjectionMatrix      — view/projection matrices
ViewProjectionMatrix              — combined VP
PrevViewProjectionMatrix          — previous frame VP (motion vectors / TAA)
NearPlane, FarPlane               — clip distances
Frustum                           — BoundingFrustum for culling
SceneUniformBuffer                — IBuffer for binding in passes
Uniforms                          — SceneUniforms snapshot
```

**SceneUniforms (CRepr, 448 bytes):**
```
Matrix4x4 ViewMatrix
Matrix4x4 ProjectionMatrix
Matrix4x4 ViewProjectionMatrix
Matrix4x4 InverseViewMatrix
Matrix4x4 InverseProjectionMatrix
Matrix4x4 PrevViewProjectionMatrix
Vector3   CameraPosition      + float Time
Vector3   CameraForward       + float DeltaTime
Vector2   ScreenSize          + float NearPlane + float FarPlane
uint32    FrameNumber         + float[3] _pad
```

**IRenderFeature interface:**
```
StringView Name { get; }
Result<void> OnInitialize(InitContext initCtx)
void OnAddPasses(RenderGraph graph, FrameContext frameCtx, ViewContext viewCtx)
void OnPostRender()
void OnShutdown(IDevice device)
```

**RenderConfig constants:**
```
FrameBufferCount       = 2
MaxViews               = 4
MaxOpaqueObjects       = 200_000
MaxTransparentObjects  = 256
MaxLights              = 1024
MaxLightsPerCluster    = 256
ClusterCountX/Y/Z      = 16/9/24
ShadowCascadeCount     = 4
ShadowMapResolution    = 2048
ShadowAtlasSize        = 4096
MaxBonesPerMesh        = 256
MaxInstancesPerDraw    = 1024
MaxMaterialsPerMesh    = 32
```

**RenderView fields:**
```
Name, Width, Height, ViewportX, ViewportY, ViewIndex
CameraPosition, CameraForward, CameraUp
FieldOfView, NearPlane, FarPlane
ViewMatrix, ProjectionMatrix, ViewProjectionMatrix (computed)
PrevViewProjectionMatrix (for motion vectors)
FrustumPlanes[6] (extracted from VP)
TAAJitterState (Halton 2,3 sequence, 16 samples)
PostProcessSettings
OutputTarget, IsSwapChainTarget
```

**Proxy Flags:**
```
MeshFlags: Visible, CastShadows, ReceiveShadows, MotionVectors, Static
LightType: Directional, Point, Spot, Area
AreaLightShape: Rectangle, Disc
ProjectionType: Perspective, Orthographic
SortMode: None, FrontToBack, BackToFront, ByMaterial
```

**Deliverable:** `RenderSystem.Render()` clears the swap chain via a render graph pass. Proxies can be created/destroyed. Frame timing works.

---

### Phase 2: GPU Resource Management

**Goal:** Manage GPU meshes, textures, and bone buffers with reference counting, deferred deletion, and batched upload.

**Files:**
```
  src/
    Resources/
      GPUResourceManager.bf    — Central manager (mesh, texture, bone buffer)
      GPUMesh.bf               — Mesh data (VB, IB, submeshes, LODs, bounds)
      GPUTexture.bf            — Texture with default view, format, mips
      GPUBoneBuffer.bf         — Bone matrix storage buffer
      ResourceHandle.bf        — GPUMeshHandle, GPUTextureHandle, GPUBoneBufferHandle
```

**GPUMesh structure:**
```
IBuffer VertexBuffer, IndexBuffer
List<GPUSubMesh> SubMeshes       — (IndexStart, IndexCount, MaterialSlot)
List<GPUMeshLOD> LODs            — (FirstSubMesh, SubMeshCount)
BoundingBox LocalBounds
uint32 VertexCount, IndexCount
VertexFormat (position+normal+uv+tangent, or +boneWeights)
bool IsActive
```

**Resource lifecycle:**
- `UploadMesh(vertices, indices, submeshes, lods, bounds, ITransferBatch?) → GPUMeshHandle`
- `UploadTexture(data, format, width, height, mips, ITransferBatch?) → GPUTextureHandle`
- `CreateBoneBuffer(boneCount) → GPUBoneBufferHandle`
- `UpdateBoneBuffer(handle, currentMatrices, prevMatrices)`
- `AddRef(handle)` / `Release(handle, frameNumber)` — ref counting
- `ProcessDeletions(currentFrame)` — delete after `FrameBufferCount + 1` frames

**Upload strategy — solving the legacy startup time problem:**

Upload methods accept an optional `ITransferBatch`. This enables two distinct modes:

1. **Init-time (batched, async):** Pass the shared `InitContext.TransferBatch`. The upload is queued but not submitted. All features queue their uploads, then `RenderSystem.Initialize()` does a single `SubmitAsync`. Zero GPU stalls.

2. **Runtime (immediate):** Pass `null` or omit. The resource manager creates a temporary transfer batch, submits it, and waits. Used for loading new assets mid-game (e.g., streaming in a mesh). Can be made async by the caller managing their own transfer batch + fence.

This dual-mode approach means the same `UploadMesh`/`UploadTexture` API works for both init and runtime without features needing to know the difference.

**Built-in fallback resources** (queued during init via shared batch):
- 1x1 white texture, 1x1 black texture, 1x1 flat normal (0.5, 0.5, 1.0)
- 1x1 cubemap (white), dummy shadow map array (4x4x4 depth)
- BRDF LUT (512x512, one-time compute — dispatched in the first frame, not during init)

**Deliverable:** Meshes and textures can be uploaded, ref-counted, and deferred-deleted. Init uploads are fully async.

---

### Phase 3: Material & Shader System

**Goal:** Self-contained material system with shader variant compilation, pipeline caching, and bind group management.

**Files:**
```
  src/
    Materials/
      ShaderLibrary.bf          — Shader source registry + variant compilation
      ShaderVariant.bf          — Variant key (name + flags + format)
      MaterialDefinition.bf     — Material template (shader, properties, defaults)
      MaterialInstance.bf       — Per-instance property values + bind group
      MaterialProperty.bf       — Property descriptor (name, type, default, binding)
      MaterialHandle.bf         — Handle type
    Pipeline/
      RenderPipelineCache.bf    — Dynamic pipeline creation + disk caching
      PipelineKey.bf            — Cache key (shader, state, layout, formats)
      PipelineVariant.bf        — Variant flags enum
```

**ShaderLibrary:**
```
RegisterShader(StringView name, StringView hlslSource)
RegisterShaderFromFile(StringView name, StringView path)
GetCompiledShader(name, ShaderStage, ShaderOutputFormat, variantFlags) → IShaderModule
InvalidateAll()
SetCompiler(ShaderCompiler)
```

**Shader Variant Flags:**
```
None, Instanced, Skinned, ReceiveShadows, AlphaTest, MotionVectors, DepthOnly, ShadowCaster
```

Variants are compiled on-demand and cached. Each combination of (shader name + variant flags + output format) produces a unique `IShaderModule`.

**MaterialDefinition:**
```
Name: StringView
ShaderName: StringView
Properties: List<MaterialProperty>     — (name, type, default, binding slot)
BlendMode: BlendMode                   — Opaque, AlphaBlend, Additive, Multiply, PremulAlpha
CullMode: CullMode
DepthMode: DepthMode                   — ReadWrite, ReadOnly, WriteOnly, Disabled
RenderLayer: uint32                    — Bitmask for selective rendering
```

**MaterialInstance:**
```
Definition: MaterialDefinition
BindGroup: IBindGroup                  — GPU resources bound to material slots
PropertyBuffer: IBuffer                — Uniform buffer for scalar properties
TextureSlots: ITextureView[]           — Bound textures
SamplerSlots: ISampler[]               — Bound samplers
Dirty: bool                            — Needs bind group rebuild
```

**MaterialProperty types:**
```
Float, Float2, Float3, Float4, Int, Color, Texture2D, TextureCube, Sampler
```

**RenderPipelineCache:**
```
GetOrCreate(MaterialInstance, Span<VertexBufferLayout>, IBindGroupLayout sceneLayout,
            TextureFormat colorFormat, TextureFormat depthFormat,
            uint8 sampleCount, PipelineVariantFlags) → IRenderPipeline
GetOrCreateLayout(sceneLayout, materialLayout, pushConstantRanges) → IPipelineLayout
SaveCache(path) / LoadCache(path)     — IPipelineCache disk serialization
Clear()
```

Pipeline key hashes: shader identity + render state + vertex layout + RT formats + variant flags.

**Bind Group Layout Convention:**
```
Set 0: Scene data (uniforms, lighting, shadows, IBL) — owned by renderer
Set 1: Material data (textures, samplers, properties) — owned by material
Set 2: Object data (transforms, bone matrices) — owned by renderer (dynamic offset)
```

**Deliverable:** Materials can be defined, instantiated, and produce correct pipelines. Shader variants compile on demand.

---

### Phase 4: Visibility, Culling & Batching

**Goal:** Frustum culling, LOD selection, draw command batching with auto-instancing.

**Files:**
```
  src/
    Visibility/
      VisibilityResolver.bf     — Frustum cull + LOD + light cull
      FrustumCuller.bf          — 6-plane AABB/sphere tests
      VisibleObject.bf          — VisibleMesh, VisibleSkinnedMesh, VisibleLight
    Batching/
      DrawBatcher.bf            — Group draws by material+mesh for instancing
      DrawCommand.bf            — DrawCommand, SkinnedDrawCommand
      DrawBatch.bf              — DrawBatch, InstanceGroup
      InstanceBufferManager.bf  — Per-frame GPU instance buffer allocation
```

**VisibilityResolver:**
```
Resolve(RenderWorld, ViewProjection, CameraPos, SortMode)
ResolveAccumulate(...)          — Multi-view union (shared light list)
Clear()
SetLODDistances(float[4])      — default: 25, 100, 400, 1600
SetLODBias(float)               — quality multiplier

Results:
  VisibleMeshes: List<VisibleMesh>           — handle, distanceSq, LOD, sortKey
  VisibleSkinnedMeshes: List<VisibleSkinnedMesh>
  VisibleLights: List<VisibleLight>          — handle, distanceSq, castsShadows
```

**DrawBatcher:**
```
Build(RenderWorld, VisibilityResolver)
BuildShadowCasters(RenderWorld, VisibilityResolver)
Clear()

Results:
  OpaqueBatches, TransparentBatches, SkinnedBatches: List<DrawBatch>
  OpaqueInstanceGroups, TransparentInstanceGroups: List<InstanceGroup>
```

Grouping is dictionary-based (O(n)) by `(MaterialHandle, GPUMeshHandle, LODLevel)` key. Groups with count > 1 become instance groups; singles remain individual draws.

**InstanceBufferManager:**
```
Reset(frameIndex)
AllocateInstances(count) → (IBuffer, offset)    — sub-allocate from per-frame ring
UploadInstanceData(Span<InstanceData>)
```

**InstanceData (CRepr, 64 bytes):**
```
Matrix4x4 WorldMatrix
```

**Deliverable:** Meshes are frustum-culled, LOD-selected, sorted, and batched. Instance groups share GPU instance buffers.

---

### Phase 5: Depth Prepass & Forward Opaque

**Goal:** Depth prepass with optional Hi-Z, and the main forward opaque rendering feature with per-object uniforms. This is the phase where the renderer first draws real 3D geometry — connecting Phase 4's visibility/batching output to actual GPU draw calls through the render graph.

**Files:**
```
  src/
    Features/
      DepthPrepassFeature.bf    — Early-Z depth pass + Hi-Z pyramid
      ForwardOpaqueFeature.bf   — Main PBR opaque rendering
      ObjectUniformManager.bf   — Per-object uniform buffer with dynamic offsets
    Shaders/
      depth_prepass.hlsl
      forward_pbr.hlsl          — Main PBR shader (metallic/roughness, Cook-Torrance)
```

---

#### Vertex Format Bridge: Sedulous.Geometry → GPU

The renderer must translate `Sedulous.Geometry.StaticMeshVertex` (48 bytes) into RHI `VertexBufferLayout`. This vertex format is the standard for all static opaque geometry:

```
StaticMeshVertex (48 bytes, CRepr):
  Offset  0: Vector3  Position     (Float32x3)  → TEXCOORD0
  Offset 12: Vector3  Normal       (Float32x3)  → TEXCOORD1
  Offset 24: Vector2  TexCoord     (Float32x2)  → TEXCOORD2
  Offset 32: uint32   Color        (Unorm8x4)   → TEXCOORD3
  Offset 36: Vector3  Tangent      (Float32x3)  → TEXCOORD4
```

**RHI vertex layout** (created once by ForwardOpaqueFeature during init):
```
VertexBufferLayout:
  Stride = 48
  StepMode = .Vertex
  Attributes:
    { Format = .Float32x3, Offset =  0, ShaderLocation = 0 }  // Position
    { Format = .Float32x3, Offset = 12, ShaderLocation = 1 }  // Normal
    { Format = .Float32x2, Offset = 24, ShaderLocation = 2 }  // TexCoord
    { Format = .Unorm8x4,  Offset = 32, ShaderLocation = 3 }  // Color
    { Format = .Float32x3, Offset = 36, ShaderLocation = 4 }  // Tangent
```

**Instance buffer layout** (second vertex buffer, step per instance):
```
VertexBufferLayout:
  Stride = 64
  StepMode = .Instance
  Attributes:
    { Format = .Float32x4, Offset =  0, ShaderLocation = 5 }  // WorldMatrix row 0
    { Format = .Float32x4, Offset = 16, ShaderLocation = 6 }  // WorldMatrix row 1
    { Format = .Float32x4, Offset = 32, ShaderLocation = 7 }  // WorldMatrix row 2
    { Format = .Float32x4, Offset = 48, ShaderLocation = 8 }  // WorldMatrix row 3
```

**HLSL semantics** — DX12 backend only supports `TEXCOORD`N, so ALL vertex attributes use `TEXCOORD0..N`:
```hlsl
struct VSInput {
    float3 Position : TEXCOORD0;
    float3 Normal   : TEXCOORD1;
    float2 TexCoord : TEXCOORD2;
    float4 Color    : TEXCOORD3;  // Unorm8x4 decoded to float4 by hardware
    float3 Tangent  : TEXCOORD4;
    // Instanced:
    float4 WorldRow0 : TEXCOORD5;
    float4 WorldRow1 : TEXCOORD6;
    float4 WorldRow2 : TEXCOORD7;
    float4 WorldRow3 : TEXCOORD8;
};
```

**Mesh upload path** (application code):
```
MeshBuilder.CreateCube() → StaticMesh
  → GPUResourceManager.UploadMesh(staticMesh) → GPUMeshHandle
  → RenderWorld.SetStaticMeshData(proxyHandle, meshHandle, staticMesh.Bounds)
  → RenderWorld.SetStaticMeshMaterial(proxyHandle, 0, materialHandle)
```

The `UploadMesh(StaticMesh)` overload reads vertex/index data directly — no manual byte wrangling needed. The raw `UploadMesh(Span<uint8>, ...)` overload remains for custom vertex formats.

---

#### Object Uniform Management

Per-object data (world matrix, previous world matrix, object/material IDs) is uploaded to a dynamic-offset uniform buffer. This avoids per-draw buffer creation and allows efficient batching.

**ObjectUniforms (CRepr, 256 bytes aligned):**
```
Matrix4x4 WorldMatrix          — 64 bytes
Matrix4x4 PrevWorldMatrix      — 64 bytes (for motion vectors)
Matrix4x4 NormalMatrix          — 64 bytes (inverse-transpose of WorldMatrix, for correct normal transform)
uint32    ObjectID              — 4 bytes
uint32    MaterialID            — 4 bytes
float[14] _Padding              — 56 bytes
                                — Total: 256 bytes (matches minUniformBufferOffsetAlignment)
```

**ObjectUniformManager:**
```
Initialize(IDevice, maxObjects = 4096)
  → Creates CpuToGpu buffer: 256 * maxObjects bytes
  → Persistent map

Reset(frameIndex)
  → Resets write offset for current frame

AllocateObject(ObjectUniforms data) → uint32 dynamicOffset
  → Copies 256 bytes at current offset
  → Returns byte offset for SetBindGroup dynamic offset

CurrentBuffer → IBuffer
```

**Why 256-byte alignment:** Vulkan `minUniformBufferOffsetAlignment` is typically 256 bytes. DX12 constant buffer views require 256-byte alignment. This is the safe universal alignment.

**Why NormalMatrix:** When an object has non-uniform scale, normals must be transformed by the inverse-transpose of the world matrix. Computing this on CPU once per visible object is cheaper than doing it per-vertex in the shader.

---

#### Bind Group Layout Convention

```
Set 0: Scene data (shared across all draws in a view) — 7 bindings
  binding 0: SceneUniforms UBO (448 bytes)                       — b0, space0
  binding 1: LightBuffer (StorageBuffer, read-only)              — t1, space0
  binding 2: ClusterGrid (StorageBuffer, read-only)              — t2, space0
  binding 3: LightIndexList (StorageBuffer, read-only)           — t3, space0
  binding 4: ShadowUniforms UBO (288 bytes)                      — b4, space0
  binding 5: CascadeShadowMap (Texture2DArray, sampled)          — t5, space0
  binding 6: ShadowSampler (ComparisonSampler, LessEqual)        — s6, space0

Set 1: Material data (shared across draws with same material)
  binding 0: MaterialProperties UBO (albedo color, metallic, roughness, etc.)
  binding 1: AlbedoTexture
  binding 2: NormalTexture
  binding 3: MetallicRoughnessTexture
  binding 4: MaterialSampler

Set 2: Object data (per-draw, dynamic offset)
  binding 0: ObjectUniforms UBO (256 bytes, dynamic offset)
```

**Register mapping (HLSL → Vulkan SPIR-V via register shifts):**
- `b0` → CbvShift(0) + 0 = Vulkan binding 0
- `t1` → SrvShift(1000) + 1 = Vulkan binding 1001
- `b4` → CbvShift(0) + 4 = Vulkan binding 4
- `t5` → SrvShift(1000) + 5 = Vulkan binding 1005
- `s6` → SamplerShift(3000) + 6 = Vulkan binding 3006
- DX12 uses HLSL registers directly.

**Future Set 0 expansion** (bindings will be added as needed):
- IrradianceCubemap, PrefilteredCubemap, BRDF LUT — Phase 10
- ShadowAtlas (Texture2D) — Phase 7 Step B

---

#### DepthPrepassFeature

**Purpose:** Populate the depth buffer before the forward pass. This eliminates overdraw in the forward pass (fragments that fail depth test are rejected before expensive PBR lighting calculations).

**Lifecycle:**
```
OnInitialize(InitContext):
  1. Register "depth_prepass" shader with ShaderLibrary
  2. Create scene bind group layout (Set 0 — SceneUniforms only for depth pass)
  3. Create depth-only material definition (DepthMode = .ReadWrite, no fragment shader)
  4. Allocate ObjectUniformManager (shared with ForwardOpaque, passed via RenderSystem)
  5. No GPU uploads needed (depth prepass uses existing mesh VB/IB)

OnAddPasses(RenderGraph, FrameContext, ViewContext):
  1. Create depth texture (Depth32Float, viewCtx.RenderWidth x viewCtx.RenderHeight)
  2. Add "DepthPrepass" render graph pass:
     - Writes: depth texture (DepthStencilAttachment, Clear to 1.0)
     - Execute callback:
       a. Run VisibilityResolver.Resolve(world, viewCtx, .FrontToBack)
       b. Run DrawBatcher.Build(world, resources, visibility)
       c. For each opaque batch:
          - Get GPUMesh from GPUResourceManager
          - Get submesh for batch.SubMeshIndex
          - Allocate object uniforms (world matrix from proxy)
          - Get/create depth-only pipeline (via RenderPipelineCache with .DepthOnly flag)
          - Set pipeline, bind groups, vertex/index buffers
          - If batch.InstanceCount > 1:
              Upload instance data via InstanceBufferManager
              Set instance vertex buffer (slot 1)
              DrawIndexed(submesh.IndexCount, batch.InstanceCount, ...)
          - Else:
              DrawIndexed(submesh.IndexCount, 1, ...)
  3. (Phase 17) Add "HiZGenerate" compute pass:
     - Reads: depth texture
     - Writes: Hi-Z mip chain (successive downsamples with max operator)
     - Used by GPU occlusion culling

  Exports: depth texture handle (for ForwardOpaque to read)
```

**Pipeline variants for depth prepass:**
- `DepthOnly`: Standard static mesh, vertex shader only
- `DepthOnly | Instanced`: Uses instance buffer for world matrix
- `DepthOnly | Skinned`: Reads bone buffer for skinned vertex transform (Phase 11)
- `DepthOnly | AlphaTest`: Requires fragment shader to test alpha and discard

**depth_prepass.hlsl:**
```hlsl
// Set 0: Scene
cbuffer SceneUniforms : register(b0) { /* ViewProjection, etc. */ };
// Set 2: Object (dynamic offset)
cbuffer ObjectUniforms : register(b1) { float4x4 WorldMatrix; /* ... */ };

struct VSInput {
    float3 Position : TEXCOORD0;
    // Instanced variant adds WorldRow0..3 : TEXCOORD5..8
};

struct VSOutput {
    float4 Position : SV_Position;
};

VSOutput VSMain(VSInput input) {
    VSOutput output;
    #ifdef INSTANCED
        float4x4 world = float4x4(input.WorldRow0, input.WorldRow1, input.WorldRow2, input.WorldRow3);
    #else
        float4x4 world = WorldMatrix;
    #endif
    float4 worldPos = mul(float4(input.Position, 1.0), world);
    output.Position = mul(worldPos, ViewProjectionMatrix);
    return output;
}

#ifdef ALPHA_TEST
// Only compiled when material uses alpha testing
Texture2D AlbedoTex : register(t0);
SamplerState AlbedoSampler : register(s0);

void PSMain(VSOutput input) {
    float alpha = AlbedoTex.Sample(AlbedoSampler, input.TexCoord).a;
    if (alpha < 0.5) discard;
}
#endif
```

---

#### ForwardOpaqueFeature

**Purpose:** Render all opaque geometry with PBR lighting. This is the main visual pass.

**Lifecycle:**
```
OnInitialize(InitContext):
  1. Register "forward_pbr" shader with ShaderLibrary
  2. Create scene bind group layout (Set 0 — full scene data)
  3. Create default PBR material definition:
     - ShaderName = "forward_pbr"
     - BlendMode = .Opaque
     - CullMode = .Back
     - DepthMode = .ReadOnly  (reuse prepass depth, test with LessEqual)
  4. Create scene bind group with fallback textures for unimplemented bindings:
     - Shadow maps → dummy depth textures
     - IBL → 1x1 white cubemap
     - Light/cluster buffers → dummy storage buffers
  5. Build static vertex buffer layout (48-byte StaticMeshVertex)
  6. Build instance vertex buffer layout (64-byte InstanceData)

OnAddPasses(RenderGraph, FrameContext, ViewContext):
  1. Import depth texture from DepthPrepassFeature (read-only depth attachment)
  2. Create HDR color texture (RGBA16Float, viewCtx dimensions)
  3. Add "ForwardOpaque" render graph pass:
     - Reads: depth texture (DepthStencilAttachment, .ReadOnly, LessEqual)
     - Writes: HDR color texture (ColorAttachment, Clear to sky/ambient color)
     - Execute callback:
       a. Reuse VisibilityResolver + DrawBatcher results from depth prepass
          (shared per-frame, not re-culled — same view, same frame)
       b. Set scene bind group (Set 0) once
       c. For each opaque batch (already sorted by material, then depth):
          - Get material instance → set material bind group (Set 1)
          - Allocate object uniforms → set object bind group (Set 2, dynamic offset)
          - Get/create pipeline:
              RenderPipelineCache.GetOrCreate(
                materialDef,
                [meshVertexLayout, instanceVertexLayout],
                sceneLayout,
                .RGBA16Float,   // color format
                .Depth32Float,  // depth format
                1,              // sample count
                variantFlags    // .None or .Instanced
              )
          - Set pipeline (only when it changes — batches are sorted to minimize changes)
          - Set vertex buffer slot 0 (mesh VB)
          - Set index buffer (mesh IB)
          - If instanced:
              Set vertex buffer slot 1 (instance buffer at batch.InstanceBufferOffset)
              DrawIndexed(submesh.IndexCount, batch.InstanceCount, submesh.IndexStart, submesh.BaseVertex, 0)
          - Else:
              DrawIndexed(submesh.IndexCount, 1, submesh.IndexStart, submesh.BaseVertex, 0)

  Exports: HDR color texture handle (for transparent pass, post-processing)
```

**Minimizing state changes in the draw loop:**

The opaque sort key layout (`SortKeyHelper.MakeOpaqueSortKey`) ensures draws are ordered by:
1. Material (high 16 bits) — pipeline + bind group Set 1 change
2. Mesh (next 16 bits) — vertex/index buffer change
3. LOD (8 bits) — submesh index change
4. Depth (low 24 bits) — tiebreaker, no state change

The draw loop tracks the previous material and pipeline. Only rebind when changed:
```
prevMaterial = -1
prevPipeline = null

for batch in opaqueBatches:
    if batch.MaterialHandle != prevMaterial:
        pipeline = cache.GetOrCreate(...)
        if pipeline != prevPipeline:
            rp.SetPipeline(pipeline)
            prevPipeline = pipeline
        rp.SetBindGroup(1, material.BindGroup)
        prevMaterial = batch.MaterialHandle

    objectOffset = objectUniformManager.AllocateObject(...)
    rp.SetBindGroup(2, objectBindGroup, dynamicOffset: objectOffset)

    rp.SetVertexBuffer(0, mesh.VertexBuffer)
    rp.SetIndexBuffer(mesh.IndexBuffer, mesh.IndexFormat)
    rp.DrawIndexed(...)
```

---

#### Forward PBR Shader (forward_pbr.hlsl)

**Structure:**
```hlsl
// === Bind Group 0: Scene ===
cbuffer SceneUniforms : register(b0) {
    float4x4 ViewMatrix;
    float4x4 ProjectionMatrix;
    float4x4 ViewProjectionMatrix;
    float4x4 InverseViewMatrix;
    float4x4 InverseProjectionMatrix;
    float4x4 PrevViewProjectionMatrix;
    float3 CameraPosition; float Time;
    float3 CameraForward;  float DeltaTime;
    float2 ScreenSize;     float NearPlane; float FarPlane;
    uint FrameNumber;      float3 _pad;
};

// === Bind Group 1: Material ===
cbuffer MaterialProperties : register(b1) {
    float4 AlbedoColor;
    float  Metallic;
    float  Roughness;
    float  AO;
    float  EmissiveStrength;
    float4 EmissiveColor;
};
Texture2D    AlbedoTex      : register(t0);
Texture2D    NormalTex       : register(t1);
Texture2D    MetRoughTex    : register(t2);
Texture2D    OcclusionTex   : register(t3);
Texture2D    EmissiveTex    : register(t4);
SamplerState MaterialSampler : register(s0);

// === Bind Group 2: Object (dynamic offset) ===
cbuffer ObjectUniforms : register(b2) {
    float4x4 WorldMatrix;
    float4x4 PrevWorldMatrix;
    float4x4 NormalMatrix;
    uint ObjectID;
    uint MaterialID;
};

// === Vertex Shader ===
struct VSInput {
    float3 Position : TEXCOORD0;
    float3 Normal   : TEXCOORD1;
    float2 TexCoord : TEXCOORD2;
    float4 Color    : TEXCOORD3;
    float3 Tangent  : TEXCOORD4;
#ifdef INSTANCED
    float4 WorldRow0 : TEXCOORD5;
    float4 WorldRow1 : TEXCOORD6;
    float4 WorldRow2 : TEXCOORD7;
    float4 WorldRow3 : TEXCOORD8;
#endif
};

struct VSOutput {
    float4 ClipPos    : SV_Position;
    float3 WorldPos   : TEXCOORD0;
    float3 WorldNormal: TEXCOORD1;
    float2 TexCoord   : TEXCOORD2;
    float4 Color      : TEXCOORD3;
    float3 WorldTangent : TEXCOORD4;
};

VSOutput VSMain(VSInput i) {
    // ... transform using WorldMatrix or instanced matrix
    // ... output world-space position, normal, tangent for fragment shader
}

// === Fragment Shader ===
// Phase 5 initial: single directional light, no shadows, no IBL
// Phase 6+: clustered light reads, shadow sampling, IBL

float4 PSMain(VSOutput i) : SV_Target {
    // 1. Sample textures
    float4 albedo = AlbedoTex.Sample(...) * AlbedoColor * i.Color;
    float3 N = NormalFromTangentSpace(NormalTex, i.WorldNormal, i.WorldTangent, i.TexCoord);
    float metallic = MetRoughTex.Sample(...).b * Metallic;
    float roughness = MetRoughTex.Sample(...).g * Roughness;

    // 2. PBR setup
    float3 V = normalize(CameraPosition - i.WorldPos);
    float3 F0 = lerp(0.04, albedo.rgb, metallic);

    // 3. Direct lighting (Phase 5: hardcoded directional light)
    float3 L = normalize(float3(0.5, 1.0, 0.3));  // Temporary
    float3 radiance = float3(1.0, 0.98, 0.95) * 3.0;
    float3 direct = CookTorranceBRDF(N, V, L, F0, albedo.rgb, metallic, roughness) * radiance;

    // 4. Ambient (Phase 5: flat ambient, Phase 10: IBL replaces this)
    float3 ambient = albedo.rgb * 0.03;

    // 5. Emissive
    float3 emissive = EmissiveTex.Sample(...).rgb * EmissiveColor.rgb * EmissiveStrength;

    return float4(direct + ambient + emissive, 1.0);
}
```

**Cook-Torrance BRDF functions** (included in shader):
- `DistributionGGX(N, H, roughness)` — GGX/Trowbridge-Reitz NDF
- `GeometrySmith(N, V, L, roughness)` — Smith's Schlick-GGX geometry function
- `FresnelSchlick(cosTheta, F0)` — Fresnel approximation

---

#### Phase 5 Testing (using Sedulous.Geometry)

Phase 5 is the first testable rendering phase. Test geometry is generated using `MeshBuilder` primitives:

```
ForwardOpaqueTestScene setup:
  1. MeshBuilder.CreateCube() → StaticMesh → UploadMesh() → GPUMeshHandle
  2. MeshBuilder.CreateSphere() → same pipeline
  3. MeshBuilder.CreatePlane() → ground plane
  4. Create MaterialDefinition for "forward_pbr"
  5. Create MaterialInstance with:
     - AlbedoColor = (1, 0.5, 0.2, 1)  // orange
     - Metallic = 0.0, Roughness = 0.8  // rough dielectric
     - All textures = fallback white/normal
  6. Create RenderWorld, add proxies at various positions
  7. Set camera, verify:
     - Depth prepass: white-near/black-far depth buffer
     - Forward opaque: lit cubes/spheres on a ground plane
     - Frustum culling: objects behind camera are not drawn
     - LOD selection: distant objects use lower LODs
     - Instancing: multiple cubes with same material batch into single draw
```

**Expected visual result:** Orange cubes and spheres on a grey ground plane, lit by a single directional light from upper-right, with proper depth testing and no overdraw.

---

**Deliverable:** Opaque PBR meshes render correctly with depth prepass optimization. Scene is lit by a single directional light (shadows and clustering in later phases). Frustum culling, LOD selection, and instanced batching all verified with MeshBuilder test geometry.

---

### Phase 6: Lighting System

**Goal:** Clustered forward+ lighting with point, spot, directional, and area lights.

**Architecture:** `LightingSystem` is owned by `RenderSystem` as shared scene-level infrastructure (alongside VisibilityResolver, RenderBatcher, ObjectUniformManager). Lighting data is consumed by multiple features (opaque, transparent, decals, volumetric fog), so it belongs at the system level rather than coupled to any single feature.

**Delivery:** Two-step — Step A adds multi-light forward rendering (brute-force loop), Step B adds compute-based cluster culling.

**Files:**
```
  src/
    Lighting/
      GPULightData.bf           — GPU light struct (80 bytes, float4-packed for SPIR-V safety)
      LightingSystem.bf         — Coordinator: light upload, cluster grid, (Step B) compute culling
      ClusterGrid.bf            — (Step B) 3D cluster grid for light assignment
    Shaders (Assets/Shaders/):
      light_cull.hlsl           — (Step B) Compute: assign lights to clusters
```

**GPULightData (80 bytes, float4-packed):**
```
struct GPULightData (CRepr):
  float4   PositionAndRange       // xyz=pos, w=range
  float4   DirectionAndSpotInner  // xyz=dir, w=innerConeAngle
  float4   ColorAndIntensity      // xyz=color, w=intensity
  uint32   Type                   // 0=directional, 1=point, 2=spot
  float    SpotOuterAngle
  float    AreaWidth, AreaHeight
  uint32   ShadowIndex, Flags
  float2   _pad
  — 80 bytes per light

MaxLights = 1024 → 80 KB buffer (double-buffered, CpuToGpu)
```

**Note:** Uses float4 packing instead of float3+float to avoid SPIR-V std430 vec3 alignment issues (vec3 pads to 16 bytes, breaking cross-API layouts).

**Scene Bind Group (Set 0):**
```
  binding 0: SceneUniforms UBO (Vertex|Fragment)
  binding 1: LightBuffer (StructuredBuffer, read-only, Fragment)
  binding 2: ClusterGrid (StructuredBuffer, read-only, Fragment)
  binding 3: LightIndexBuffer (StructuredBuffer, read-only, Fragment)
```

LightCount is added to SceneUniforms (replaces padding, struct stays 448 bytes).

**Compute Culling (pre-graph, separate bind group):**

Cluster grid: 16×9×24 = 3,456 clusters. Exponential depth slices: `depth(z) = near * pow(far/near, z/24)`. Cluster AABBs computed per-thread in the compute shader from the inverse projection matrix (no extra buffer needed).

Per-cluster data: `{ uint32 offset; uint32 count; }` — offset into global light index list.

Compute bind group (bound at index 0 during compute pass only):
```
  binding 0: SceneUniforms UBO (Compute) — rebound for compute visibility
  binding 1: LightBuffer (StructuredBuffer, read-only, Compute)
  binding 2: ClusterGrid (RWStructuredBuffer, read-write, Compute)
  binding 3: LightIndexList (RWStructuredBuffer, read-write, Compute)
  binding 4: AtomicCounter (RWByteAddressBuffer, read-write, Compute)
```

`light_cull.hlsl` — `[numthreads(64,1,1)]`, one thread per cluster. Each thread:
1. Computes view-space AABB from inverse projection + exponential depth slices
2. Tests all lights: directional always passes, point/spot use sphere-AABB intersection
3. Atomically allocates contiguous range in global light index list
4. Writes light indices and cluster metadata

`forward_pbr.hlsl` — fragment shader computes cluster index from `(screenPos, viewDepth)` using the same exponential formula, reads `ClusterGrid[flatIndex]`, loops only over that cluster's assigned lights.

**Buffer sizes:**
| Buffer | Size | Notes |
|--------|------|-------|
| LightBuffer | 80 KB | 1024 lights × 80 bytes, staging + GPU per frame |
| ClusterGrid | 27 KB | 3456 × 8 bytes, per frame |
| LightIndexList | 1.7 MB | 3456 × 128 × 4 bytes, per frame |
| AtomicCounter | 4 B | cleared to 0 each frame via staging copy |

**Deliverable:** Multiple dynamic lights with clustered culling. Performance scales with visible lights per cluster, not total scene lights.

---

### Phase 7: Shadow System

**Goal:** Cascaded shadow maps for directional lights, shadow atlas for point/spot lights.

**Step A — Cascaded Shadow Maps (COMPLETE):**

A single directional light casts shadows via 4-cascade shadow maps with 5x5 PCF filtering. Hard cascade cuts (no blending) match the legacy approach — cascade blending was tested but caused shadow pop-in artifacts at cascade boundaries where inner cascades lack caster coverage.

**Files (Step A):**
```
  src/
    Shadows/
      ShadowSystem.bf           — Cascade computation, texture, uniforms, shadow pass recording
  Assets/Shaders/
    shadow_depth.hlsl            — Depth-only shadow caster vertex shader (no fragment)
    forward_pbr.hlsl             — Extended with SampleCascadedShadow + 5x5 PCF
  Code/Samples/RendererFramework/src/
    DxcShaderCompiler.bf         — Adds #define VULKAN 1 when compiling SPIR-V
```

**ShadowSystem architecture:**
- Owned by `RenderSystem` as shared scene-level infrastructure (like LightingSystem)
- `ShadowUniforms` (288 bytes): 4 cascade VP matrices + distances + shadow params → scene bind group (binding 4)
- `Texture2DArray` (4 layers, 2048×2048, Depth32Float) → scene bind group (binding 5)
- `ComparisonSampler` (LessEqual, linear, clamp) → scene bind group (binding 6)
- Shadow cascade passes run **pre-graph** (see "Pre-Graph vs Graph Work" above)
- Shadow pass pipeline: separate layout (Set 0: shadow pass UBO, Set 1: object UBO), depth-only, CullMode.None
- Per-cascade-per-frame buffering: `[FrameBufferCount * ShadowCascadeCount]` uniform buffers and bind groups (CpuToGpu mapped buffers are read at GPU execution time, not recording time)
- Multi-view buffered: shadow uniform buffers are `[TotalBufferSlots]` (per-frame-per-view)

**Cascade computation:**
```
CascadeCount = 4, Resolution = 2048, Format = Depth32Float
SplitLambda = 0.85 (log/uniform blend)
Tight frustum fitting: extract 8 NDC corners from inverse VP, interpolate for cascade slice
Texel snapping: cascade ortho bounds snapped to shadow map texel grid (prevents shadow swimming)
Depth range extension: minZ extended by 0.5× to catch shadow casters behind camera frustum
```

**Shadow sampling (forward_pbr.hlsl):**
- 5x5 PCF (25-tap `SampleCmpLevelZero`) for soft shadow edges
- `saturate(shadowCoord.z)` clamps depth to [0,1] preventing artifacts from behind-frustum geometry
- Shader-level depth bias (`ShadowParams.x`, default 0.003)
- Cascade selection by view-space Z (negated for RH) vs `CascadeDistances`
- Hard cascade cuts (no blending) — matches legacy, avoids pop-in at boundaries
- Edge fade on outermost cascade only — prevents hard cutoff at shadow coverage boundary
- Applied to directional lights where `ShadowIndex != 0xFFFFFFFF`

**Cross-backend notes:**
- DX12 per-layer DSV/RTV must use `Texture2DArray` dimension (not `Texture2D`) — `Texture2D` ignores `BaseArrayLayer`
- DX12 initial texture state for depth is `DepthStencilWrite`, not `Undefined` — first barrier must use `ITexture.InitialState`
- DX12 barriers always use `ALL_SUBRESOURCES` — per-layer barriers not supported
- `#define VULKAN 1` auto-injected during SPIR-V compilation for backend-specific shader paths

**Step B — Shadow Atlas (Pending):**

**ShadowAtlas:**
```
AtlasSize = 4096x4096 (configurable)
Format = Depth32Float
TileResolutions: 512, 256, 128 (by priority/distance)

AllocateTile(LightProxyHandle, uint32 resolution) → (x, y, w, h)
FreeTile(LightProxyHandle)
GetAtlasTexture() → ITexture
GetTileViewport(LightProxyHandle) → Viewport
```

**Known Step A limitations (addressable in future refinement):**
- **Shadow silhouette bleeding**: thin bright lines at shadow caster edges from depth discontinuities. Fix: add per-cascade world-space texel sizes to `ShadowUniforms` and use receiver-side normal offset bias (like legacy `CascadeTexelSizes + ShadowNormalBias * texelSize * (1 - NdotL)`).
- **Inner cascade caster coverage**: cascade 0 may not contain shadow casters if objects are beyond its depth range, causing shadows to appear only starting at cascade 1. Fix: extend cascade ortho projection XY to include casters from adjacent cascades, or use scene AABB for depth range.
- **Cascade blending**: removed due to pop-in at boundaries (inner cascade lacks caster data → shadow appears abruptly at blend edge). Could be re-enabled if caster coverage is fixed.
- **Hardware depth bias**: tested (`DepthBias + SlopeScaledDepthBias` in `DepthStencilState`) but produced severe banding on D32_FLOAT — values that worked on one backend didn't work on the other. Shader-level bias is more portable.

**Future shadow quality improvements:**
- Per-cascade texel-scaled receiver-side normal offset bias (legacy approach, highest impact)
- PCSS (Percentage-Closer Soft Shadows) — variable penumbra width
- VSM (Variance Shadow Maps) — optional, needs blur pass
- Cascade blending (re-enable after fixing inner cascade caster coverage)

**Deliverable:** Step A: directional light casts cascaded shadows with 5x5 PCF. Step B: point/spot lights cast shadows via atlas.

---

### Phase 8: Transparent Rendering & Motion Vectors

**Goal:** Transparent geometry rendering and per-pixel motion vectors for temporal effects.

**Files:**
```
  src/
    Features/
      ForwardTransparentFeature.bf   — Back-to-front transparent rendering
      MotionVectorFeature.bf         — Per-pixel velocity buffer
    Shaders/
      forward_transparent.hlsl
      motion_vectors.hlsl
```

**ForwardTransparentFeature:**
- Depends on: `Lighting`, `ForwardOpaque` (needs scene color for refraction reads)
- Sorted back-to-front by distance to camera
- Per-draw blend state from material (AlphaBlend, Additive, Multiply, PremultipliedAlpha)
- Depth writes disabled, depth test enabled (read-only)
- Two-pass option for correct alpha: back faces first (FrontFaceCull), then front faces
- Max 256 transparent objects per frame (RenderConfig)

**MotionVectorFeature:**
- Depends on: `DepthPrepass`
- Full-screen pass: reconstruct world position from depth, reproject with PrevViewProjection
- Outputs: RG16Float motion vector texture (in pixel space)
- Per-object motion: `PrevWorldMatrix` in ObjectUniforms enables per-vertex velocity
- Used by: TAA, Motion Blur

**Deliverable:** Transparent objects render with correct blending. Motion vectors generated for temporal effects.

---

### Phase 9: Post-Processing Stack

**Goal:** Full post-processing pipeline with all legacy effects plus improvements.

**Files:**
```
  src/
    PostProcess/
      PostProcessStack.bf           — Effect chaining with ping-pong targets
      IPostProcessEffect.bf         — Effect interface
      Effects/
        AutoExposureEffect.bf       — Luminance histogram → exposure
        BloomEffect.bf              — Dual-filter Kawase blur
        TAAEffect.bf                — Temporal AA with neighborhood clamping
        SSAOEffect.bf               — GTAO or HBAO
        SSREffect.bf                — Hi-Z traced screen-space reflections
        TonemapEffect.bf            — ACES / Reinhard / Uncharted2 / AgX
        FXAAEffect.bf               — Fast approximate AA (non-TAA fallback)
        DOFEffect.bf                — Bokeh depth of field
        MotionBlurEffect.bf         — Per-pixel velocity-based blur
        VignetteEffect.bf           — Edge darkening
        FilmGrainEffect.bf          — Noise overlay
        ChromaticAberrationEffect.bf
        ColorGradingEffect.bf       — 3D LUT color correction
        ContactShadowEffect.bf      — Screen-space ray marched shadows
        SharpenEffect.bf            — CAS (Contrast Adaptive Sharpening)
    Shaders/
      postprocess/
        auto_exposure.hlsl
        bloom_downsample.hlsl
        bloom_upsample.hlsl
        taa_resolve.hlsl
        ssao.hlsl
        ssr.hlsl
        tonemap.hlsl
        fxaa.hlsl
        dof.hlsl
        motion_blur.hlsl
        vignette.hlsl
        film_grain.hlsl
        chromatic_aberration.hlsl
        color_grading.hlsl
        contact_shadows.hlsl
        sharpen.hlsl
```

**PostProcessStack:**
```
RegisterEffect(IPostProcessEffect)
UnregisterEffect(IPostProcessEffect)
GetEffect<T>() / GetEffect(StringView name)
HasEnabledEffects → bool
AddPasses(RenderGraph, RenderView, RGTexture sceneColor, RGTexture depth) → RGTexture
```

Ping-pong RGBA16Float targets. Effects execute in priority order. Each effect reads previous result + depth.

**IPostProcessEffect:**
```
Name: StringView
Priority: int32          — Lower = earlier in chain
Enabled: bool
Initialize(IDevice)
Shutdown()
AddPasses(RenderGraph, RenderView, RGTexture input, RGTexture output, RGTexture depth)
```

**TAA Improvements over legacy:**
- Neighborhood clamping (3x3 color AABB clamp on history)
- Velocity rejection (discard history for high-velocity pixels)
- Luminance weighting for flicker reduction
- Catmull-Rom history sampling for sharpness

**Tonemapping additions:**
- AgX tonemapper (modern alternative to ACES)
- Per-channel or luminance-based options

**Deliverable:** Full post-processing chain. All 15 effects functional.

---

### Phase 10: Sky & Environment

**Goal:** Procedural and HDRI sky rendering with IBL generation.

**Step A — HDRI Sky Rendering (COMPLETE):**

Full-screen equirectangular HDRI sky rendered wherever depth == 1.0 (no geometry).
Renders after forward opaque, before forward transparent (transparent objects don't
write depth, so sky must fill background first).

**Step B — IBL Pipeline (COMPLETE):**

Image-based lighting with compute-baked cubemaps and precomputed BRDF LUT.
Forward PBR ambient replaced with proper irradiance + prefiltered specular + BRDF LUT.

**Files:**
```
  src/
    Features/
      SkyFeature.bf              — Sky rendering + IBL baking (compute dispatch)
    EnvironmentSettings.bf       — Per-world environment config (HDRI, exposure, ambient)
    DeferredDeletionQueue.bf     — General-purpose deferred GPU resource deletion
    IRenderFeature.bf            — Added OnRecordPreGraph() for pre-graph GPU work
  Assets/Shaders/
    sky_hdri.hlsl                — Full-screen equirectangular HDRI sampling
    ibl_irradiance.hlsl          — Diffuse irradiance convolution (compute, 32x32 cubemap)
    ibl_prefilter.hlsl           — Specular prefilter (compute, 128x128, 5 mip levels)
  Assets/Textures/
    BRDFLut.bin                  — Precomputed 512x512 RG16Float BRDF integration LUT
  Scripts/
    generate_brdf_lut.py         — Python script to regenerate BRDFLut.bin
```

**Architecture:**
- `EnvironmentSettings` on `RenderWorld` — per-world sky config (HDRI texture, BRDF LUT, sky exposure, ambient intensity)
- `SkyFeature` reads from active world's `Environment`, owns IBL GPU resources
- `Exposure` on `RenderView`/`ViewContext` — per-camera setting
- Scene bind group expanded to 12 entries (added irradiance cubemap t9, prefiltered cubemap t10, BRDF LUT t11)
- IBL bake via `OnRecordPreGraph` — 36 compute dispatches (6 irradiance + 30 prefiltered) with push constants
- `MarkIBLDirty()` triggers re-bake; deferred deletion queue handles old bake resource cleanup
- Push constants: `[[vk::push_constant]] ConstantBuffer<T> : register(b0, spaceN)` works on both backends

**IBL Pipeline:**
1. BRDF LUT: 512x512 RG16Float, precomputed offline (`Scripts/generate_brdf_lut.py`), loaded from binary
2. Irradiance: 32x32x6 RGBA16Float cubemap, cosine-weighted hemisphere convolution from HDRI
3. Prefiltered: 128x128x6 RGBA16Float cubemap with 5 mip levels (roughness per mip), GGX importance sampling
4. Re-bake support via `MarkIBLDirty()` when HDRI changes (deferred deletion for old resources)

**ImGui controls (sandbox):**
- Sun direction (yaw/pitch), color, intensity
- Scene exposure, ambient intensity, sky exposure
- Camera orbit/zoom guarded by `WantCaptureMouse`

**Not yet implemented:**
- Procedural sky (Preetham/Hosek atmospheric model) — `sky_procedural.hlsl`
- Solid color sky mode
- Mode switching API (Procedural | EnvironmentMap | SolidColor)
- IBL re-bake throttling (currently re-bakes immediately when dirty)

**Deliverable:** HDRI sky renders in background. IBL cubemaps baked from HDRI for PBR ambient lighting. Per-world environment settings. ImGui tweaking for sun and exposure.

---

### Phase 11: GPU Skinning

**Goal:** Compute-based skeletal animation with bone matrix upload and skinned vertex transformation.

**Status:** COMPLETE — GPU skinning works on both DX12 and Vulkan.

**Files:**
```
  src/
    Skinning/
      SkinningSystem.bf           — Compute skinning system (owned by RenderSystem)
    Proxies/
      SkinnedMeshProxy.bf         — Skinned mesh proxy (transform, bone buffer, flags)
    Resources/
      GPUBoneBuffer.bf            — Per-frame staged bone matrix buffers
  Assets/Shaders/
    skinning_comp.hlsl            — Compute: SkinnedVertex (72B) → StaticMeshVertex (48B)
```

**Architecture:**
- `SkinningSystem` is RenderSystem infrastructure (like LightingSystem), not an IRenderFeature
- Compute dispatch in `RecordSkinning()` before shadow passes and render graph execution
- Each skinned mesh instance gets a persistent output VB (Storage+Vertex, 48-byte stride)
- Post-skinning VBs are standard StaticMeshVertex layout — all render features draw them unchanged
- No instancing for skinned meshes (each has unique VB) — flat sorted draw list
- Bone buffer uses staging→GPU copy pattern (DX12 UPLOAD heaps can't have UAV/Storage flag)

**SkinnedMeshProxy:**
```
Transform, PrevTransform     — for motion vectors
LocalBounds, AnimationBounds — 1.2x expanded for frustum culling
MeshHandle, BoneBufferHandle
Materials[MaxMaterialsPerMesh]
BoneCount, BonesDirty, Flags
```

**Cross-API Pitfall — StructuredBuffer matrix layout (DX12 vs Vulkan):**
`#pragma pack_matrix(row_major)` does NOT apply to `StructuredBuffer<float4x4>` reads on DX12/DXIL — it only affects cbuffer layout. DXIL defaults to column-major interpretation for StructuredBuffer, causing incorrect skinning matrices. Vulkan/SPIR-V correctly applies the `RowMajor` decoration to SSBOs, so it works either way. **Fix:** Use `ByteAddressBuffer` with manual `Load4` at `index * 64` byte offsets to construct `float4x4` from explicit row vectors. This is correct on both backends.

**Deliverable:** Skinned meshes animate on GPU. Previous frame bone matrices enable motion vectors.

---

### Phase 12: Particle System

**Goal:** Unified particle system with CPU and GPU simulation backends, trails, and sub-emitters.

**Files:**
```
  src/
    Particles/
      ParticleSystem.bf           — System coordinator
      ParticleEmitter.bf          — Base emitter (spawn rate, lifetime, modules)
      CPUParticleEmitter.bf       — CPU-simulated particles
      GPUParticleEmitter.bf       — GPU compute-simulated particles
      TrailEmitter.bf             — Trail rendering
      ParticleModules.bf          — Velocity, gravity, color-over-life, size-over-life, etc.
      ParticleCurve.bf            — Editable curves for parameter animation
      ParticlePresets.bf          — Common presets (fire, smoke, sparks, etc.)
    Features/
      ParticleFeature.bf          — Render feature for particle draw
    Proxies/
      ParticleEmitterProxy.bf
      TrailEmitterProxy.bf
    Shaders/
      particle_simulate.hlsl      — GPU compute simulation
      particle_render.hlsl        — Billboard quad rendering (vertex shader expansion)
      trail_render.hlsl           — Trail strip rendering
```

**Particle Modules:**
- InitialVelocity (cone, sphere, box)
- Gravity / ConstantForce
- ColorOverLifetime (gradient)
- SizeOverLifetime (curve)
- RotationOverLifetime
- VelocityOverLifetime (turbulence)
- EmissionRate (constant, burst)
- SubEmitter (spawn on death)

**GPU Particles:**
- Append/consume buffers for alive/dead lists
- Indirect draw from alive count
- Async compute simulation (overlap with rendering)

**Deliverable:** Particles spawn, simulate, and render. CPU and GPU backends. Trails work.

---

### Phase 13: Terrain, Water, Grass, Vegetation

**Goal:** Large-world rendering features.

**Files:**
```
  src/
    Features/
      TerrainFeature.bf           — Heightmap terrain with LOD
      WaterFeature.bf             — Water surface with displacement + reflections
      GrassFeature.bf             — GPU-instanced grass/vegetation
    Proxies/
      TerrainProxy.bf
      WaterProxy.bf
      GrassProxy.bf
    Shaders/
      terrain.hlsl
      water.hlsl
      grass.hlsl
```

**TerrainFeature:**
- Heightmap-based with clipmap or quadtree LOD
- Tri-planar texture blending (or splatmap)
- Normal map generation from heightfield
- Shadow receiving

**WaterFeature:**
- Displacement via Gerstner waves or FFT
- Screen-space reflections + planar reflection fallback
- Refraction via distorted scene color read
- Depth-based fog/absorption

**GrassFeature:**
- GPU instancing from density map
- Distance-based LOD and fade
- Wind animation (vertex shader)
- Frustum culling per grass cluster

**Deliverable:** Terrain, water, and grass render with appropriate LOD and shading.

---

### Phase 14: Decals & Sprites

**Goal:** Deferred decal projection and 2D sprite/billboard rendering.

**Files:**
```
  src/
    Features/
      DecalFeature.bf             — Deferred decal rendering
      SpriteFeature.bf            — Billboard sprite rendering
    Proxies/
      DecalProxy.bf               — Box/sphere projection volume
      CurveDecalProxy.bf          — Curve-based decal mesh
      SpriteProxy.bf              — 2D sprite with billboard transform
    Shaders/
      decal.hlsl
      sprite.hlsl
```

**DecalFeature:**
- Screen-space projection: sample depth → reconstruct world pos → check if inside decal volume
- Modify albedo/normal/roughness of underlying surface
- Priority-based layering
- Supports box and curve-based projection volumes

**SpriteFeature:**
- Camera-facing billboards (screen-aligned or axis-aligned)
- Batched quad rendering
- Texture atlas support
- Sorted with transparent objects

**Deliverable:** Decals project onto surfaces. Sprites render as billboards.

---

### Phase 15: Volumetric Fog

**Goal:** Volumetric lighting and fog using froxel grid.

**Files:**
```
  src/
    Features/
      VolumetricFogFeature.bf     — Froxel-based volumetric fog
    Shaders/
      volumetric_inject.hlsl      — Compute: inject light + density into froxels
      volumetric_scatter.hlsl     — Compute: ray-march scattering accumulation
      volumetric_apply.hlsl       — Full-screen: composite fog onto scene
```

**Froxel Grid:**
- Same dimensions as cluster grid (16x9x24)
- Per-froxel: scattering color + extinction
- Temporal reprojection for stability
- Jittered ray start for noise reduction

**Pipeline:**
1. Inject: scatter light contributions from each light into froxels
2. Accumulate: front-to-back ray march through froxels
3. Apply: composite accumulated fog onto scene color

**Deliverable:** Volumetric fog with god rays from directional/point/spot lights.

---

### Phase 16: Reflection Probes

**Goal:** Local reflection probes for indoor/outdoor IBL.

**Files:**
```
  src/
    Lighting/
      ReflectionProbeSystem.bf    — Probe management + baking
    Proxies/
      ReflectionProbeProxy.bf     — Probe position, influence volume, priority
    Shaders/
      probe_capture.hlsl          — Render scene into cubemap face
      probe_filter.hlsl           — Prefilter for roughness mips
```

**ReflectionProbeSystem:**
```
BakeProbe(ReflectionProbeProxy)         — Render 6 cubemap faces + prefilter
GetProbeArray() → ITexture              — Cubemap array for all baked probes
FindInfluencingProbes(position) → (probe1, probe2, blendFactor)
```

- Bake on demand (not every frame)
- Parallax-corrected cubemap sampling (box projection)
- Blend between probes + sky fallback
- Budget: max 8-16 active probes

**Deliverable:** Local reflection probes override sky IBL within their influence volumes.

---

### Phase 17: GPU-Driven Rendering Pipeline

**Goal:** Move culling and draw command generation to the GPU for high object counts.

**Status:** COMPLETE — GPU-driven indirect draws with frustum + Hi-Z occlusion culling, working on both DX12 and Vulkan.

**Files:**
```
  src/
    GPUDriven/
      GPUSceneBuffer.bf          — Uploads all object data (transforms, bounds, material/mesh info) sorted by draw group
      IndirectDrawSystem.bf      — Indirect command buffer management, GPU cull dispatch, draw group tracking
      HiZPyramid.bf              — Hi-Z depth pyramid generation (dual-pipeline mip0/mipN approach)
  Assets/Shaders/
    gpu_cull.hlsl                — Compute: frustum planes + Hi-Z occlusion test per object
    hiz_generate.hlsl            — Compute: depth buffer downsample into mip chain (max operator)
    debug_hiz.hlsl               — Debug visualization of Hi-Z pyramid mip levels
```

**Architecture:**
- `GPUSceneBuffer` uploads all static mesh proxy data each frame via staging→GPU copy. Objects sorted by draw group (material+mesh+submesh) for contiguous indirect command ranges.
- `GPUObjectData` (256 bytes/object): WorldMatrix, PrevWorldMatrix, NormalMatrix, world-space AABB, material/mesh/submesh indices, flags.
- One `DrawIndexedIndirectCommand` pre-filled per object (mesh info from CPU, instanceCount=0). GPU cull sets instanceCount=1 for visible objects.
- Features call `DrawIndexedIndirect(buffer, groupOffset, groupCount, stride)` per material group. Invisible objects have instanceCount=0 → draw nothing.
- Identity instance buffer `[0,1,2,...,N-1]` provides `ObjectIndex` via per-instance vertex attribute. `firstInstance` from indirect command selects the correct entry. Cross-platform — avoids `SV_StartInstanceLocation` portability issues.
- Vertex shaders read per-object transforms from `ByteAddressBuffer ObjectData` (GPU_DRIVEN shader variant via `#ifdef`). Skinned meshes use the legacy `cbuffer ObjectUniforms` path.

**GPU Culling Pipeline:**
1. CPU uploads all object transforms + bounds to `GPUSceneBuffer` (staging→GPU copy)
2. CPU pre-fills indirect commands with mesh info, instanceCount=0
3. GPU compute: test each object against 6 frustum planes → if visible, set instanceCount=1
4. GPU compute: test each visible object against Hi-Z depth pyramid → if occluded, leave instanceCount=0
5. Features issue `DrawIndexedIndirect` per material group — GPU skips invisible objects

**Hi-Z Depth Pyramid:**
- Generated as a render graph compute pass after depth prepass
- Dual-pipeline approach: mip 0 reads depth as `Texture2D` (SampledTexture, SHADER_READ_ONLY), mip 1+ reads previous Hi-Z mip as `RWTexture2D` (StorageTexture, GENERAL layout)
- Per-mip params UBOs (avoids CpuToGpu read-after-write race with shared buffer)
- Whole-texture GENERAL layout during generation with memory barriers between dispatches
- Final transition to ShaderRead for next frame's cull compute (1-frame latency, standard approach)
- 4-corner sampling in occlusion test for robust AABB coverage

**Cross-API Pitfall — CpuToGpu read timing:**
CpuToGpu (UPLOAD) mapped buffers are read by the GPU at execution time, not recording time. If a single mapped buffer is overwritten per-dispatch (e.g., Hi-Z params per mip), the GPU reads the LAST write for ALL dispatches. Fix: use separate buffers per dispatch, or write at different offsets.

**What's NOT GPU-driven (remains on CPU path):**
- Skinned meshes (unique per-instance vertex buffers from compute skinning)
- Shadow rendering (uses CPU batcher + ObjectUniformManager)
- Transparent sort order (GPU-driven draws transparent groups but without back-to-front sorting)

**Future enhancements:**
- Instance merging: draw groups with instanceCount > 1 for identical mesh+material objects
- Two-phase occlusion: cull against prev Hi-Z → depth prepass → new Hi-Z → re-cull
- Meshlet-level culling via mesh shaders
- GPU-driven shadow caster rendering

**Deliverable:** GPU-driven culling and indirect draw for massive scenes. Debug Hi-Z visualization via ImGui mip slider.

---

### Phase 18: Overlay Rendering & Profiling

**Goal:** Comprehensive overlay drawing system for both debug visualization and game UI (HUD markers, health bars, selection highlights, etc.), plus GPU profiling.

The legacy `OverlayRenderFeature` proved that "debug rendering" quickly becomes a general-purpose overlay used by the game too. Design it as a first-class feature from the start.

**Files:**
```
  src/
    Overlay/
      OverlayRenderer.bf         — Immediate-mode overlay draw API
      OverlayFeature.bf          — Render feature (adds passes to render graph)
      DebugFont.bf               — Built-in bitmap font (R8Unorm atlas, ASCII)
    Debug/
      DebugVisualizations.bf     — Debug view mode helpers (cascade viz, cluster heatmap, etc.)
      RenderProfiler.bf          — GPU timing via render graph profiler
    Shaders/
      overlay_lines.hlsl         — Colored line/triangle rendering
      overlay_text3d.hlsl        — World-space billboard text
      overlay_text2d.hlsl        — Screen-space text
```

**OverlayRenderMode:**
```
DepthTest    — Depth-tested, integrates with scene geometry
Overlay      — Always on top, ignores depth buffer
```

**OverlayRenderer API — Primitives:**
```
AddLine(Vector3 start, Vector3 end, Color, OverlayRenderMode mode = .DepthTest)
AddTriangle(Vector3 v0, Vector3 v1, Vector3 v2, Color, OverlayRenderMode mode = .DepthTest)
AddQuad(Vector3 v0, Vector3 v1, Vector3 v2, Vector3 v3, Color, OverlayRenderMode mode = .DepthTest)
```

**OverlayRenderer API — Wireframe Shapes:**
```
AddBox(BoundingBox, Color, OverlayRenderMode)
AddBox(Vector3 center, Vector3 halfExtents, Color, OverlayRenderMode)
AddTransformedBox(BoundingBox localBounds, Matrix worldMatrix, Color, OverlayRenderMode) — OBB
AddSphere(Vector3 center, float radius, Color, int segments = 16, OverlayRenderMode)
AddSphere(BoundingSphere, Color, int segments = 16, OverlayRenderMode)
AddCapsule(Vector3 center, float radius, float height, Color, int segments = 16, OverlayRenderMode)
AddCylinder(Vector3 center, float radius, float height, Color, int segments = 16, OverlayRenderMode)
AddCone(Vector3 apex, Vector3 direction, float length, float angle, Color, int segments = 16, OverlayRenderMode)
AddCircle(Vector3 center, float radius, Vector3 normal, Color, int segments = 32, OverlayRenderMode)
```

**OverlayRenderer API — Filled Shapes:**
```
AddFilledBox(BoundingBox, Color, OverlayRenderMode)
AddRect2D(float x, float y, float width, float height, Color) — Screen-space filled rect
```

**OverlayRenderer API — Utility Shapes:**
```
AddAxes(Vector3 position, float size = 1.0, OverlayRenderMode) — RGB XYZ axes
AddAxes(Vector3 position, Matrix rotation, float size = 1.0, OverlayRenderMode) — Rotated axes
AddFrustum(Matrix viewProjection, Color, OverlayRenderMode)
AddGrid(Vector3 center, float size, int divisions, Color, OverlayRenderMode) — XZ plane grid
AddArrow(Vector3 start, Vector3 end, Color, float headSize = 0.1, OverlayRenderMode)
AddRay(Vector3 origin, Vector3 direction, Color, OverlayRenderMode)
AddCross(Vector3 center, float size, Color, OverlayRenderMode) — 3D cross
```

**OverlayRenderer API — Text:**
```
AddText(StringView text, Vector3 position, Color, float scale, Vector3 right, Vector3 up, OverlayRenderMode)
AddTextCentered(StringView text, Vector3 position, Color, float scale, Vector3 right, Vector3 up, OverlayRenderMode)
AddText2D(StringView text, float x, float y, Color, float scale = 1.0) — Screen-space
AddText2DRight(StringView text, float rightMargin, float y, Color, float scale = 1.0) — Right-aligned
```

**OverlayRenderer API — Frame Management:**
```
BeginFrame()
SetViewProjection(Matrix viewProjection)
SetScreenSize(uint32 width, uint32 height)
```

**Rendering Details:**
- Separate vertex buffers per primitive type (lines, triangles, text3D, text2D)
- Separate pipelines for DepthTest vs Overlay mode (depth enabled/disabled)
- All primitives use alpha blending, CullMode.None
- Color format: RGBA16Float (HDR-capable, composites correctly with scene)
- Font atlas: built-in bitmap font, R8Unorm texture, linear sampled
- Per-frame Map/Unmap upload (no transfer batch needed — overlay data changes every frame)
- Max vertices: configurable (default 65536 per type)

**Debug Visualization Modes (built on top of OverlayRenderer):**
- Wireframe overlay
- Normal vectors
- Motion vectors (color-coded)
- Shadow cascade boundaries
- Light cluster heatmap
- Hi-Z pyramid mip levels
- Bounding boxes (mesh, light, decal volumes)
- LOD level coloring

**RenderProfiler:**
- Wraps `GraphProfiler` from RenderGraph
- Per-pass GPU timing (ms)
- Frame time graph (rolling window)
- Draw call / triangle / instance counts
- Memory usage tracking
- Displayed via OverlayRenderer.AddText2D

**Deliverable:** Full overlay drawing system usable by both debug tools and game code. GPU profiling overlay.

---

### Phase 19: Final Output & Multi-View Compositing

**Goal:** Composite final result to swap chain, handle split-screen layout.

**Files:**
```
  src/
    Features/
      FinalOutputFeature.bf      — Composite to swap chain
    Shaders/
      final_output.hlsl          — Full-screen copy/blit to swap chain
```

**FinalOutputFeature:**
- Single view: blit post-processed scene to swap chain
- Multi-view: composite up to 4 views into swap chain (split-screen layout)
- Handles format conversion (RGBA16Float → swap chain format)
- Optional UI overlay compositing point

**Deliverable:** Final image presented to screen. Split-screen works.

---

### Phase 20: Async Compute & Performance Optimization

**Goal:** Overlap compute work with graphics for better GPU utilization.

**Key optimizations:**
- Light culling on async compute (overlap with shadow rendering)
- Hi-Z generation on async compute (overlap with shadow rendering)
- Particle simulation on async compute (overlap with rendering)
- Volumetric fog injection/accumulation on async compute
- Auto-exposure histogram on async compute

**RenderGraph handles this naturally** — passes on different `QueueType` values get scheduled with timeline fence sync.

**Additional optimizations:**
- Pipeline pre-warming at load time (compile all known variants)
- Descriptor set caching / bindless transition
- Staging ring buffer for per-frame uploads (avoid map/unmap overhead)
- Reduced-precision intermediate targets where possible (R11G11B10Float for scene color)

**Deliverable:** Measurable GPU utilization improvement from overlapped compute. Pipeline cache warm-up reduces frame hitches.

---

## Summary: Phase Dependencies

```
Phase 1:  Core Framework
Phase 2:  GPU Resource Management         → depends on Phase 1
Phase 3:  Material & Shader System         → depends on Phase 2
Phase 4:  Visibility, Culling & Batching   → depends on Phase 2
Phase 5:  Depth Prepass & Forward Opaque   → depends on Phase 3, 4
Phase 6:  Lighting System                  → depends on Phase 5
Phase 7:  Shadow System                    → depends on Phase 6
Phase 8:  Transparent & Motion Vectors     → depends on Phase 5, 6
Phase 9:  Post-Processing Stack            → depends on Phase 8
Phase 10: Sky & Environment                → depends on Phase 6
Phase 11: GPU Skinning                     → depends on Phase 5
Phase 12: Particle System                  → depends on Phase 5
Phase 13: Terrain, Water, Grass            → depends on Phase 5, 6, 7
Phase 14: Decals & Sprites                 → depends on Phase 5
Phase 15: Volumetric Fog                   → depends on Phase 6
Phase 16: Reflection Probes                → depends on Phase 10
Phase 17: GPU-Driven Rendering             → depends on Phase 4, 5
Phase 18: Debug Rendering & Profiling      → depends on Phase 1
Phase 19: Final Output & Multi-View        → depends on Phase 9
Phase 20: Async Compute & Optimization     → depends on all above
```

Phases 10-16 are largely independent of each other and can be implemented in any order after their dependencies are met.

---

## Milestone Checkpoints

**M1 — Lit Scene (Phases 1-7):** Static PBR meshes with multiple lights and shadows. This is the minimum viable renderer.

**M2 — Full Pipeline (Phases 8-9):** Transparent objects, motion vectors, and complete post-processing. Production-quality image output.

**M3 — Environment (Phases 10-11):** Sky, IBL, and skeletal animation. Characters and outdoor scenes.

**M4 — World Features (Phases 12-16):** Particles, terrain, water, grass, decals, volumetric fog, reflection probes. Complete feature set matching legacy.

**M5 — Performance (Phases 17-20):** GPU-driven rendering, async compute, debug tools. Ready for shipping games.
