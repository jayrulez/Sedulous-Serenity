# Sedulous.Renderer

Low-level 3D rendering library providing GPU-accelerated rendering for meshes, materials, lighting, particles, sprites, and post-processing effects.

## Overview

```
Sedulous.Renderer
├── Resources/
│   └── GPUResourceManager       - Mesh and texture GPU resources
├── Materials/
│   ├── Material                 - Material definitions
│   ├── MaterialInstance         - Per-object material instances
│   ├── MaterialSystem           - Material management
│   └── PipelineCache            - Render pipeline caching
├── Shaders/
│   └── ShaderLibrary            - Shader loading and caching
├── Lighting/
│   ├── LightingSystem           - Light clustering and management
│   ├── CascadedShadowMaps       - Directional light shadows
│   └── ShadowAtlas              - Point/spot light shadows
├── Renderers/
│   ├── StaticMeshRenderer       - Static geometry
│   ├── SkinnedMeshRenderer      - Animated skeletal meshes
│   ├── SpriteRenderer           - 2D billboards
│   ├── ParticleRenderer         - Particle systems
│   ├── SkyboxRenderer           - Background rendering
│   ├── ShadowRenderer           - Shadow pass rendering
│   └── TrailRenderer            - Particle trails
├── Visibility/
│   ├── FrustumCuller            - Frustum culling
│   └── VisibilityResolver       - Visibility determination
├── World/
│   ├── RenderWorld              - Proxy storage
│   ├── StaticMeshProxy          - Mesh render data
│   ├── SkinnedMeshProxy         - Skinned mesh data
│   ├── LightProxy               - Light render data
│   ├── CameraProxy              - Camera render data
│   ├── SpriteProxy              - Sprite render data
│   └── ParticleEmitterProxy     - Particle emitter data
├── Views/
│   └── RenderView               - Unified view abstraction
├── Graph/
│   └── RenderGraph              - Automatic pass management
├── RenderPipeline               - Render orchestration
├── RenderContext                - Per-scene rendering context
└── Particles/
    ├── ParticleSystem           - CPU simulation
    ├── ParticleEmitterConfig    - Emitter configuration
    ├── ParticleCurve            - Property animation
    ├── ParticleModules          - Composable behaviors
    ├── EmissionShape            - Emission shapes
    ├── ForceField               - Scene-level forces
    ├── SubEmitter               - Child particle spawning
    └── TrailParticle            - Trail/ribbon support
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                       RenderContext                              │
│  ├── RenderWorld (proxy storage)                                │
│  ├── LightingSystem (clustering, shadows)                       │
│  └── VisibilityResolver (frustum culling)                       │
├─────────────────────────────────────────────────────────────────┤
│                       RenderPipeline                             │
│  ├── StaticMeshRenderer                                         │
│  ├── SkinnedMeshRenderer                                        │
│  ├── ParticleRenderer                                           │
│  ├── SpriteRenderer                                             │
│  ├── SkyboxRenderer                                             │
│  ├── ShadowRenderer                                             │
│  └── TrailRenderer                                              │
├─────────────────────────────────────────────────────────────────┤
│                       Shared Resources                           │
│  ├── GPUResourceManager (meshes, textures)                      │
│  ├── MaterialSystem (materials, instances)                      │
│  ├── ShaderLibrary (shader compilation)                         │
│  └── PipelineCache (pipeline management)                        │
└─────────────────────────────────────────────────────────────────┘
```

---

## GPU Resource Manager

Manages GPU resources (meshes, textures, skinned meshes) with reference counting and handle-based access.

### Usage

```beef
using Sedulous.Renderer;

// Create mesh from CPU data
let meshHandle = resourceManager.CreateMesh(staticMesh);

// Access mesh for rendering
if (let gpuMesh = resourceManager.GetMesh(meshHandle))
{
    // Use gpuMesh.VertexBuffer, gpuMesh.IndexBuffer, etc.
}

// Reference counting
resourceManager.AddMeshRef(meshHandle);  // Increment
resourceManager.ReleaseMesh(meshHandle); // Decrement, frees at 0

// Textures
let textureHandle = resourceManager.CreateTexture(image, generateMips: true);
if (let gpuTexture = resourceManager.GetTexture(textureHandle))
{
    // Use gpuTexture.Texture, gpuTexture.View
}
resourceManager.ReleaseTexture(textureHandle);

// Skinned meshes
let skinnedHandle = resourceManager.CreateSkinnedMesh(skinnedMesh);
```

### Handles

| Handle Type | Description |
|-------------|-------------|
| `GPUStaticMeshHandle` | Static mesh resource |
| `GPUTextureHandle` | Texture resource |
| `GPUSkinnedMeshHandle` | Skinned mesh resource |

