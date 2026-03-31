# Sedulous.RenderGraph Design Document

## Overview

Sedulous.RenderGraph is a frame graph / render graph system built on top of Sedulous.RHI. It automates resource lifetime management, barrier insertion, and pass scheduling — allowing engine code to declare **what** each pass reads and writes without manually tracking resource states or synchronization.

### Goals

- **Automatic barriers** — Resource state transitions are derived from pass read/write declarations. No manual `encoder.Barrier()` calls.
- **Transient resource management** — Resources that only live within a frame are allocated from pools and aliased when lifetimes don't overlap.
- **Pass culling** — Unreferenced passes are automatically removed (dead code elimination for the GPU).
- **Multi-queue scheduling** — Passes can target graphics, compute, or transfer queues with automatic cross-queue synchronization via timeline fences.
- **Debug tooling** — Graph visualization, pass timing, resource lifetime diagrams.

### Project Structure

```
BeefGFX_Workspace/
├── Sedulous.RenderGraph/          # Render graph library
│   └── src/
│       ├── RenderGraph.bf        # Main graph builder & executor
│       ├── RenderGraphPass.bf    # Pass declaration & callbacks
│       ├── RenderGraphResource.bf # Resource handle & descriptors
│       ├── RenderGraphBuilder.bf # Per-pass resource access API
│       ├── ResourceRegistry.bf   # Transient resource pool & aliasing
│       ├── BarrierSolver.bf      # Automatic barrier insertion
│       ├── PassScheduler.bf      # Topological sort, culling, multi-queue assignment
│       ├── GraphDebug.bf         # Debug visualization & profiling
│       └── Types.bf              # Shared types, enums, handles
```

### Dependencies

- `Sedulous.RHI` — interfaces, descriptors, enums

---

## Core Concepts

### Resource Handles

Resources in the render graph are referenced by opaque handles, not raw `ITexture`/`IBuffer` pointers. This enables aliasing, versioning, and deferred allocation.

```beef
/// Opaque handle to a render graph resource. Lightweight value type.
struct RGResource
{
    uint32 Index;    // Resource table index
    uint32 Version;  // Incremented on each write (enables SSA-style tracking)
}

struct RGTexture : RGResource { }
struct RGBuffer  : RGResource { }
```

### Resource Descriptors

Transient resources are described by their usage, not by concrete GPU objects:

```beef
struct RGTextureDesc
{
    TextureFormat Format;
    uint32 Width;
    uint32 Height;
    uint32 DepthOrArrayLayers = 1;
    uint32 MipLevelCount = 1;
    uint32 SampleCount = 1;
    StringView Name;
}

struct RGBufferDesc
{
    uint64 Size;
    BufferUsage Usage;
    StringView Name;
}
```

### Imported vs Transient Resources

- **Imported** — External resources (swap chain backbuffer, persistent scene buffers) brought into the graph. The graph does not own them.
- **Transient** — Resources created and destroyed within a single frame. The graph manages their lifetime and can alias memory across non-overlapping usages.

### Pass Declaration

Each pass declares its resource accesses and provides an execute callback:

```beef
graph.AddPass("GBuffer", .Graphics, scope (builder) =>
{
    let albedo = builder.CreateTexture(albedoDesc);
    let normal = builder.CreateTexture(normalDesc);
    let depth  = builder.CreateTexture(depthDesc);

    builder.WriteRenderTarget(albedo, 0);
    builder.WriteRenderTarget(normal, 1);
    builder.WriteDepthStencil(depth);

    builder.SetExecute(new (encoder, registry) =>
    {
        let rp = encoder.BeginRenderPass(registry.GetRenderPassDesc("GBuffer"));
        // ... bind pipeline, draw geometry ...
        rp.End();
    });
});

graph.AddPass("Lighting", .Graphics, scope (builder) =>
{
    builder.ReadTexture(albedo, .Fragment);  // sampled in fragment shader
    builder.ReadTexture(normal, .Fragment);
    builder.ReadTexture(depth, .Fragment);

    let hdr = builder.CreateTexture(hdrDesc);
    builder.WriteRenderTarget(hdr, 0);

    builder.SetExecute(new (encoder, registry) =>
    {
        // ... fullscreen lighting pass ...
    });
});
```

---

## Architecture

### RenderGraphBuilder (per-pass API)

Provided to each pass's setup callback. Declares resource accesses and produces dependency edges.

