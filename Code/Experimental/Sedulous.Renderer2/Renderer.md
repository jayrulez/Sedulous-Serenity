# Sedulous.Renderer — Progress Tracker

Migration from Sedulous.Render with improved architecture. Each item checked off when sandbox demo confirms it works.

## Future Refactoring Notes

- **RenderPipelineCache**: Currently ported from Serenity as-is (2-set layout: Scene + Material). Consider adopting experimental renderer's cleaner `GetOrCreate(MaterialDefinition, ...)` API once full renderer is ported and stable. The experimental approach also supports a 3rd set for GPU-driven rendering (Set 2: GPUDrivenObject).
- **MaterialInstance.BindGroup**: Not multi-buffered — single bind group shared across all frames. If a material's textures or properties change mid-frame while the GPU is still using the old data, this could cause issues. The experimental renderer multi-buffered material bind groups per frame. Consider adding this if material updates during rendering become a problem.

## Phase 1: Skeleton + SharedResources + Profiling

- [x] `RenderSystem.bf` — Init/Shutdown lifecycle, owns SharedResources + RenderGraph, profiled
- [x] `RenderConfig.bf` — Configuration constants
- [x] `SharedResources.bf` — All default textures + samplers, single batched upload, profiled
- [x] `RenderFrameContext.bf` — Scene uniform buffer, per-frame data
- [x] `IRenderFeature.bf` — Feature interface
- [x] `SkinningSystem.bf` — Infrastructure stub
- [x] `RendererSandbox` — Clear color, P prints init stats
- [x] Init confirmed: 1ms on RTX 3060

## Phase 2: Depth Prepass + Visibility

- [x] `DepthPrepassFeature.bf` — Full port with instancing, skinning, Hi-Z, all draw code active
- [x] `RenderWorld.bf` — Split into 14 extension files (1 per proxy type)
- [x] `RenderView.bf` — Camera/view with frustum extraction, TAA jitter, split-screen
- [x] All 15 proxy types ported (StaticMesh, SkinnedMesh, Light, Camera, + 11 more)
- [x] `GPUMesh.bf` — GPU mesh/texture/bone buffer handles and data classes
- [x] `GPUResourceManager.bf` — Full port with mesh/texture/bone upload, deferred deletion, SProfiler
- [x] `FrustumCuller.bf` — CPU frustum culling with stats
- [x] `VisibilityResolver.bf` — Visible object collection with LOD selection
- [x] `DrawBatcher.bf` — Draw command batching by material/mesh/LOD
- [x] `InstanceBufferManager.bf` — GPU instancing buffer management
- [x] `HiZOcclusionCuller.bf` — Hi-Z occlusion culling
- [x] `SkinningSystem.bf` — Full GPU compute skinning as infrastructure (not feature)
- [x] `SharedBindGroupLayouts.bf` — Shared depth pass layout + object uniform buffers (features don't create own)
- [x] `SceneUniforms.bf` — CRepr struct matching shader cbuffer (464 bytes)
- [x] `ViewContext.bf` — Per-view snapshot with Update(RenderView)
- [x] `RenderFrameContext.bf` — Persistent mapping, UploadUniforms(ViewContext, world)
- [x] `RenderStats.bf` — Centralized draw/dispatch/instance counters
- [x] `RenderConfig.BufferSlot()` — Helper for frame+view buffer slot calculation
- [x] ShaderSystem wired through RenderSystem
- [x] Feature interface: `AddPasses(graph, frameCtx, viewCtx)` — no raw RenderView/RenderWorld
- [x] `TextureData` moved to Sedulous.Textures (shared)
- [x] Sandbox: 5x5 sphere grid + ground plane, FPS camera, depth renders correctly
- [x] Depth buffer verified correct in RenderDoc
- [x] P key shows profiling + render stats

## Phase 3: Forward Opaque + Lighting

- [ ] `ForwardOpaqueFeature.bf` — Forward PBR render pass
- [ ] `LightingSystem.bf` — Light upload (copy) + cluster culling (compute) through graph
- [ ] Sandbox shows lit scene, P shows per-pass timing
- [ ] Visual match with Serenity

## Phase 4: Shadows

- [ ] `ShadowSystem.bf` — Persistent shadow atlas, cascade passes via graph
- [ ] ForwardOpaque reads shadow atlas
- [ ] Sandbox shows shadows, P shows shadow pass timing
- [ ] Shadow passes labeled in RenderDoc

## Phase 5: Sky + IBL

- [ ] `SkyFeature.bf` — Sky render pass + lazy IBL compute passes
- [ ] BRDF LUT + fallback cubemap in SharedResources
- [ ] Sandbox shows sky + reflections, P shows IBL timing
- [ ] No WaitIdle() in init path

## Phase 6: Final Output + Full Integration

- [ ] `FinalOutputFeature.bf` — Blit to backbuffer
- [ ] Full pipeline working in sandbox
- [ ] DX12 + Vulkan validated
- [ ] Init < 5 seconds confirmed
- [ ] All passes labeled in RenderDoc
