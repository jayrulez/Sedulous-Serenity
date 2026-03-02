# Sedulous.Render — Feature Roadmap

Phased plan for bringing Sedulous-Serenity's renderer to feature-complete status.
Each phase is validated by a new or updated Render* sample.

**Current state**: Forward+ clustered lighting, PBR + IBL, CSM shadows, volumetric fog,
GPU skinning, particles (CPU/GPU), trails, sprites, decals (box), depth prepass,
Hi-Z occlusion culling, motion vectors, RenderGraph, sky (procedural/env map/solid).
FinalOutputFeature has basic exposure but no proper tonemapping operator.

---

## Phase 1 — Post-Processing Foundation

The PostProcessStack is wired up (priority-sorted, ping-pong buffers) but only
VolumetricFogEffect is registered. This phase fills in the core post-processing
chain that every scene needs.

- [ ] **Tonemapping effect** (priority ~400)
  - ACES filmic as default, Reinhard and Uncharted2 as alternatives
  - Selectable via `RenderWorld.TonemapOperator` enum
  - Move exposure application from FinalOutputFeature blit shader into this effect
  - FinalOutputFeature becomes a pure passthrough blit after this
- [ ] **Auto-exposure** (priority ~390)
  - Compute luminance histogram (compute shader, 256 bins)
  - Adaptive exposure with min/max EV range and speed-up/speed-down rates
  - Manual override mode (fixed EV) retained via `RenderWorld.ExposureMode`
- [ ] **Bloom** (priority ~200)
  - Threshold + progressive downsample (half-res chain, 5-6 mips)
  - Dual-filter Kawase blur per mip (cheaper than Gaussian)
  - Progressive upsample + accumulate
  - `BloomIntensity`, `BloomThreshold` on RenderWorld
- [ ] Update `PostProcessStack` priority range comments if ranges shift
- [ ] Update `FinalOutputFeature` to read from PostProcessOutput only (remove inline exposure)

**Validation**: Update **RenderSandbox** — add UI toggles for tonemapper selection,
bloom intensity/threshold, exposure mode (auto/manual). Visually confirm HDR scene
looks correct with bloom on bright emissive surfaces.

---

## Phase 2 — Anti-Aliasing

Motion vectors are already generated. TAA is the highest-value AA technique for
a forward renderer with temporal stability.

- [ ] **TAA** (priority ~300)
  - Halton jitter on projection matrix (2-frame minimum, 8-16 frame sequence)
  - Velocity-based reprojection from previous frame
  - Neighborhood clamping (3x3 min/max or variance clip)
  - History blend factor (~0.9 static, lower on disocclusion)
  - Requires persistent history buffer (managed by effect, not render graph transient)
  - Jitter must be applied in `RenderView` before features run
- [ ] **FXAA** (priority ~310, alternative to TAA)
  - FXAA 3.11 quality preset
  - Single full-screen pass, no temporal state
  - Selectable via `RenderWorld.AAMode` enum (None, FXAA, TAA)
- [ ] **Sharpening pass** (priority ~320, optional post-TAA)
  - CAS (AMD Contrast Adaptive Sharpening) or simple unsharp mask
  - Counteracts TAA softening

**Validation**: New sample **RenderAntiAliasing** — side-by-side split view
(None / FXAA / TAA) on a scene with thin geometry (fences, wires, foliage edges)
and camera motion to show temporal stability.

---

## Phase 3 — Screen-Space Effects

These effects read from the depth and normal buffers already produced by the
depth prepass and forward pass.

- [ ] **SSAO** (priority ~100)
  - GTAO (Ground Truth Ambient Occlusion) — good quality/perf ratio
  - Half-res compute, bilateral blur, full-res apply
  - Temporal accumulation using motion vectors (optional)
  - `SSAORadius`, `SSAOIntensity`, `SSAOEnabled` on RenderWorld
  - ForwardOpaqueFeature reads AO texture and modulates ambient term
- [ ] **SSR** (priority ~110)
  - Hi-Z ray marching (Hi-Z buffer already built by HiZOcclusionCuller)
  - Roughness-based ray spread (skip SSR for rough surfaces)
  - Temporal reprojection for stability
  - Fallback to IBL cubemap where SSR misses
  - Blend: `SSRIntensity` on RenderWorld