### GPUStaticMesh Properties

| Property | Type | Description |
|----------|------|-------------|
| `VertexBuffer` | `IBuffer` | Vertex data |
| `IndexBuffer` | `IBuffer` | Index data |
| `IndexCount` | `uint32` | Number of indices |
| `VertexCount` | `uint32` | Number of vertices |
| `Bounds` | `BoundingBox` | Local-space bounds |
| `SubMeshes` | `List<SubMesh>` | Sub-mesh definitions |

### GPUTexture Properties

| Property | Type | Description |
|----------|------|-------------|
| `Texture` | `ITexture` | GPU texture |
| `View` | `ITextureView` | Shader resource view |
| `Width`, `Height` | `uint32` | Dimensions |
| `Format` | `TextureFormat` | Pixel format |
| `MipLevels` | `uint32` | Mip chain length |

---

## Material System

### Materials

Materials define shader bindings, render states, and parameter declarations.

```beef
// Create PBR material
let material = Material.CreatePBR("MyMaterial");

// Or create unlit material
let unlit = Material.CreateUnlit("UnlitMaterial");

// Custom material
let custom = new Material("CustomMaterial");
custom.ShaderName = "custom_shader";
custom.BlendMode = .AlphaBlend;
custom.CullMode = .None;
custom.DepthMode = .ReadOnly;
custom.RenderQueue = 2500;  // Transparent queue

// Add parameters
custom.AddFloatParam("roughness", binding: 0, offset: 0);
custom.AddFloat4Param("baseColor", binding: 0, offset: 4);
custom.AddTextureParam("albedoMap", binding: 0);
custom.AddSamplerParam("albedoSampler", binding: 0);

// Register with system
let materialHandle = materialSystem.RegisterMaterial(material);
```

#### Material Properties

| Property | Type | Description |
|----------|------|-------------|
| `Name` | `String` | Material name |
| `ShaderName` | `String` | Shader to use |
| `ShaderFlags` | `uint32` | Shader variant flags |
| `BlendMode` | `MaterialBlendMode` | Blend mode |
| `CullMode` | `CullMode` | Face culling |
| `DepthMode` | `DepthMode` | Depth testing |
| `RenderQueue` | `int32` | Render order |
| `UniformBufferSize` | `uint32` | Uniform buffer size |

#### Blend Modes

| Mode | Description |
|------|-------------|
| `Opaque` | No blending |
| `AlphaBlend` | Standard transparency |
| `Additive` | Add to background |
| `Multiply` | Darken background |
| `PremultipliedAlpha` | Pre-multiplied alpha |

#### Render Queue Ranges

| Range | Description |
|-------|-------------|
| 0-999 | Opaque geometry |
| 1000-1999 | Alpha-tested geometry |
| 2000+ | Transparent geometry |

### Material Instances

Instances hold per-object parameter values.

```beef
// Create instance from material
let instanceHandle = materialSystem.CreateInstance(materialHandle);

// Set parameters
if (let instance = materialSystem.GetInstance(instanceHandle))
{
    instance.SetFloat("roughness", 0.5f);
    instance.SetFloat4("baseColor", .(1, 0.5f, 0.2f, 1));
    instance.SetColor("tint", Color.White);
    instance.SetTexture("albedoMap", textureHandle);
    instance.SetSampler("albedoSampler", sampler);
    instance.SetMatrix("customTransform", matrix);
}

// Upload to GPU (call each frame if dirty)
materialSystem.UploadInstance(instanceHandle);
```

#### Instance Methods

| Method | Description |
|--------|-------------|
| `SetFloat(name, value)` | Set scalar parameter |
| `SetFloat2/3/4(name, value)` | Set vector parameters |
| `SetColor(name, color)` | Set color parameter |
| `SetMatrix(name, matrix)` | Set matrix parameter |
| `SetTexture(name, handle)` | Bind texture |
| `SetSampler(name, sampler)` | Bind sampler |
| `Upload(queue)` | Upload uniforms to GPU |

### MaterialSystem

Manages materials, instances, and bind group layouts.

```beef
// Register material
let handle = materialSystem.RegisterMaterial(material);

// Create instances
let instance = materialSystem.CreateInstance(handle);

// Access
let mat = materialSystem.GetMaterial(handle);
let inst = materialSystem.GetInstance(instance);

// Bind groups
let layout = materialSystem.GetOrCreateBindGroupLayout(material);
let bindGroup = materialSystem.CreateBindGroup(instance, layout);

// Default resources
let whiteTex = materialSystem.WhiteTexture;    // 1x1 white
let normalTex = materialSystem.NormalTexture;  // 1x1 flat normal
let blackTex = materialSystem.BlackTexture;    // 1x1 black
let sampler = materialSystem.DefaultSampler;   // Linear, clamp
```

