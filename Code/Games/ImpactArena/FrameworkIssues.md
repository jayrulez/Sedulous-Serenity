# Framework Issues Encountered

Issues discovered while building ImpactArena against the Sedulous framework.

## 1. Jolt Physics: Mass Calculated from Shape Volume

**Severity:** High (gameplay-breaking)
**Status:** Fixed (PhysicsBodyDescriptor.Mass override added)

Jolt calculates mass from shape volume * density (1000 kg/m^3 default). A sphere with radius 0.5 results in ~524kg, making forces like 40N produce imperceptible acceleration (0.076 m/s^2).

**Fix:** Added `Mass` field to `PhysicsBodyDescriptor`. When > 0, calls `JPH_BodyCreationSettings_SetOverrideMassProperties` with `CalculateInertia` mode so inertia is still derived from shape but mass is user-specified.

**Files:** `Sedulous.Physics/src/Bodies/PhysicsBodyDescriptor.bf`, `Sedulous.Physics.Jolt/src/JoltPhysicsWorld.bf`

## 2. AllowedDOFs Not Applied

**Severity:** Medium
**Status:** Fixed

`PhysicsBodyDescriptor.AllowedDOFs` existed but `JoltPhysicsWorld.CreateBody` never called `JPH_BodyCreationSettings_SetAllowedDOFs`.

**Fix:** Added the call when `AllowedDOFs != .All`.

**File:** `Sedulous.Physics.Jolt/src/JoltPhysicsWorld.bf`

## 3. ParticleFeature Requires ForwardTransparentFeature

**Severity:** High (particles silently don't render)
**Status:** Workaround (register ForwardTransparentFeature even if unused)

ParticleFeature's render pass is added to the render graph but never executed unless ForwardTransparentFeature is also registered. The render graph's resource dependency chain for SceneColor apparently needs the transparent pass to properly connect opaque output to particle input.

NeverCull is set on the particle pass, and the pass IS added to the graph, but execution never occurs without the transparent feature present.

**Potential fix:** ParticleFeature should not silently fail when ForwardTransparentFeature is absent. Either remove the dependency or ensure the render graph chains SceneColor correctly regardless.

## 4. ParticleFeature: Silent Bind Group Failure Without Lighting

**Severity:** Medium (particles silently don't render)
**Status:** Fixed (fallback buffers added)

`CreateCPURenderBindGroup()` and the standalone trail bind group creation both require ALL lighting buffers (from ForwardOpaqueFeature.Lighting) to be non-null. If any are null, returns null and rendering is silently skipped.

**Fix:** Created zeroed fallback buffers (0 lights) in `CreateDefaultResources()`. Used as fallback when real lighting buffers aren't available.

**File:** `Sedulous.Render/src/Features/Particles/ParticleFeature.bf`

## 5. Buffer Destruction While In-Flight

**Severity:** Medium (Vulkan validation error, potential GPU crash on some drivers)
**Status:** Fixed (deferred deletion queue in RenderWorld)

`RenderWorld.DestroyParticleEmitter` and `DestroyTrailEmitter` were immediately deleting CPUParticleEmitter/TrailEmitter objects (and their GPU vertex buffers) while in-flight command buffers still referenced them. Confirmed with debugging that `DestroyImmediate` triggers this even during normal gameplay.

**Fix:** Both methods now queue emitters into `mPendingEmitterDeletions` / `mPendingTrailDeletions` with a countdown of `FrameBufferCount + 1` frames. `ProcessDeferredDeletions()` is called from `RenderSystem.BeginFrame()` and decrements the counter each frame, only deleting once all in-flight frames have completed.

**Files:** `Sedulous.Render/src/World/RenderWorld.bf`, `Sedulous.Render/src/RenderSystem.bf`

**General principle:** Any RenderWorld proxy type that owns GPU buffers (IBuffer/ITexture) must defer deletion until in-flight frames complete. Currently only CPUParticleEmitter and TrailEmitter own GPU vertex buffers directly. Other proxy types (Mesh, SkinnedMesh, Sprite, Light, Camera) reference shared resources managed by ResourceManager (which already has frame-aware `ReleaseMesh(handle, frameNumber)`) or don't own GPU resources at all. Future proxy types that allocate their own GPU buffers should use the same deferred deletion pattern.

## 6. Vertex Attribute Not Consumed (Cosmetic)

**Severity:** Low (validation warning, no functional impact)
**Status:** Open

```
vkCreateGraphicsPipelines(): pCreateInfos[0].pVertexInputState Vertex attribute at location 4 not consumed by vertex shader.
```

The CPU particle vertex layout includes attributes (likely for lit particles) that the shader doesn't consume in unlit mode. Non-fatal but noisy in validation.

**Potential fix:** Use separate vertex layouts for lit vs unlit particle pipelines, or mark unused attributes with `[[maybe_unused]]` equivalent.

## 7. PBR Shader: No Emissive Color Uniform

**Severity:** Low (feature gap)
**Status:** Open

The PBR material defines an `EmissiveMap` texture slot but has no emissive color/intensity uniform. The fragment shader (`Assets/Render/Shaders/forward.frag.hlsl:264`) samples the emissive texture directly:
```hlsl
float3 emissive = EmissiveTexture.Sample(LinearSampler, input.TexCoord).rgb;
```

Without a multiplier uniform, you cannot:
- Tint emissive output without a custom texture per color
- Animate emissive intensity (e.g., pulse/flash effects)
- Scale emissive brightness at runtime

**Suggested fix:** Add `float4 EmissiveColor` (or `float3 EmissiveColor` + `float EmissiveIntensity`) to the MaterialUniforms cbuffer and multiply:
```hlsl
float3 emissive = EmissiveTexture.Sample(LinearSampler, input.TexCoord).rgb * EmissiveColor.rgb * EmissiveIntensity;
```
Register matching parameters in `Materials.CreatePBR()` via the MaterialBuilder. Default to `(0,0,0)` or `(1,1,1)` with intensity 1.0 so existing materials are unaffected.