- [ ] **Contact shadows** (priority ~50, or integrated into shadow pass)
  - Screen-space ray march from light direction
  - Short range (5-10 texels) for small-scale shadow detail
  - Applied as multiplier on shadow term in forward shader
  - `ContactShadowsEnabled`, `ContactShadowLength` on RenderWorld

**Validation**: New sample **RenderScreenEffects** — indoor scene (room with
furniture/columns) showing SSAO darkening corners/crevices, SSR on glossy floor,
contact shadows under small objects. Toggle each effect on/off.

---

## Phase 4 — Terrain & Environment

New proxy types and render features. These are the biggest missing pieces
compared to Lunex.

- [ ] **TerrainProxy + TerrainFeature**
  - New `TerrainProxy` in RenderWorld (heightmap texture, splatmap, material layers)
  - `TerrainFeature : IRenderFeature` with dependency on DepthPrepass
  - Clipmap or concentric ring LOD (GPU-driven vertex placement)
  - 4-layer splatmap blending (albedo + normal per layer)
  - Height-based and slope-based blending weights
  - Shadow casting (depth pass integration)
  - Terrain collision mesh export for physics (separate from rendering)
- [ ] **GrassFeature**
  - Instanced grass billboards/meshes placed by density map
  - Distance-based LOD (full mesh → billboard → fade out)
  - Wind animation via vertex shader (time + world position noise)
  - Frustum + distance culling on GPU (compute shader populates indirect draw)
  - Grass density/types configurable per terrain layer
- [ ] **Reflection probes**
  - New `ReflectionProbeProxy` in RenderWorld (position, range, cubemap)
  - Offline bake: render scene from probe position into cubemap (6 faces)
  - Mip chain convolution for roughness (reuse IBL prefilter compute shader)
  - Probe blending: nearest probe(s) weighted by distance
  - ForwardOpaqueFeature samples probe cubemap instead of global IBL when in range
  - Fallback to sky IBL outside all probe volumes
- [ ] **Environment probes** (extend reflection probes)
  - Separate diffuse irradiance probe (SH9 or low-res cubemap)
  - Probe grid for large scenes (interpolate between nearest 8)
  - Runtime re-bake on demand (`RenderWorld.BakeProbe(handle)`)
- [ ] **Water**
  - New `WaterProxy` in RenderWorld (plane position, normal, material params)
  - `WaterFeature : IRenderFeature` after ForwardOpaque
  - Planar reflection (render scene mirrored, half-res)
  - Screen-space refraction (distorted scene color read)
  - Flow map animation (UV distortion over time)
  - Depth-based color absorption (shallow = clear, deep = tinted)
  - Foam at depth discontinuities (shore, objects)
  - Fresnel-based reflection/refraction blend

**Validation**: New sample **RenderTerrain** — outdoor scene with heightmap terrain,
4-layer splatmap (grass/dirt/rock/snow by slope+height), grass billboards waving
in wind, a water plane with reflections, and one reflection probe inside a small
structure. Orbit camera.

---

## Phase 5 — Visual Polish

Post-process effects that add cinematic quality. All are relatively small
(single-pass or two-pass effects).

- [ ] **Depth of Field** (priority ~210)
  - Circle-of-confusion from depth buffer + focus distance/range
  - Separable bokeh blur (near + far field)
  - `DOFEnabled`, `DOFFocusDistance`, `DOFFocusRange`, `DOFBokehSize` on RenderWorld
- [ ] **Motion blur** (priority ~220)
  - Per-pixel velocity from motion vector buffer
  - Variable-length blur along velocity direction
  - Tile-based max velocity for efficiency (TileMax → NeighborMax → blur)
  - `MotionBlurEnabled`, `MotionBlurIntensity` on RenderWorld
- [ ] **Film grain** (priority ~410)
  - Noise overlay modulated by luminance (more grain in shadows)
  - Animated per-frame (blue noise or white noise with temporal offset)
  - `FilmGrainIntensity` on RenderWorld
- [ ] **Color grading** (priority ~420)
  - 3D LUT (32x32x32 or 64x64x64) loaded as texture
  - Applied after tonemapping
  - `ColorGradingLUT` resource ref on RenderWorld
- [ ] **Vignette** (priority ~430)
  - Radial darkening from center
  - `VignetteIntensity`, `VignetteSmoothness` on RenderWorld
- [ ] **Chromatic aberration** (priority ~440)
  - Per-channel UV offset (R/G/B) scaled by distance from center
  - `ChromaticAberrationIntensity` on RenderWorld