---

## Shader Library

Loads and caches shaders from disk.

```beef
// Load shaders from directory
shaderLibrary.LoadShadersFromPath("assets/shaders");

// Get shader module
let vertexShader = shaderLibrary.GetShader("mesh.vert");
let fragmentShader = shaderLibrary.GetShader("mesh.frag");

// Check if loaded
if (shaderLibrary.HasShader("custom.vert"))
{
    // Use shader
}
```

---

## Pipeline Cache

Caches render pipelines by configuration to avoid redundant creation.

```beef
// Define pipeline key
let key = PipelineKey() {
    Material = material,
    VertexLayoutHash = vertexLayout.GetHashCode(),
    ColorFormat = .BGRA8Unorm,
    DepthFormat = .Depth32Float,
    SampleCount = 1
};

// Get or create pipeline
if (pipelineCache.GetMaterialPipeline(key, vertexBuffers, sceneLayout, materialLayout) case .Ok(let cached))
{
    // Use cached.Pipeline, cached.PipelineLayout
}

// Clear cache (e.g., on format change)
pipelineCache.Clear();
```

---

## Render Pipeline

Stateless rendering orchestrator that owns sub-renderers and coordinates rendering.

### Initialization

```beef
let pipeline = new RenderPipeline();
pipeline.Initialize(device, shaderLibrary, materialSystem,
                    resourceManager, pipelineCache, colorFormat, depthFormat);
pipeline.InitializeRenderers(lightingSystem);
```

### Frame Rendering

```beef
// Prepare visibility and batches
pipeline.PrepareVisibility(context);

// Upload GPU data for all views
pipeline.PrepareGPU(context);

// Render shadow passes
pipeline.RenderShadows(context, encoder);

// Render main views
pipeline.RenderViews(context, renderPass,
    renderSkybox: true,
    renderParticles: true,
    renderSprites: true,
    depthTextureView);
```

### Camera Uniforms

```beef
// Upload camera data (supports up to 4 simultaneous views)
pipeline.UploadCameraUniforms(view, frameIndex);
pipeline.UploadCameraUniforms(view, frameIndex, viewSlot: 1);

// Billboard camera (for sprites/particles)
pipeline.UploadBillboardCameraUniforms(view, frameIndex);
```

### Soft Particles

```beef
// Prepare depth texture for soft particle rendering
pipeline.PrepareSoftParticleBindGroups(frameIndex, depthTextureView);
let bindGroup = pipeline.GetSoftParticleBindGroup(frameIndex);
```

### Accessing Renderers

```beef
let staticRenderer = pipeline.StaticMeshRenderer;
let skinnedRenderer = pipeline.SkinnedMeshRenderer;
let particleRenderer = pipeline.ParticleRenderer;
let spriteRenderer = pipeline.SpriteRenderer;
let skyboxRenderer = pipeline.SkyboxRenderer;
let shadowRenderer = pipeline.ShadowRenderer;
let trailRenderer = pipeline.TrailRenderer;
```

---

## Render Graph

Frame-based render graph managing passes, resources, and dependencies.

```beef
let graph = new RenderGraph(device);

// Begin frame
graph.BeginFrame(frameIndex, deltaTime, totalTime);

// Import external resources
let swapChain = graph.ImportTexture("swapchain", texture, view, .Undefined);
let depthBuffer = graph.ImportTexture("depth", depthTex, depthView, .Undefined);

// Create transient resources (live one frame)
let hdrBuffer = graph.CreateTransientTexture("hdr", TextureDescription() {
    Width = width, Height = height,
    Format = .RGBA16Float,
    Usage = .RenderTarget | .ShaderResource
});

// Add graphics pass
let mainPass = graph.AddGraphicsPass("MainPass");
mainPass.SetColorTarget(0, hdrBuffer, .Clear(.(0, 0, 0, 1)));
mainPass.SetDepthTarget(depthBuffer, .Clear(1.0f));
mainPass.Read(shadowMap);  // Declare read dependency
mainPass.SetExecute(new (encoder, pass) => {
    // Render geometry
});

// Add compute pass
let computePass = graph.AddComputePass("PostProcess");
computePass.Read(hdrBuffer);
computePass.Write(swapChain);
computePass.SetExecute(new (encoder, pass) => {
    // Post-processing
});

// Compile and execute
graph.Compile();  // Build dependencies, allocate resources, compute barriers
graph.Execute(encoder);
graph.EndFrame();  // Return transients to pool
```

---

## Lighting System

Manages clustered lighting, shadow maps, and light data upload.

### Setup

```beef
let lighting = new LightingSystem();
lighting.Initialize(device, shaderLibrary);
```

### Per-Frame Update

