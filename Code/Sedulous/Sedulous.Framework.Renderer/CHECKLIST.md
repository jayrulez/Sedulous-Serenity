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
- [ ] Skinned mesh rendering (bone transforms, vertex skinning)
- [x] Sprite rendering (billboards, instancing)
- [x] Particle system
- [ ] Decal rendering
- [x] Skybox rendering
- [x] GLTF model loading
- [ ] Sample: `RendererGeometry` complete (missing: skinned mesh, decals)

## Phase 4: Visibility & Scene
- [ ] RenderWorld and proxy system
- [ ] FrustumCuller
- [ ] Draw sorting
- [ ] LOD selection
- [ ] Instancing support
- [ ] Depth pre-pass
- [ ] Sample: `RendererScene`

## Phase 5: Lighting & Shadows
- [ ] ClusterGrid
- [ ] Light types (directional, point, spot)
- [ ] Cascaded shadow maps
- [ ] Shadow atlas
- [ ] PCF shadow filtering
- [ ] Light culling
- [ ] Sample: `RendererLighting`

## Phase 6: Post-Processing
- [ ] HDR render target
- [ ] Exposure control
- [ ] Bloom
- [ ] Tonemapping
- [ ] TAA
- [ ] FXAA fallback
- [ ] Color grading
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