```beef
class RenderGraphBuilder
{
    // Create transient resources
    RGTexture CreateTexture(RGTextureDesc desc);
    RGBuffer  CreateBuffer(RGBufferDesc desc);

    // Read access (produces dependency edge from writer → this pass)
    void ReadTexture(RGTexture tex, ShaderStage stages);
    void ReadBuffer(RGBuffer buf, ShaderStage stages);
    void ReadDepthStencil(RGTexture tex);  // depth read-only

    // Write access (produces new version of resource)
    void WriteRenderTarget(RGTexture tex, uint32 slot);
    void WriteDepthStencil(RGTexture tex);
    void WriteStorage(RGTexture tex, ShaderStage stages);  // UAV / storage image
    void WriteStorage(RGBuffer buf, ShaderStage stages);   // UAV / storage buffer

    // Copy operations
    void ReadCopySrc(RGTexture tex);
    void ReadCopySrc(RGBuffer buf);
    void WriteCopyDst(RGTexture tex);
    void WriteCopyDst(RGBuffer buf);

    // Side effects — prevents culling even if no output is consumed
    void HasSideEffects();

    // Execute callback
    void SetExecute(delegate void(ICommandEncoder, ResourceRegistry) callback);
}
```

### ResourceRegistry (runtime resource access)

Available during pass execution. Maps graph handles to concrete GPU resources.

```beef
class ResourceRegistry
{
    ITexture     GetTexture(RGTexture handle);
    ITextureView GetTextureView(RGTexture handle);
    IBuffer      GetBuffer(RGBuffer handle);

    // Convenience: builds RenderPassDesc from pass's declared render targets
    RenderPassDesc GetRenderPassDesc(StringView passName);
}
```

### BarrierSolver

Walks the scheduled pass list and inserts barriers between passes based on declared access patterns.

**Algorithm:**
1. For each resource, track the "last write" pass and "last known state."
2. Before each pass, for each resource it accesses:
   - Determine the required `ResourceState` from the access type.
   - If the required state differs from the last known state, insert a barrier.
   - If the resource was last written on a different queue, insert a cross-queue fence wait.
3. Batch all barriers for a pass into a single `encoder.Barrier(BarrierGroup)` call before the pass executes.

**Access → ResourceState mapping:**
| Access Type | ResourceState |
|---|---|
| ReadTexture (sampled) | ShaderRead |
| ReadBuffer (uniform) | UniformBuffer |
| ReadBuffer (storage) | ShaderRead |
| WriteRenderTarget | RenderTarget |
| WriteDepthStencil | DepthStencilWrite |
| ReadDepthStencil | DepthStencilRead |
| WriteStorage | ShaderWrite |
| ReadCopySrc | CopySrc |
| WriteCopyDst | CopyDst |
| Present | Present |

### PassScheduler

**Responsibilities:**
1. **Topological sort** — Order passes based on data dependencies (read-after-write edges).
2. **Pass culling** — Walk backwards from output resources (swap chain, exported buffers). Remove any pass whose outputs are not consumed by a retained pass.
3. **Multi-queue assignment** — Passes marked as `.Compute` or `.Transfer` are assigned to async queues when available. Insert timeline fence signal/wait pairs at queue boundaries.
4. **Transient resource lifetime** — Compute first-use and last-use pass indices for each transient resource. Resources with non-overlapping lifetimes can share the same GPU memory.

### RenderGraph (main orchestrator)

```beef
class RenderGraph
{
    // Setup phase
    RGTexture ImportTexture(ITexture texture, ITextureView view, ResourceState initialState);
    RGBuffer  ImportBuffer(IBuffer buffer, ResourceState initialState);
    void AddPass(StringView name, QueueType queue, delegate void(RenderGraphBuilder) setup);

    // Compilation (called once per frame after all passes declared)
    void Compile();   // → cull, schedule, allocate transients, solve barriers

    // Execution (records and submits command buffers)
    void Execute(IDevice device);

    // Cleanup
    void Reset();     // Clears all passes & resources for next frame
}
```

---

## Transient Resource Aliasing

Transient textures/buffers that don't overlap in time can share the same GPU memory allocation. This is critical for reducing VRAM usage in complex frame graphs.

**Strategy:**
1. After scheduling, compute `[firstUse, lastUse]` intervals for each transient resource.
2. Sort resources by size (largest first).
3. Greedily assign resources to a pool of GPU allocations, reusing an allocation if its previous occupant's `lastUse < currentResource.firstUse`.
4. When aliasing textures, clear/discard at first use (LoadOp.DontCare or Clear).

**Pool management:**
- Maintain a `List<PooledTexture>` and `List<PooledBuffer>` keyed by descriptor (format, size, usage flags).
- Across frames, grow pools as needed but never shrink. After several frames of lower usage, trim excess.

---

## Multi-Queue Scheduling

Passes can target different queue types:

```beef
graph.AddPass("AsyncCompute_SSAO", .Compute, scope (builder) =>
{
    builder.ReadTexture(depth, .Compute);
    builder.ReadTexture(normals, .Compute);
    let ssao = builder.CreateTexture(ssaoDesc);
    builder.WriteStorage(ssao, .Compute);
    // ...
});
```

**Cross-queue synchronization:**
- When a resource written on queue A is read on queue B, the scheduler inserts:
  1. A `fence.Signal(value)` after queue A's command buffer.
  2. A `fence.Wait(value)` before queue B's command buffer submission.