```beef
// Update from camera and lights
lighting.Update(cameraProxy, lights, frameIndex);
// Or from render view
lighting.UpdateFromView(renderView, lights, frameIndex);

// Prepare shadow data
lighting.PrepareShadows(cameraProxy);
lighting.UploadShadowUniforms(frameIndex);
```

### Accessing Resources

```beef
// Light buffers
let lightingBuffer = lighting.GetLightingUniformBuffer(frameIndex);
let lightBuffer = lighting.GetLightBuffer(frameIndex);
let gridBuffer = lighting.GetLightGridBuffer(frameIndex);
let indexBuffer = lighting.GetLightIndexBuffer(frameIndex);

// Shadow resources
let shadowBuffer = lighting.GetShadowUniformBuffer(frameIndex);
let shadowSampler = lighting.ShadowSampler;  // PCF comparison sampler
let cascadeView = lighting.CascadeShadowMapView;
let atlasView = lighting.ShadowAtlasView;

// Current directional light
let sunLight = lighting.DirectionalLight;
```

### Statistics

| Property | Description |
|----------|-------------|
| `VisibleLightCount` | Point/spot lights visible |
| `ShadowCasterCount` | Lights casting shadows |
| `LocalLightCount` | Point/spot light count |
| `ActiveShadowTileCount` | Atlas tiles allocated |

### Cascaded Shadow Maps

4-cascade directional shadow mapping:

```beef
let cascades = lighting.CascadedShadows;

// Update cascades
cascades.UpdateCascades(camera, lightDirection);

// Access cascade data
for (int i < 4)
{
    let data = cascades.CascadeData[i];  // ViewProjection, SplitDepths
    let view = cascades.GetCascadeView(i);
    let splitDist = cascades.GetSplitDistance(i);
}
```

### Shadow Atlas

8x8 grid of 512x512 tiles for point/spot shadows:

```beef
let atlas = lighting.ShadowAtlas;

// Allocate tile for light
int32 slot = atlas.AllocateTile(lightProxy, faceIndex: 0);

// Get viewport for rendering
let (x, y, width, height) = atlas.GetTileViewport(slot);

// Reset each frame
atlas.Reset();
```

---

## Renderers

### StaticMeshRenderer

Renders static meshes with material batching.

```beef
// Build batches from visible meshes
staticRenderer.BuildBatches(visibleMeshes);

// Upload instance data
staticRenderer.PrepareGPU(frameIndex);

// Render
staticRenderer.RenderMaterials(renderPass, sceneBindGroup, frameIndex);

// Statistics
int instanceCount = staticRenderer.MaterialInstanceCount;
int visibleCount = staticRenderer.VisibleMeshCount;
```

### SkinnedMeshRenderer

Renders skeletal animated meshes.

```beef
// Build batches
skinnedRenderer.BuildBatches();

// Render with bone transforms
skinnedRenderer.Render(renderPass, cameraBuffer, sceneBindGroup, frameIndex);

// Bind groups: 0=Scene, 1=Object (bones), 2=Material
```

### SpriteRenderer

Batched billboard rendering.

```beef
// Render all sprites (auto-batched by texture)
spriteRenderer.Render(renderPass, frameIndex, useNoDepthPipelines: false);

// Max 10,000 sprites per batch
```

### SkyboxRenderer

Background rendering.

```beef
// Create gradient sky
skyboxRenderer.SetGradientSky(topColor, bottomColor);

// Render (no depth test, renders behind everything)
skyboxRenderer.Render(renderPass, frameIndex);
```

### ShadowRenderer

Shadow pass rendering.

```beef
// Render all shadow passes (cascades + atlas)
bool rendered = shadowRenderer.RenderShadows(encoder, frameIndex,
    staticRenderer, skinnedRenderer);
```

---

## Visibility System

### FrustumCuller

```beef
let culler = new FrustumCuller();

// Set from camera or view
culler.SetCamera(cameraProxy);
culler.SetView(renderView);

// Layer filtering
culler.SetLayerMask(0xFFFFFFFF);  // All layers

// Test visibility
if (culler.IsVisible(boundingBox))
{
    // Object is in frustum
}

// Bulk culling
culler.CullMeshes(allMeshes, outVisibleMeshes, cameraPos);
culler.CullLights(allLights, outVisibleLights);
culler.CullParticleEmitters(allEmitters, outVisibleEmitters, cameraPos);
```

### VisibilityResolver

Complete visibility with sorting.

```beef
let resolver = new VisibilityResolver();

// Resolve from camera
resolver.Resolve(renderWorld, cameraProxy);
// Or from view
resolver.ResolveForView(renderWorld, renderView);

// Sorted results
let opaque = resolver.OpaqueMeshes;          // Front-to-back
let transparent = resolver.TransparentMeshes; // Back-to-front
let shadowCasters = resolver.ShadowCasters;
let lights = resolver.VisibleLights;
let particles = resolver.VisibleParticleEmitters;  // Back-to-front
```

