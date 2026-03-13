# Sedulous.Render — Architecture & Quality Assessment

## Overall Verdict

**Strong, well-structured renderer with clear engineering discipline.** The feature-based modular architecture, handle-based proxy system, and render graph integration are solid foundations. The codebase is production-quality for its development stage, with a few structural debts worth addressing.

---

## Architecture (A-)

### Strengths

**1. Feature-based composability** — The `IRenderFeature` interface with dependency-declared topological sorting (Kahn's algorithm) is the right pattern. 15 features compose cleanly without direct references to each other. Adding a new feature is isolated work: implement the interface, declare dependencies, register it. Terrain, water, grass, curve decals, and 15 post-process effects were all added without modifying existing features.

**2. Data/logic/execution separation** — `RenderWorld` owns proxy data, features own rendering logic, `RenderGraph` owns pass scheduling and barriers. No god-object anti-pattern.

**3. Handle-based proxy pools** — `ProxyPool<T>` with index+generation validation eliminates dangling pointer bugs. Typed handles (`MeshProxyHandle`, `LightProxyHandle`, etc.) prevent accidental cross-pool access at compile time.

**4. Render graph integration** — Automatic barrier insertion, transient resource pooling, and named resource sharing (`"SceneColor"`, `"SceneDepth"`, `"SceneNormalRoughness"`) keep feature coupling loose. Features communicate through the graph, not through each other.

**5. Post-process stack** — Priority-based chaining with ping-pong buffers. 15 effects registered without any knowing about each other. Priority range convention (0-99 pre-light, 100-199 lighting, 200-299 color, 300-399 AA, 400-499 final) is sensible and well-documented.

**6. Multi-view as first-class** — Split-screen support baked into `RenderFrameContext` from day one. Per-view scene uniforms, bind groups, and viewports indexed consistently via `[frameIndex * MaxViews + viewIndex]`.

**7. Robust resource lifecycle** — Deferred deletion with `FrameBufferCount + 1` frame delay prevents use-after-free on in-flight command buffers. Init-time `TransferBatch` batches GPU uploads (e.g., Sponza 69 textures → single sync).

### Weaknesses

**1. Scattered bind group layout creation** — Every feature creates its own layouts. The common pattern (b0=SceneUniforms, b1=ObjectUniforms) appears in 10+ features. A centralized layout factory would reduce ~200 lines of duplicated setup code.

**2. Manual multi-buffer index arithmetic** — `[frameIndex * MaxViews + viewIndex]` is copy-pasted across 13+ features. Should be encapsulated in a `FrameContext.GetBufferIndex(viewIndex)` method.

**3. String-based feature dependencies** — `GetDependencies()` returns `List<StringView>`. A typo in a dependency name silently fails at runtime. Enum-based or typed constants would catch errors at compile time.

**4. No optional dependency fallback** — If a feature fails to initialize, dependent features don't gracefully degrade. Some features guard with null checks on graph resources, others assume they exist.

**5. Duplicate uniform upload logic** — ObjectUniforms created/uploaded independently in DepthPrepassFeature, ForwardOpaqueFeature, ShadowRenderer. Instancing optimization mitigates runtime cost, but structural redundancy adds maintenance burden.

---

## Code Quality (A-)

### Strengths

- **Consistent naming**: `m` prefix for members, PascalCase for types/methods, clear file-per-type organization
- **Defensive coding**: Null checks at feature boundaries, `Result<void>` returns from Initialize, deferred deletion
- **Profiler instrumentation**: `SProfiler.Begin/End` markers throughout for frame timing breakdown
- **Documented performance**: `RenderPerformance.md` quantifies bottlenecks with concrete scaling paths
- **Value-type discipline**: Structs for data, allocation-free iteration patterns, CRepr for GPU alignment

### Debts

- **PrevWorldMatrix dead weight** — Present in DrawCommand, ObjectUniforms, proxies, and shaders, but only MotionVectorFeature needs previous transforms, and it maintains its own dictionary. See [PrevWorldMatrix analysis](#prevworldmatrix-removal-analysis) below.
- **Particle backend split** — Shape/spawn config lives on `CPUParticleEmitter`, not on the proxy. Config calls like `emitter.CPUEmitter?.Shape` fail if null.

---

## Shader Quality (A)

102 shaders across 6 categories, well-structured:

- **Consistent conventions**: `#pragma pack_matrix(row_major)`, `mul(vector, Matrix)` throughout
- **Good code sharing**: 7 `.hlsli` includes for uniforms, lighting, GBuffer utils, probes — no inline cbuffer definitions
- **Correct PBR**: Cook-Torrance with GGX, Schlick Fresnel, Disney roughness remapping
- **Preprocessor variants**: `SKINNED`, `INSTANCED`, `NORMAL_MAP`, `RECEIVE_SHADOWS`, `ALPHA_TEST` — clean variant compilation
- **Cofactor normal matrix on GPU**: Removed NormalMatrix from CPU upload, computed in vertex shader — good tradeoff

---

## Performance Architecture (B+)

### Current Scaling

| Objects | FPS | CPU Bottleneck |
|---------|-----|----------------|
| 32k | 45 | Batcher.Build (39%), Visibility (21%) |
| 72k | ~20 | Batcher dominates |
| 200k | cap | Instance buffer limit (configurable) |

GPU utilization is only ~4% — the renderer is thoroughly CPU-bound at scale.

### Missing for 100k+

1. **No spatial acceleration** — Frustum culling is O(n) linear scan. Octree/BVH would drop ~3.17ms → ~0.5ms at 32k.
2. **No batcher caching** — Static scenes rebuild batches every frame. Incremental batching would eliminate the 5.98ms sort.
3. **No multi-threading** — Culling and batching are single-threaded. Both are embarrassingly parallel.
4. **No GPU-driven rendering** — Indirect draws with GPU culling would unlock 1M+ objects. (Deferred to future.)

The architecture doesn't block any of these improvements — the feature system and proxy pools are structured to support them.

---

## Modularity (A)

91 source files, well-organized:

```
src/
├── RenderSystem, RenderWorld, RenderConfig, RenderFrameContext    (core orchestration)
├── Features/           14 features, each self-contained
│   ├── Overlay/        Debug geometry rendering
│   └── Particles/      CPU+GPU particle subsystem (13 files)
├── PostProcess/        IPostProcessEffect + 15 effects in Effects/
├── World/Proxies/      13 proxy types + ProxyPool<T> + ProxyHandle
├── Visibility/         FrustumCuller, HiZOcclusionCuller, DrawBatcher
├── Lighting/           ClusterGrid, LightBuffer
│   └── Shadows/        CascadedShadowMaps, ShadowAtlas, ShadowRenderer
├── Resources/          GPUMesh, GPUResourceManager, TextureData
└── Probes/             ReflectionProbeSystem
```

Each subsystem has clear ownership boundaries. Features don't reference each other directly.

---

## PrevWorldMatrix Removal Analysis

### Where it lives

| Location | Field | Size Impact |
|----------|-------|-------------|
| `DrawCommand` struct | `Matrix PrevWorldMatrix` | 64 bytes per draw |
| `SkinnedDrawCommand` struct | `Matrix PrevWorldMatrix` | 64 bytes per draw |
| `MeshProxy` struct | `Matrix PrevWorldMatrix` | 64 bytes per proxy |
| `SkinnedMeshProxy` struct | `Matrix PrevWorldMatrix` | 64 bytes per proxy |
| `ObjectUniforms` (ForwardOpaque) | `Matrix PrevWorldMatrix` | 64 bytes per upload |
| `ObjectUniforms` (DepthPrepass) | `Matrix PrevWorldMatrix` | 64 bytes per upload |
| `MotionObjectUniforms` | `Matrix PrevWorldMatrix` | 64 bytes per upload |
| `object_uniforms.hlsli` | `float4x4 PrevWorldMatrix` | cbuffer slot |
| `BoneTransforms` struct | `Matrix[256] PrevBoneMatrices` | 16 KB per skinned mesh |

### Where it's SET (written)

- **Proxies**: `MeshProxy.SetTransform()` and `SkinnedMeshProxy.SetTransform()` copy `WorldMatrix → PrevWorldMatrix` before overwriting.
- **DrawBatcher**: Copies `proxy.PrevWorldMatrix → DrawCommand.PrevWorldMatrix` when building commands.
- **Features**: ForwardOpaqueFeature, DepthPrepassFeature, ForwardTransparentFeature copy from DrawCommand into ObjectUniforms. Terrain/Water/Grass set it to `Identity`.

### Where it's READ (consumed)

- **motion.vert.hlsl line 73**: `float4 prevWorldPos = mul(float4(prevLocalPos, 1.0), PrevWorldMatrix);` — the **only shader** that reads it.
- **MotionVectorFeature**: Maintains its own `Dictionary<MeshProxyHandle, Matrix> mPrevTransforms`. Reads previous transforms from this dictionary (line 279), NOT from DrawCommand or proxy. Stores current transform into dictionary each frame (line 290).

### Verdict: SAFE TO REMOVE

PrevWorldMatrix in DrawCommand/ObjectUniforms is **dead weight**:

1. **No shader reads it** except motion.vert.hlsl, which is only used by MotionVectorFeature.
2. **MotionVectorFeature bypasses it entirely** — uses its own dictionary for previous transforms.
3. **Forward/depth/all other shaders** include `object_uniforms.hlsli` but never access the field.
4. Zero functional impact from removal.

### Recommended Removal (Option B — DrawCommand + ObjectUniforms cbuffer)

Remove PrevWorldMatrix from:
- `DrawCommand` and `SkinnedDrawCommand` structs
- `ObjectUniforms` in ForwardOpaqueFeature and DepthPrepassFeature
- `object_uniforms.hlsli` cbuffer definition
- All assignment sites in DrawBatcher and feature upload code

Keep PrevWorldMatrix in:
- `MotionObjectUniforms` (MotionVectorFeature's own struct) — it still needs this
- `motion.vert.hlsl` — still reads from MotionVectorFeature's cbuffer
- Proxies (for now) — MotionVectorFeature's dictionary makes them redundant too, but proxy cleanup can be a follow-up

**Impact**: DrawCommand 160 → 96 bytes (40% reduction). ObjectUniforms 144 → 80 bytes (44% reduction). At 72k draws: ~4.6 MB saved in command lists, ~3.4 MB saved per frame in uniform data.

---

## Phased Improvement Plan

### Phase 1: Remove PrevWorldMatrix Dead Weight

**Goal**: Reduce DrawCommand and ObjectUniforms size by ~40%, improving cache efficiency for batching and culling.

**Scope**:
- Remove `PrevWorldMatrix` from `DrawCommand`, `SkinnedDrawCommand` structs
- Remove `PrevWorldMatrix` from `ObjectUniforms` in ForwardOpaqueFeature, DepthPrepassFeature
- Remove `PrevWorldMatrix` from `object_uniforms.hlsli` cbuffer
- Remove all assignment sites in DrawBatcher, ForwardOpaqueFeature, DepthPrepassFeature, ForwardTransparentFeature
- Update aligned size constants if any depend on struct size
- Leave `MotionObjectUniforms` and `motion.vert.hlsl` unchanged (MotionVectorFeature manages its own prev transforms)
- Leave proxy fields as optional follow-up

**Estimated changes**: ~40 lines across ~8 files.

**Validation**: Run all Render samples. Verify motion blur and TAA still work correctly (they use MotionVectorFeature's independent dictionary path).

---

### Phase 2: Centralize Bind Group Layout Creation

**Goal**: Eliminate ~200 lines of duplicated bind group layout setup across 10+ features.

**Scope**:
- Create a `BindGroupLayoutFactory` or extend `RenderSystem` with helper methods for common layouts:
  - `CreateSceneBindGroupLayout()` — b0 SceneUniforms (used by nearly every feature)
  - `CreateObjectBindGroupLayout()` — b0 SceneUniforms + b1 ObjectUniforms (used by ForwardOpaque, DepthPrepass, Shadows, MotionVectors, etc.)
  - `CreateLightingBindGroupLayout()` — full scene layout with lighting, shadows, IBL, probes
- Cache layouts on `RenderSystem` (they're immutable once created)
- Refactor features to call factory methods instead of inline layout creation
- Extract `GetBufferIndex(frameIndex, viewIndex)` helper into `RenderFrameContext`

**Estimated changes**: New factory class (~100 lines), refactor ~10 features (remove ~200 lines, add ~50 lines of factory calls). Net reduction ~150 lines.

**Validation**: All Render samples must produce identical output. Bind group validation layers should report no errors.

---

### Phase 3: Spatial Acceleration (BVH/Octree)

**Goal**: Reduce frustum culling from O(n) linear scan to O(log n) spatial query. Target: 3.17ms → <0.5ms at 32k objects.

**Scope**:
- Implement a spatial acceleration structure in `Visibility/`:
  - **Option A: Loose Octree** — simpler, good for mixed static/dynamic scenes, O(log n) query
  - **Option B: Two-level BVH** — static BVH rebuilt on change + dynamic objects in flat list, better cache coherence
  - Recommended: **Loose Octree** for simplicity, with dynamic object support built-in
- Integrate into `VisibilityResolver`:
  - `Insert(handle, AABB)` on proxy creation
  - `Update(handle, AABB)` on proxy transform change (only if AABB crosses cell boundary)
  - `Remove(handle)` on proxy destruction
  - `QueryFrustum(planes) → List<handle>` replaces linear scan
- `RenderWorld` triggers spatial structure updates when proxies move (dirty flags already exist)
- `FrustumCuller` queries spatial structure instead of iterating all proxies
- Keep linear fallback for small scenes (<1000 objects) where overhead isn't worth it

**Key design decisions**:
- Octree cell size tuning: Start with world bounds auto-detected from proxy AABBs, max depth 8
- Dynamic objects: Re-insert on transform change; loose bounds reduce re-insert frequency
- Memory: Node pool with free list (no per-node allocations)

**Estimated changes**: New `SpatialIndex` class (~400-500 lines), refactor `VisibilityResolver` (~100 lines), wire into `RenderWorld` proxy create/update/destroy (~50 lines).

**Validation**: Compare visible object lists between linear and spatial paths (must be identical). Benchmark at 32k and 100k objects. Verify no popping or missing objects.

---

### Phase 4: Batcher Caching for Static Scenes

**Goal**: Eliminate per-frame batch rebuilding for static objects. Target: 5.98ms → <0.5ms for scenes where most objects don't move.

**Scope**:
- Add a **static/dynamic split** in DrawBatcher:
  - Proxies flagged as `IsStatic` (set at creation, or auto-detected if transform hasn't changed for N frames)
  - Static batch cache: Pre-sorted DrawBatch/InstanceGroup arrays, rebuilt only when static objects are added/removed/material-changed
  - Dynamic batch: Rebuilt every frame (only moving objects)
  - Final merge: Concatenate static + dynamic batches (static batches already sorted, dynamic batches sorted independently, then merged)
- Add dirty tracking to `RenderWorld`:
  - `StaticBatchDirty` flag set when static proxy added/removed/material changed
  - Static batches rebuilt only when dirty
  - Dynamic objects always re-batched
- Invalidation triggers:
  - Proxy creation/destruction
  - Material change on proxy
  - Transform change on static proxy (promotes to dynamic, or rebuilds static cache)

**Key design decisions**:
- Static detection: Explicit `IsStatic` flag on proxy (set by engine scene module based on entity flags). Default: dynamic.
- Cache granularity: One cached batch list per RenderWorld. Rebuild is all-or-nothing for static objects (simpler than incremental patching).
- Instance buffer: Static instances written once, appended before dynamic instances each frame.

**Estimated changes**: Extend `DrawBatcher` (~200 lines), add `IsStatic` to proxy structs (~10 lines), wire dirty tracking in `RenderWorld` (~50 lines), update features to use merged batches (~30 lines).

**Validation**: Toggle caching on/off, verify identical rendering. Benchmark improvement at 32k+ objects. Stress test with objects transitioning static↔dynamic.

---

### Phase 5: Multi-Threaded Culling & Batching

**Goal**: Parallelize the two largest CPU bottlenecks. Target: 2-4x throughput improvement, enabling 100k+ objects at interactive frame rates.

**Scope**:
- **Parallel frustum culling**:
  - Split proxy pool into N chunks (N = worker thread count)
  - Each thread culls its chunk against frustum planes → thread-local visible list
  - Main thread merges visible lists (fast concatenation)
  - Spatial structure query (Phase 3) can also be parallelized per-octree-node
- **Parallel batch building**:
  - After culling, split visible list into N chunks
  - Each thread builds local DrawCommand arrays + local material grouping
  - Main thread merges sorted chunks (k-way merge, preserving sort order)
  - Instance grouping runs after merge (single pass over sorted commands)
- **Threading infrastructure**:
  - Use existing job system if available, or lightweight thread pool with work-stealing
  - Per-thread scratch allocators (avoid contention on global allocator)
  - Fence/barrier between culling phase and batching phase

**Key design decisions**:
- Thread count: `min(CPU cores - 1, 8)` worker threads (leave one core for main thread + GPU driver)
- Chunk size: `max(objectCount / threadCount, 1024)` (avoid overhead for small scenes)
- Memory: Per-thread `List<DrawCommand>` pre-allocated to `maxObjects / threadCount` — reused across frames
- Synchronization: Single barrier between cull and batch phases. No locks during parallel work.

**Dependencies**: Phase 3 (spatial acceleration) should land first — parallel spatial queries are more efficient than parallel linear scans. Phase 4 (batcher caching) reduces the dynamic object count that needs parallel batching.

**Estimated changes**: New `ParallelVisibility` and `ParallelBatcher` classes (~500 lines), thread pool integration (~200 lines), refactor `VisibilityResolver` to dispatch parallel work (~100 lines).

**Validation**: Deterministic output regardless of thread count (sorted merge must be stable). Stress test with varying object counts and thread counts. Profile to verify scaling (should see near-linear improvement up to 4 threads, diminishing returns after).

---

## Phase Summary

| Phase | Target | Key Metric | Effort | Risk |
|-------|--------|-----------|--------|------|
| 1. Remove PrevWorldMatrix | Reduce struct sizes 40% | DrawCommand 160→96 bytes | Trivial (~40 lines) | None — verified dead code |
| 2. Centralize Bind Layouts | Reduce duplication | ~150 fewer lines, single source of truth | Small (~1 day) | Low — mechanical refactor |
| 3. Spatial Acceleration | O(n)→O(log n) culling | 3.17ms → <0.5ms at 32k | Medium (~3 days) | Low — additive, keeps linear fallback |
| 4. Batcher Caching | Skip static re-batching | 5.98ms → <0.5ms for static scenes | Medium (~2 days) | Low — toggle-able, verifiable |
| 5. Multi-Threaded Cull/Batch | Parallel CPU work | 2-4x throughput | Medium-Large (~5 days) | Medium — threading correctness |

Phases 1-2 are cleanup/quality. Phases 3-5 are performance. Each phase is independently valuable and can ship separately. Phases 3 and 4 benefit Phase 5 (less work to parallelize when spatial queries are fast and static objects are cached).
