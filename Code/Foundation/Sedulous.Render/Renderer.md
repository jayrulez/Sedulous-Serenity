# Sedulous.Render — Improvement Plan

## Context

Sedulous.Render is a copy of the working Serenity renderer (Sedulous.Render) with the
render graph swapped from the built-in implementation to the standalone Sedulous.RenderGraph.
All 22+ samples are verified working.

This document tracks phased improvements to the renderer architecture. Each phase is
independently testable — all samples must continue working after each change.

## Current State

**What works:**
- Full rendering pipeline: depth prepass, forward opaque/transparent, shadows (CSM + atlas),
  sky/IBL, motion vectors, post-processing (15+ effects), GPU skinning, particles,
  decals, terrain, water, grass, sprites, volumetric fog, overlay/debug drawing
- Multi-view rendering (split-screen)
- New Sedulous.RenderGraph with ITexture-keyed barrier tracking

**What needs improvement:**
1. Each feature creates its own fallback textures (duplicate GPU resources)
2. ForwardOpaqueFeature owns lighting, shadows, IBL, probes — too much responsibility
3. `WaitIdle()` calls during init (ForwardOpaque shadow map, SkyFeature IBL)
4. No shared default textures — each feature creates 1x1 white/black/normal independently
5. Per-feature bind group layouts duplicated across features
6. No profiling instrumentation in the renderer itself (only in samples)
7. Features receive raw RenderView — no clean per-view data snapshot

## Improvement Phases

### Phase 1: Profiling Instrumentation — DONE
SProfiler instrumented in RenderSystem init, subsystems, per-feature init/AddPasses.

### Phase 2: SharedResources — DONE
Centralized fallback textures (shadow map, IBL cubemaps, BRDF LUT, samplers).

### Phase 3: ViewContext — DONE
Features receive ViewContext instead of RenderView in AddPasses.

### Phase 4: Extract LightingSystem — DONE
Moved from ForwardOpaqueFeature to RenderSystem.

### Phase 5: Extract ShadowRenderer — DONE
Moved from ForwardOpaqueFeature to RenderSystem.

### Phase 6: Shared Bind Group Layouts — DONE
SharedBindGroupLayouts with shared scene layout + CreateSceneBindGroup helper.

### Phase 7: InitContext + SkySetupContext — DONE (WaitIdle partial)
InitContext for feature init. SkySetupContext for sky IBL generation.
Init-only features use transferBatch directly. Runtime sky paths use
TransferHelper or WithRuntimeSkySetup. UploadTexture/UploadBuffer helpers removed.
**Remaining:** SharedResources WaitIdle (negligible), SkyFeature runtime WaitIdle
(FlushAndInvalidateBindGroups, SetEnvironmentMapEquirect).

---

### Phase 8: Centralize Frame Orchestration — DONE
Visibility, batching, probes, and shadow state moved from features to RenderSystem.
Step 1: VisibilityResolver, FrustumCuller, DrawBatcher moved to RenderSystem.
Step 2: Skipped — object uniform buffers differ per feature (different object types).
Step 3: ReflectionProbeSystem moved to RenderSystem. ShadowPassesActive moved to ShadowRenderer.
Step 4: BuildRenderGraph is now a clear pipeline — all shared data prepared before features run.
**Result:** Zero [Friend] access in any feature. Features only access shared data via
Renderer properties. Profiler shows clear frame pipeline stages.

---

## Constraints

- **Preserve comments:** When moving or copying code, all existing comments must stay in place.
- **No unnecessary refactors:** Don't restructure code that isn't part of the current phase.
  For example, don't inline descriptor creation into function call parameters, don't reformat
  working code, don't rename variables that aren't being moved.
- **Don't touch binding code:** Don't change any bind group entry code, bind group layout code,
  or their comments. These are carefully matched to shader register layouts.

## Non-Goals (For Now)

These are valuable improvements but deferred to avoid scope creep:

- **3-set pipeline layout** (Scene + Material + Object) — requires shader changes
- **Multi-buffered material bind groups** — requires MaterialSystem changes
- **Bindless textures** — requires RHI extension support
- **Async compute** — requires queue management changes
- **Pipeline disk caching** — requires IPipelineCache integration

## Testing Strategy

Every phase must pass:
1. Full workspace build (0 errors, 0 new warnings)
2. RendererSandbox — full scene with shadows, skinning, sky, debug overlay
3. RendererTerrain — terrain + grass + shadows
4. RendererWater — water + terrain
5. RendererScreenEffects — all post-processing effects
6. RendererParticles — GPU particle simulation
7. RendererMultiView — split-screen rendering
8. RendererSkinned — animated fox model
9. No Vulkan validation errors in any sample