---

## Render World

Storage and management of all render proxies.

### Static Mesh Proxies

```beef
// Create proxy
let handle = renderWorld.CreateStaticMeshProxy(gpuMesh, transform, localBounds);

// Access proxy
if (let proxy = renderWorld.GetStaticMeshProxy(handle))
{
    proxy.MaterialInstances[0] = materialInstance;
    proxy.CastsShadows = true;
    proxy.LayerMask = 0x1;
}

// Update transform
renderWorld.SetStaticMeshTransform(handle, newTransform);

// Destroy
renderWorld.DestroyStaticMeshProxy(handle);

// Get all valid proxies
renderWorld.GetValidStaticMeshProxies(outList);
```

### Skinned Mesh Proxies

```beef
let handle = renderWorld.CreateSkinnedMeshProxy(gpuSkinnedMesh, transform, localBounds);

if (let proxy = renderWorld.GetSkinnedMeshProxy(handle))
{
    proxy.MaterialInstance = materialInstance;
    // Update bone matrices each frame
    for (int i < boneCount)
        proxy.BoneMatrices[i] = boneTransforms[i];
}
```

### Light Proxies

```beef
// Create lights
let dirLight = renderWorld.CreateDirectionalLight(direction, color, intensity);
let pointLight = renderWorld.CreatePointLight(position, color, intensity, range);
let spotLight = renderWorld.CreateSpotLight(position, direction, color, intensity,
    range, innerAngle, outerAngle);

// Access and modify
if (let light = renderWorld.GetLightProxy(pointLight))
{
    light.Color = .(1, 0.8f, 0.6f);
    light.Intensity = 2.0f;
    light.CastsShadows = true;
}

renderWorld.DestroyLightProxy(dirLight);
```

### Camera Proxies

```beef
let handle = renderWorld.CreateCamera(camera, viewportWidth, viewportHeight, isMain: true);

if (let proxy = renderWorld.GetCameraProxy(handle))
{
    // Access matrices
    let viewProj = proxy.ViewProjectionMatrix;
    let frustum = proxy.FrustumPlanes;
}

// Set main camera
renderWorld.SetMainCamera(handle);
let mainCam = renderWorld.MainCamera;
```

### Sprite Proxies

```beef
let handle = renderWorld.CreateSpriteProxy(position, size, color);
// Or with UV rect
let handle = renderWorld.CreateSpriteProxy(position, size, uvRect, color);

renderWorld.SetSpritePosition(handle, newPos);
renderWorld.SetSpriteSize(handle, newSize);
renderWorld.SetSpriteColor(handle, newColor);
renderWorld.SetSpriteUVRect(handle, newUV);

renderWorld.DestroySpriteProxy(handle);
```

### Force Fields

```beef
// Create force fields
let wind = renderWorld.CreateDirectionalForceField(direction, strength);
let attractor = renderWorld.CreatePointForceField(position, strength, radius, falloff);
let vortex = renderWorld.CreateVortexForceField(position, axis, strength, radius);
let turbulence = renderWorld.CreateTurbulenceForceField(position, strength,
    radius, frequency, octaves);

// Control
renderWorld.SetForceFieldEnabled(wind, false);
renderWorld.SetForceFieldStrength(attractor, 15.0f);
renderWorld.SetForceFieldPosition(vortex, newPos);

// Query total force at position
let force = renderWorld.CalculateTotalForceFieldForce(position, time, layerMask);

renderWorld.DestroyForceField(wind);
```

### Render Views

```beef
// Clear views each frame
renderWorld.ClearRenderViews();

// Add main camera view
let viewIndex = renderWorld.AddMainCameraView(colorTarget, depthTarget);

// Add custom camera view
let viewIndex = renderWorld.AddCameraView(cameraHandle, colorTarget, depthTarget, isMain: false);

// Add shadow cascade views
let count = renderWorld.AddShadowCascadeViews(cascadeData, depthTargets,
    shadowMapSize, lightHandle, layerMask);

// Add local shadow view (atlas tile)
let viewIndex = renderWorld.AddLocalShadowView(atlasSlot, viewProjection,
    depthTarget, x, y, tileSize, lightHandle, layerMask);

// Access views
let views = renderWorld.RenderViews;
let mainView = renderWorld.GetRenderView(0);
renderWorld.GetSortedViews(outViews);
renderWorld.GetEnabledSortedViews(outViews);
```

### Frame Lifecycle

```beef
// Start of frame
renderWorld.BeginFrame();  // Updates camera matrices

// ... rendering ...

// End of frame
renderWorld.EndFrame();  // Saves previous transforms, clears culling flags
```