- Timeline fences allow multiple in-flight frames without additional fence objects.

**Command buffer organization:**
- One command buffer per queue per frame (or per queue-segment if interleaving requires splits).
- Each queue's passes are recorded into a single encoder, with barriers between passes.

---

## Debug & Profiling

### Graph Visualization
- Export pass dependency graph as DOT format for Graphviz rendering.
- Show resource lifetimes, aliasing assignments, and barrier locations.

### GPU Timing
- Optionally insert timestamp queries at pass begin/end.
- Aggregate per-pass GPU time and report via callback or log.

### Validation
- Detect read-without-write (uninitialized resource access).
- Detect write-after-write without intermediate read (redundant pass).
- Detect cycles in the dependency graph.
- Warn on passes that are culled.

---

## Phased Implementation Plan

### Phase 1: Core Graph Framework

- [x] Create `Sedulous.RenderGraph` Beef project with dependency on `Sedulous.RHI`
- [x] Implement `RGResource`, `RGTexture`, `RGBuffer` handle types
- [x] Implement `RGTextureDesc`, `RGBufferDesc` descriptor types
- [x] Implement `RenderGraphBuilder` — resource creation, read/write declarations, execute callback
- [x] Implement `RenderGraph.AddPass()` — stores pass definitions
- [x] Implement `RenderGraph.ImportTexture()` / `ImportBuffer()` — external resources
- [x] Unit test: declare passes with dependencies, verify pass list is built correctly

### Phase 2: Scheduling & Culling

- [x] Implement topological sort based on read/write dependency edges
- [x] Implement pass culling — reverse walk from output/side-effect passes
- [x] Handle imported resources as graph roots (never culled)
- [x] Detect and report dependency cycles
- [x] Unit test: verify culling removes unused passes, sort order is correct

### Phase 3: Barrier Solver

- [x] Implement access-to-ResourceState mapping table
- [x] Implement per-resource state tracking across scheduled passes
- [x] Generate `BarrierGroup` between passes (batch buffer + texture + memory barriers)
- [x] Handle first-use transitions from `Undefined` state
- [x] Handle imported resource initial/final state transitions
- [x] Unit test: verify correct barriers for various access patterns

### Phase 4: Transient Resource Allocation

- [x] Implement `ResourceRegistry` — maps RGResource handles to concrete GPU objects
- [x] Implement transient texture/buffer pool with descriptor-based matching
- [x] Compute resource lifetime intervals `[firstUse, lastUse]`
- [x] Implement greedy aliasing assignment (largest-first bin packing)
- [x] Pool growth/reuse across frames
- [x] Unit test: verify aliasing correctness, no overlapping lifetimes share memory

### Phase 5: Execution

- [x] Implement `RenderGraph.Compile()` — orchestrates scheduling, culling, allocation, barrier solving
- [x] Implement `RenderGraph.Execute()` — creates command pool/encoder, records barriers + pass callbacks, finishes + submits
- [x] Implement `RenderGraph.Reset()` — clears per-frame state, returns transient resources to pool
- [x] Implement `ResourceRegistry.GetRenderPassDesc()` — builds RenderPassDesc from declared render targets + load/store ops
- [x] Integration test: simple GBuffer → Lighting → Tonemap → Present pipeline

### Phase 6: Multi-Queue Support

- [x] Extend `PassScheduler` with queue type awareness
- [x] Implement per-queue command buffer recording
- [x] Insert timeline fence signal/wait at queue boundaries
- [ ] Handle queue family ownership transfers (Vulkan)
- [x] Integration test: async compute pass overlapping with graphics

### Phase 7: Debug & Profiling

- [x] Implement DOT graph export for visualization
- [x] Implement optional timestamp query insertion per pass
- [x] Implement GPU timing aggregation and reporting
- [x] Implement validation warnings (uninitialized reads, redundant writes, culled passes)
- [x] Resource lifetime visualization output

### Phase 8: Advanced Features

- [ ] Transient resource memory aliasing (sub-allocation from shared heaps)
- [x] Conditional passes (skip based on runtime flag without recompilation)
- [ ] Pass merging — combine compatible adjacent render passes into a single pass (subpass optimization on tiled GPUs)
- [x] Automatic mipmap generation pass insertion
- [x] Read-write (UAV) access within a pass (storage read + write on same resource)

---

## Open Questions

1. **Thread safety** — Should pass setup be thread-safe (parallel pass declaration)? Initial design assumes single-threaded setup, multi-threaded execution via separate encoders per queue.

2. **Pipeline & bind group management** — Should the render graph manage pipeline/bind group creation, or leave that to the caller? Initial design: caller manages pipelines, graph manages resources and barriers.

3. **Render pass merging** — Vulkan subpasses and tile-based GPU optimization are deferred to Phase 8. The initial implementation uses one render pass per graph pass.

4. **Frame overlap** — Multiple frames in flight require per-frame graph instances or careful pool management. Defer to Phase 8.