**Validation**: New sample **RenderCinematic** — animated camera path through a
scene (dolly + focus pull). DOF shifts focus between near/far objects, motion blur
on camera movement, film grain + color grading LUT for a stylized look. Toggle
each effect.

---

## Phase 6 — Performance & Scalability

Optimizations for rendering many objects efficiently.

- [ ] **GPU instancing**
  - Batch identical mesh+material draws into single instanced draw call
  - Instance data buffer (transform + per-instance params) uploaded per frame
  - Integrate with `DrawBatcher` — detect instancable groups during batching
  - Vertex shader reads instance data from structured buffer
  - Affects forward opaque, depth prepass, shadow passes
- [ ] **LOD system**
  - `MeshProxy` gains LOD level array (submesh index ranges per LOD)
  - Asset pipeline: LOD generation via mesh simplification (meshoptimizer)
  - Distance-based LOD selection in culling pass (screen-space size metric)
  - Crossfade dithering between LOD levels (optional)
  - `LODBias` on RenderWorld for global quality scaling
- [ ] **Curve decals**
  - Spline-projected decals for roads, tire tracks, damage patterns
  - New `CurveDecalProxy` with control points + width + UV mapping
  - Generate mesh strip from spline, project onto depth buffer
  - Shares DecalFeature pass with box decals

**Validation**: Update **RenderScene** — increase object count to 5000+
with LOD (3 levels per mesh), GPU instancing enabled. Show frame time
improvement with/without instancing. Add curve decal along a path.

---

## Phase 7 — Advanced Rendering

Larger architectural additions for specific use cases.

- [ ] **Deferred rendering path** (optional, selectable)
  - G-buffer pass: albedo, normal, metallic/roughness, emissive, depth
  - Deferred light pass: full-screen or tiled per light
  - Transparent objects still use forward pass
  - Selectable via `RenderWorld.RenderPath` (Forward, Deferred)
  - Useful for scenes with many lights (>100 point lights)
- [ ] **Volumetric clouds**
  - Ray-marched cloud layer in atmosphere
  - Weather map (2D texture) for coverage/type/density
  - Light scattering (silver lining, dark edges)
  - Temporal reprojection for performance (quarter-res, 16-frame accumulation)
  - Integrates with SkyFeature (renders between sky and scene)
- [ ] **Voxel GI** (experimental)
  - Scene voxelization (conservative rasterization or compute)
  - 3D texture storing radiance
  - Cone tracing for diffuse + specular indirect
  - Cascaded voxel grids for range
  - Heavy — optional feature, off by default

**Validation**: New sample **RenderDeferred** — scene with 200+ point lights
in a dungeon/warehouse. Compare forward+ vs deferred frame times.
New sample **RenderClouds** — outdoor scene with dynamic cloud layer,
time-of-day cycle affecting cloud lighting.

---

## Existing Samples Reference

| Sample | Features Covered |
|--------|-----------------|
| RenderTriangle | RenderGraph basics |
| RenderPBR | PBR materials |
| RenderGeometry | Procedural meshes, camera |
| RenderStaticMesh | GLTF loading |
| RenderSkinned | Skeletal animation |
| RenderMaterials | PBR parameter grid |
| RenderMaterialsCustom | Custom shaders (toon) |
| RenderLighting | Point lights, shadows, PBR grid |
| RenderShadow | Directional shadows |
| RenderSky | Sky modes, IBL |
| RenderDecals | Box decals |
| RenderSprite | Billboard sprites |
| RenderParticles | GPU particles |
| RenderMultiView | Split-screen |
| RenderUnlit | Unlit materials |
| RenderAsset | Asset caching pipeline |
| RenderScene | Large scene, culling, perf |
| RenderSandbox | Integration demo |
| RenderIntegrated | All features combined |

## New Samples Added by This Plan

| Sample | Phase | Validates |
|--------|-------|-----------|
| RenderSandbox (updated) | 1 | Tonemapping, bloom, exposure |
| RenderAntiAliasing | 2 | TAA, FXAA, sharpening |
| RenderScreenEffects | 3 | SSAO, SSR, contact shadows |
| RenderTerrain | 4 | Terrain, grass, water, probes |
| RenderCinematic | 5 | DOF, motion blur, film grain, color grading |
| RenderScene (updated) | 6 | GPU instancing, LOD, curve decals |
| RenderDeferred | 7 | Deferred path, many lights |
| RenderClouds | 7 | Volumetric clouds |