---

## Render View

Unified abstraction for any rendering viewpoint.

### View Types

| Type | Description |
|------|-------------|
| `MainCamera` | Primary display view |
| `SecondaryCamera` | Split-screen/PIP |
| `ShadowCascade` | Cascaded shadow map |
| `ShadowLocal` | Point/spot shadow (atlas) |
| `ReflectionProbe` | Reflection capture |
| `Custom` | User-defined |

### View Flags

| Flag | Description |
|------|-------------|
| `Enabled` | View is active |
| `ClearColor` | Clear color buffer |
| `ClearDepth` | Clear depth buffer |
| `ReverseZ` | Use reverse-Z depth |
| `Orthographic` | Orthographic projection |
| `DepthOnly` | Depth-only pass |

### Properties

```beef
// Transform
view.Position, view.Forward, view.Up, view.Right
view.ViewMatrix, view.ProjectionMatrix, view.ViewProjectionMatrix

// Projection
view.NearPlane, view.FarPlane
view.FieldOfViewOrSize  // FOV (perspective) or size (ortho)
view.AspectRatio

// Culling
view.FrustumPlanes[6]
view.LayerMask

// Viewport
view.ViewportX, view.ViewportY, view.ViewportWidth, view.ViewportHeight

// Render targets
view.ColorTarget, view.DepthTarget
view.ClearColor, view.ClearDepth

// Type-specific
view.SubIndex       // Cascade index, atlas slot, cube face
view.SourceCamera   // Source camera proxy
view.SourceLight    // Source light proxy
```

---

## Render Context

Per-scene rendering context that consolidates all rendering state.

```beef
// Create context
let context = RenderContext.Create(device).Value;

// Owned systems
let world = context.World;           // RenderWorld
let lighting = context.Lighting;     // LightingSystem
let visibility = context.Visibility; // VisibilityResolver

// Frame state
context.FrameIndex;
context.ViewCount;
context.MainView;

// Get views
let views = context.GetViews();
let enabledViews = context.GetEnabledSortedViews();

// Scene bind groups (for rendering)
let bindGroup = context.GetSceneBindGroup(frameIndex);
let viewBindGroup = context.GetViewBindGroup(frameIndex, viewSlot);
```

---

## Particle System

The particle system provides CPU-driven simulation with GPU rendering, supporting a wide range of visual effects.

### Quick Start

```beef
using Sedulous.Renderer;
using Sedulous.Mathematics;

// Create particle system with default config
let particles = new ParticleSystem(device, maxParticles: 1000);

// Configure the emitter
let config = particles.Config;
config.EmissionRate = 100;
config.Lifetime = .(1.0f, 2.0f);
config.InitialSpeed = .(2.0f, 5.0f);
config.InitialSize = .(0.1f, 0.3f);
config.SetConeEmission(30);  // 30 degree cone
config.Gravity = .(0, -9.81f, 0);
config.BlendMode = .Additive;
config.SetColorOverLifetime(.(255, 255, 100, 255), .(255, 50, 0, 0));

// Position the emitter
particles.Position = .(0, 0, 0);

// In update loop
particles.CameraPosition = cameraPos;  // For sorting and LOD
particles.Update(deltaTime);
particles.Upload();  // Upload to GPU

// Render (via ParticleRenderer or manually)
particleRenderer.Render(renderPass, frameIndex, particles);

// Cleanup
delete particles;
```

### Using Preset Configs

```beef
// Fire effect
let fireConfig = ParticleEmitterConfig.CreateFire();
let fire = new ParticleSystem(device, fireConfig, 500);

// Smoke effect
let smokeConfig = ParticleEmitterConfig.CreateSmoke();
let smoke = new ParticleSystem(device, smokeConfig, 300);

// Sparks effect
let sparksConfig = ParticleEmitterConfig.CreateSparks();
let sparks = new ParticleSystem(device, sparksConfig, 200);

// Firework with sub-emitters
let fireworkConfig = ParticleEmitterConfig.CreateFirework();
let firework = new ParticleSystem(device, fireworkConfig, 100);

// Magic sparkle
let magicConfig = ParticleEmitterConfig.CreateMagicSparkle();
let magic = new ParticleSystem(device, magicConfig, 400);

// Important: When using external configs, you own them
defer delete fireConfig;  // Config not owned by ParticleSystem
```

### Emitter Configuration

