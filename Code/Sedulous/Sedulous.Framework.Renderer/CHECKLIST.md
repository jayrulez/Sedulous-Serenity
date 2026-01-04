# Sedulous.Framework.Renderer Implementation Checklist

## Phase 1: Foundation + Render Graph Core
- [x] Create `Sedulous.Renderer` project with dependencies
- [x] RenderGraph core (pass declaration, resource nodes, compile, execute)
- [x] TransientResourcePool (texture/buffer pooling)
- [x] GPUResourceManager basics (mesh/texture upload)
- [x] Simple forward pass (not through render graph yet)
- [x] Basic camera (view/projection, reverse-Z, Vulkan Y-flip)
- [x] Sample: `RendererTriangle`

## Phase 2: Materials & Shaders
- [x] ShaderLibrary (load shaders, reflection)
- [x] Material/MaterialInstance system
- [x] PipelineCache (hash-based lookup)
- [x] Standard PBR shader
- [x] Shader variant system (SKINNED, INSTANCED)
- [x] Sample: `RendererPBR`

## Phase 3: Geometry Types
- [x] Static mesh rendering
- [x] Skinned mesh rendering (bone transforms, vertex skinning)
- [x] Sprite rendering (billboards, instancing)
- [x] Particle system
- [ ] Decal rendering
- [x] Skybox rendering
- [x] GLTF model loading
- [ ] Sample: `RendererGeometry` complete (missing: decals)

## Phase 4: Visibility & Scene
- [x] RenderWorld and proxy system (MeshProxy, LightProxy, CameraProxy)
- [x] FrustumCuller (geometric approach, needs refinement)
- [x] VisibilityResolver with draw sorting
- [x] LOD selection (distance-based)
- [x] Instancing support (instance buffer, DrawIndexedInstanced)
- [ ] Depth pre-pass
- [x] Sample: `RendererScene` - 1200 instanced cubes with camera controls

## Phase 5: Lighting & Shadows
- [x] ClusterGrid (16x9x24 clusters) - CPU implementation
- [x] Light types (directional, point, spot) with attenuation
- [x] LightingSystem wrapper class
- [x] Clustered lighting shader include (clustered_lighting.hlsli)
- [x] PBR shader variant for dynamic lights (pbr_clustered.frag.hlsl)
- [ ] Cascaded shadow maps (4 cascades) - placeholder created
- [ ] Shadow atlas (point/spot tiles) - placeholder created
- [ ] PCF shadow filtering
- [ ] Sample: `RendererLighting` - in progress

## Phase 6: Post-Processing
- [ ] HDR render target (RGBA16F)
- [ ] Exposure control
- [ ] Bloom (downsample + blur + composite)
- [ ] Tonemapping (ACES)
- [ ] TAA (jitter + velocity + history)
- [ ] FXAA fallback
- [ ] Color grading (3D LUT)
- [ ] Sample: `RendererPostFX`

## Phase 7: Polish & Integration
- [ ] Hi-Z occlusion culling
- [ ] GPU profiling markers
- [ ] Debug visualization modes
- [ ] Shader hot-reload
- [ ] Framework.Core integration
- [ ] RenderSceneComponent
- [ ] Documentation
- [ ] Sample: `RendererIntegrated`

## Known Issues / TODO
- FrustumCuller: Geometric plane computation works but culling is currently bypassed; needs refinement
- Decal rendering not yet implemented