```beef
class ParticleEmitterConfig
{
    // Emission
    float EmissionRate = 10;           // Particles per second
    int32 BurstCount = 0;              // Particles per burst
    float BurstInterval = 0;           // Time between bursts

    // Lifetime
    RangeFloat Lifetime = .(1, 2);     // Min/max lifetime in seconds

    // Initial state (randomized within range)
    RangeFloat InitialSpeed = .(1, 5);
    RangeFloat InitialSize = .(0.1f, 0.5f);
    RangeFloat InitialRotation = .(0, Math.PI_f * 2);
    RangeFloat InitialRotationSpeed = .(0, 0);

    // Color (start/end interpolation)
    RangeColor StartColor;
    RangeColor EndColor;

    // Physics
    Vector3 Gravity = .(0, -9.81f, 0);
    float Drag = 0;

    // Rendering
    ParticleRenderMode RenderMode = .Billboard;
    ParticleBlendMode BlendMode = .AlphaBlend;
    bool SoftParticles = false;
    float SoftParticleDistance = 0.5f;

    // Stretched billboard settings
    float StretchFactor = 1.0f;
    float MinStretchLength = 0.1f;

    // LOD (Level of Detail)
    bool EnableLOD = false;
    float LODStartDistance = 20.0f;
    float LODEndDistance = 100.0f;
    float LODMinEmissionRate = 0.1f;

    // Sorting
    bool SortParticles = false;        // Back-to-front sorting for alpha
}
```

### Emission Shapes

```beef
// Point emission (default)
config.SetPointEmission();

// Cone emission (degrees)
config.SetConeEmission(30);  // 30 degree cone

// Sphere emission
config.SetSphereEmission(radius: 1.0f);
config.SetSphereEmission(radius: 1.0f, fromSurface: true);  // Surface only

// Hemisphere emission
config.SetHemisphereEmission(radius: 1.0f);

// Box emission
config.SetBoxEmission(.(2, 1, 2));  // Half-extents

// Circle emission (XZ plane)
config.SetCircleEmission(radius: 1.0f);

// Edge/Line emission
config.SetEdgeEmission(length: 2.0f);
```

### Blend Modes

| Mode | Description | Use Case |
|------|-------------|----------|
| `AlphaBlend` | Standard transparency | Smoke, dust, general |
| `Additive` | Add to background | Fire, glow, lasers, magic |
| `Multiply` | Darken background | Shadows (rare) |
| `Premultiplied` | Pre-multiplied alpha | UI, specific effects |

### Render Modes

| Mode | Description |
|------|-------------|
| `Billboard` | Always face camera |
| `StretchedBillboard` | Stretch along velocity |
| `HorizontalBillboard` | Face up (Y-axis) |
| `VerticalBillboard` | Face camera, stay vertical |

### Property Curves

Animate properties over particle lifetime:

```beef
// Size over lifetime (shrink to 30%)
config.SetSizeOverLifetime(startScale: 1.0f, endScale: 0.3f);

// Color over lifetime
config.SetColorOverLifetime(
    startColor: .(255, 255, 100, 255),
    endColor: .(255, 50, 0, 0)
);

// Or use curves for complex animations
config.SizeOverLifetime = new ParticleCurve<float>();
config.SizeOverLifetime.AddKey(0.0f, 0.5f);   // Start at 50%
config.SizeOverLifetime.AddKey(0.3f, 1.0f);   // Grow to 100%
config.SizeOverLifetime.AddKey(1.0f, 0.2f);   // Shrink to 20%

config.ColorOverLifetime = new ParticleCurve<Color>();
config.ColorOverLifetime.AddKey(0.0f, Color.White);
config.ColorOverLifetime.AddKey(0.5f, Color.Yellow);
config.ColorOverLifetime.AddKey(1.0f, .(255, 0, 0, 0));
```

### Particle Modules

Add composable behaviors to particles:

```beef
// Turbulence (noise-based displacement)
config.AddModule(new TurbulenceModule(
    strength: 2.0f,
    frequency: 1.0f,
    octaves: 2
));

// Vortex (swirling motion)
config.AddModule(new VortexModule(
    axis: .(0, 1, 0),
    strength: 5.0f,
    inwardForce: 0.5f
));

// Attractor (pull toward point)
config.AddModule(new AttractorModule(
    position: .(0, 5, 0),
    strength: 10.0f,
    radius: 5.0f
));

// Wind (directional force)
config.AddModule(new WindModule(
    direction: .(1, 0, 0),
    strength: 3.0f
));
```

### Sub-Emitters

Spawn child particles on events:

```beef
// Create explosion config for when main particle dies
let explosionConfig = new ParticleEmitterConfig();
explosionConfig.Lifetime = .(0.5f, 1.0f);
explosionConfig.InitialSpeed = .(5, 10);
explosionConfig.SetSphereEmission(0.1f);
explosionConfig.BlendMode = .Additive;

// Add sub-emitter triggered on death
config.AddOnDeathSubEmitter(
    explosionConfig,
    emitCount: 30,
    probability: 1.0f,
    inheritColor: true  // Explosion inherits parent color
);

// Or on birth
config.AddOnBirthSubEmitter(sparkConfig, emitCount: 5);
```

### Force Fields

Scene-level forces that affect all particles:

```beef
// Add force fields to RenderWorld
let windHandle = renderWorld.CreateDirectionalForceField(
    direction: .(1, 0, 0),
    strength: 5.0f
);

let attractorHandle = renderWorld.CreatePointForceField(
    position: .(0, 5, 0),
    strength: 10.0f,
    radius: 10.0f,
    falloff: 2.0f  // Quadratic falloff
);

let vortexHandle = renderWorld.CreateVortexForceField(
    position: .(0, 0, 0),
    axis: .(0, 1, 0),
    strength: 8.0f,
    radius: 5.0f,
    inwardForce: 1.0f
);

let turbulenceHandle = renderWorld.CreateTurbulenceForceField(
    position: .(0, 0, 0),
    strength: 3.0f,
    radius: 10.0f,
    frequency: 1.0f,
    octaves: 2
);

// Enable/disable
renderWorld.SetForceFieldEnabled(windHandle, false);

// Cleanup
renderWorld.DestroyForceField(windHandle);
```

### Trails/Ribbons

Connect particles with ribbon trails:

```beef
config.RenderMode = .Trail;
config.TrailLength = 20;              // Points per trail
config.TrailMinVertexDistance = 0.1f; // Min distance between points
config.TrailWidthStart = 0.2f;
config.TrailWidthEnd = 0.0f;          // Taper to point
```

### Soft Particles

Fade particles near surfaces for seamless integration:

```beef
config.SoftParticles = true;
config.SoftParticleDistance = 0.5f;  // Fade distance

// Requires depth texture in render pass
let bindGroup = particleRenderer.CreateSoftParticleBindGroup(frameIndex, depthTextureView);
particleRenderer.Render(renderPass, frameIndex, emitters, nearPlane, farPlane, bindGroup);
```

### Manual Control

```beef
// Burst emit
particles.Burst(count: 50);

// Clear all particles
particles.Clear();

// Start/stop emission
particles.IsEmitting = false;  // Stop
particles.IsEmitting = true;   // Resume

// Get particle count
int32 count = particles.ParticleCount;
int32 total = particles.TotalParticleCount;  // Includes sub-emitters
```

---

## Performance Optimizations

### Particle Sorting

For correct alpha blending, enable sorting:

```beef
config.SortParticles = true;
particles.CameraPosition = cameraPos;  // Required for sorting
```

Sorting is automatic for `AlphaBlend` mode. Additive particles don't need sorting.

### Level of Detail (LOD)

Reduce particle count at distance:

```beef
config.EnableLOD = true;
config.LODStartDistance = 20.0f;   // Full emission within this distance
config.LODEndDistance = 100.0f;    // Minimum emission beyond this
config.LODMinEmissionRate = 0.1f;  // 10% of normal at max distance

particles.CameraPosition = cameraPos;  // Required for LOD
```

### Frustum Culling

Emitters outside the camera frustum are automatically culled:

```beef
// In VisibilityResolver
visibilityResolver.Resolve(renderWorld, camera);
let visibleEmitters = visibilityResolver.VisibleParticleEmitters;

// Statistics
int32 culled = visibilityResolver.CulledParticleEmitterCount;
int32 visible = visibilityResolver.VisibleParticleEmitterCount;
```

### Emitter Batching

ParticleRenderer automatically sorts emitters by blend mode to minimize pipeline switches:

```beef
particleRenderer.RenderEmitters(renderPass, frameIndex, emitters,
    nearPlane, farPlane, softParticleBindGroup,
    useNoDepthPipelines: false,
    sortByBlendMode: true  // Default: true
);

// Statistics
int32 drawCalls = particleRenderer.LastDrawCallCount;
int32 pipelineSwitches = particleRenderer.LastPipelineSwitchCount;
```

### Particle Pooling

ParticleSystem uses a pre-allocated pool for zero runtime allocations:

```beef
// Pool is allocated once based on maxParticles
let particles = new ParticleSystem(device, maxParticles: 1000);

// Particles are recycled, no allocations during emission/death
```

---

## Samples

- **RendererIntegrated**: Full renderer integration sample with meshes, lights, shadows
- **RendererParticles**: Particle effects sample
  - Fountain, fire, smoke, sparks, magic effects
  - Fireworks with sub-emitters
  - LOD and sorting demonstration
  - Controls: 1-5 switch effect, Space spawn firework

---

## See Also

- [Engine Renderer Integration](Engine/Renderer.md) - ParticleEmitterComponent, StaticMeshComponent, etc.
- [RHI Documentation](RHI.md) - Low-level graphics API
