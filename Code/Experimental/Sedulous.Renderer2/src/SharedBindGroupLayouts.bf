using System;
using Sedulous.RHI;
using Sedulous.Profiler;

namespace Sedulous.Renderer;

/// Shared bind group layouts and per-frame bind groups owned by RenderSystem.
/// Features reference these instead of creating their own layouts.
/// Bind groups are rebuilt per-frame with current buffer references.
public class SharedBindGroupLayouts
{
	private IDevice mDevice;

	// --- Layouts ---

	/// Object layout: single dynamic-offset UBO for per-object transforms.
	/// Used by depth prepass, forward opaque, shadows.
	/// Binding 0: object uniforms (vertex stage, dynamic offset)
	private IBindGroupLayout mObjectLayout;

	/// Scene layout for the forward pass: all lighting, shadow, IBL, probe bindings.
	/// Matches forward.frag.hlsl register layout.
	private IBindGroupLayout mSceneLayout;

	/// Forward pass bind groups (per frame × per view)
	private IBindGroup[RenderConfig.FrameBufferCount * RenderConfig.MaxViews] mSceneBindGroups;

	/// Depth scene layout: camera uniforms for depth-only passes.
	/// Binding 0: camera/scene uniforms (vertex stage)
	/// Binding 1: object uniforms (vertex stage, dynamic offset)
	private IBindGroupLayout mDepthPassLayout;

	// --- Per-frame bind groups ---

	/// Depth pass bind groups (per frame × per view)
	private IBindGroup[RenderConfig.FrameBufferCount * RenderConfig.MaxViews] mDepthPassBindGroups;

	// --- Per-frame object uniform buffers ---

	/// Shared object uniform buffers (per frame). All features that draw meshes use these.
	private IBuffer[RenderConfig.FrameBufferCount] mObjectUniformBuffers;

	/// Aligned size of one object uniform entry
	public const uint64 ObjectUniformAlignment = 256;
	public const uint64 ObjectUniformSize = 144; // 2 matrices (128) + 2 uint32 (8) + 2 float (8)
	public const uint64 AlignedObjectUniformSize = ((ObjectUniformSize + ObjectUniformAlignment - 1) / ObjectUniformAlignment) * ObjectUniformAlignment;

	// --- Public accessors ---

	public IBindGroupLayout ObjectLayout => mObjectLayout;
	public IBindGroupLayout DepthPassLayout => mDepthPassLayout;
	public IBindGroupLayout SceneLayout => mSceneLayout;

	/// Get the scene bind group for a frame+view combination
	public IBindGroup GetSceneBindGroup(int32 frameIndex, int32 viewIndex = 0)
	{
		return mSceneBindGroups[RenderConfig.BufferSlot(frameIndex, viewIndex)];
	}

	/// Get the depth pass bind group for a frame+view combination
	public IBindGroup GetDepthPassBindGroup(int32 frameIndex, int32 viewIndex = 0)
	{
		return mDepthPassBindGroups[RenderConfig.BufferSlot(frameIndex, viewIndex)];
	}

	/// Get the shared object uniform buffer for a frame
	public IBuffer GetObjectUniformBuffer(int32 frameIndex)
	{
		return mObjectUniformBuffers[frameIndex % RenderConfig.FrameBufferCount];
	}

	public this(IDevice device)
	{
		mDevice = device;
	}

	/// Create all shared layouts and per-frame buffers
	public Result<void> Initialize()
	{
		using (SProfiler.Begin("Renderer.SharedLayouts"))
		{
			Try!(CreateLayouts());
			Try!(CreateObjectUniformBuffers());
		}
		return .Ok;
	}

	/// Rebuild depth pass bind groups for the current frame.
	/// Call each frame after scene uniform buffers are updated.
	public void RebuildDepthPassBindGroups(int32 frameIndex, IBuffer sceneBuffer, int32 viewIndex = 0)
	{
		let bgIndex = RenderConfig.BufferSlot(frameIndex, viewIndex);
		let fi = frameIndex % RenderConfig.FrameBufferCount;

		if (mDepthPassBindGroups[bgIndex] != null)
			mDevice.DestroyBindGroup(ref mDepthPassBindGroups[bgIndex]);

		if (sceneBuffer == null) return;
		let objectBuffer = mObjectUniformBuffers[fi];
		if (objectBuffer == null) return;

		BindGroupEntry[2] entries = .(
			BindGroupEntry.Buffer(sceneBuffer, 0, RenderFrameContext.SceneUniformSize),
			BindGroupEntry.Buffer(objectBuffer, 0, AlignedObjectUniformSize)
		);

		BindGroupDesc desc = .(mDepthPassLayout, entries);
		desc.Label = "Shared DepthPass BindGroup";

		if (mDevice.CreateBindGroup(desc) case .Ok(let bg))
			mDepthPassBindGroups[bgIndex] = bg;
	}

	/// Rebuild the scene bind group for the forward pass.
	/// Uses LightingSystem buffers for lighting, SharedResources fallbacks for shadow/IBL/probes.
	public void RebuildSceneBindGroups(int32 frameIndex, IBuffer sceneBuffer, IBuffer objectBuffer,
		LightingSystem lighting, SharedResources shared, int32 viewIndex = 0)
	{
		let bgIndex = RenderConfig.BufferSlot(frameIndex, viewIndex);
		let fi = frameIndex % RenderConfig.FrameBufferCount;

		if (mSceneBindGroups[bgIndex] != null)
			mDevice.DestroyBindGroup(ref mSceneBindGroups[bgIndex]);

		if (sceneBuffer == null || objectBuffer == null || lighting == null || shared == null)
			return;

		// Gather resources — use real buffers where available, fallbacks where not
		let lightBuffer = lighting.LightBuffer;
		let clusterGrid = lighting.ClusterGrid;

		let clusterConfig = lighting.ClusterGrid.Config;

		BindGroupEntry[15] entries = .(
			BindGroupEntry.Buffer(sceneBuffer, 0, SceneUniforms.Size),                              // b0: Camera
			BindGroupEntry.Buffer(objectBuffer, 0, AlignedObjectUniformSize),                        // b1: Object (dynamic)
			BindGroupEntry.Buffer(lightBuffer.GetUniformBuffer(fi), 0, (uint64)LightingUniforms.Size),  // b3: LightingUniforms
			BindGroupEntry.Buffer(lightBuffer.GetLightDataBuffer(fi), 0, (uint64)(lightBuffer.MaxLights * GPULight.Size)),  // t4: Lights
			BindGroupEntry.Buffer(clusterGrid.GetClusterLightInfoBuffer(fi, viewIndex), 0, (uint64)(clusterConfig.TotalClusters * 8)),  // t5: ClusterLightInfo
			BindGroupEntry.Buffer(clusterGrid.GetLightIndexBuffer(fi, viewIndex), 0, (uint64)(clusterConfig.MaxLightsPerCluster * clusterConfig.TotalClusters * 4)),  // t6: LightIndices
			BindGroupEntry.Buffer(shared.DummyUniformBuffer, 0, 336),                                // b5: ShadowUniforms (fallback, 336 bytes)
			BindGroupEntry.Texture(shared.DummyShadowMapView),                                       // t7: ShadowMap (fallback)
			BindGroupEntry.Sampler(shared.ShadowSampler),                                            // s1: ShadowSampler
			BindGroupEntry.Texture(shared.FallbackCubemapView),                                      // t8: Irradiance (fallback)
			BindGroupEntry.Texture(shared.FallbackCubemapView),                                      // t9: Prefiltered (fallback)
			BindGroupEntry.Texture(shared.BRDFLUTView),                                              // t10: BRDF LUT
			BindGroupEntry.Sampler(shared.LinearClamp),                                              // s2: IBL Sampler
			BindGroupEntry.Buffer(shared.DummyUniformBuffer, 0, 1424),                               // b6: ProbeUniforms (fallback, 1424 bytes)
			BindGroupEntry.Texture(shared.FallbackCubemapArrayView)                                   // t11: ProbeCubemaps (fallback — TextureCubeArray)
		);

		BindGroupDesc desc = .(mSceneLayout, Span<BindGroupEntry>(&entries[0], 15));
		desc.Label = "Shared Scene BindGroup";

		if (mDevice.CreateBindGroup(desc) case .Ok(let bg))
			mSceneBindGroups[bgIndex] = bg;
	}

	private Result<void> CreateLayouts()
	{
		// Object layout: single dynamic UBO
		{
			BindGroupLayoutEntry[1] entries = .(
				.() { Binding = 0, Visibility = .Vertex | .Fragment, Type = .UniformBuffer, HasDynamicOffset = true }
			);

			if (mDevice.CreateBindGroupLayout(BindGroupLayoutDesc()
			{
				Entries = entries,
				Label = "Shared Object Layout"
			}) case .Ok(let layout))
				mObjectLayout = layout;
			else
				return .Err;
		}

		// Depth pass layout: camera UBO + object dynamic UBO
		{
			BindGroupLayoutEntry[2] entries = .(
				.() { Binding = 0, Visibility = .Vertex, Type = .UniformBuffer },
				.() { Binding = 1, Visibility = .Vertex, Type = .UniformBuffer, HasDynamicOffset = true }
			);

			if (mDevice.CreateBindGroupLayout(BindGroupLayoutDesc()
			{
				Entries = entries,
				Label = "Shared DepthPass Layout"
			}) case .Ok(let layout))
				mDepthPassLayout = layout;
			else
				return .Err;
		}

		// Scene layout for forward pass: 15 entries matching forward.frag.hlsl
		// This is the full layout used by ForwardOpaqueFeature.
		// Entries match Serenity's ForwardOpaqueFeature.CreateBindGroupLayouts()
		{
			// Entries must match Serenity's ForwardOpaqueFeature.CreateBindGroupLayouts() exactly
			BindGroupLayoutEntry[15] entries = .(
				.() { Binding = 0, Visibility = .Vertex | .Fragment, Type = .UniformBuffer },                  // b0: Camera
				.() { Binding = 1, Visibility = .Vertex, Type = .UniformBuffer, HasDynamicOffset = true },     // b1: ObjectUniforms
				.() { Binding = 3, Visibility = .Fragment, Type = .UniformBuffer },                             // b3: LightingUniforms
				.() { Binding = 4, Visibility = .Fragment, Type = .StorageBufferReadOnly },                     // t4: Lights
				.() { Binding = 5, Visibility = .Fragment, Type = .StorageBufferReadOnly },                     // t5: ClusterLightInfo
				.() { Binding = 6, Visibility = .Fragment, Type = .StorageBufferReadOnly },                     // t6: LightIndices
				.() { Binding = 5, Visibility = .Fragment, Type = .UniformBuffer },                             // b5: ShadowUniforms
				BindGroupLayoutEntry.SampledTexture(7, .Fragment, .Texture2DArray),                               // t7: ShadowMap (Texture2DArray)
				.() { Binding = 1, Visibility = .Fragment, Type = .ComparisonSampler },                         // s1: ShadowSampler
				BindGroupLayoutEntry.SampledTexture(8, .Fragment, .TextureCube),                                 // t8: Irradiance Map
				BindGroupLayoutEntry.SampledTexture(9, .Fragment, .TextureCube),                                 // t9: Prefiltered Map
				BindGroupLayoutEntry.SampledTexture(10, .Fragment, .Texture2D),                                  // t10: BRDF LUT
				BindGroupLayoutEntry.Sampler(2, .Fragment),                                                      // s2: IBL Sampler
				.() { Binding = 6, Visibility = .Fragment, Type = .UniformBuffer },                             // b6: ProbeUniforms
				BindGroupLayoutEntry.SampledTexture(11, .Fragment, .TextureCubeArray)                            // t11: ProbeCubemaps
			);

			if (mDevice.CreateBindGroupLayout(BindGroupLayoutDesc()
			{
				Entries = Span<BindGroupLayoutEntry>(&entries[0], 15),
				Label = "Shared Scene Layout"
			}) case .Ok(let layout))
				mSceneLayout = layout;
			else
				return .Err;
		}

		return .Ok;
	}

	private Result<void> CreateObjectUniformBuffers()
	{
		let maxObjects = RenderConfig.MaxOpaqueObjectsPerFrame;
		let bufferSize = (uint64)(maxObjects * (int)AlignedObjectUniformSize);

		for (int32 i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			if (mDevice.CreateBuffer(BufferDesc()
			{
				Label = "Shared Object Uniforms",
				Size = bufferSize,
				Usage = .Uniform,
				Memory = .CpuToGpu
			}) case .Ok(let buffer))
				mObjectUniformBuffers[i] = buffer;
			else
				return .Err;
		}

		return .Ok;
	}

	public void Shutdown()
	{
		for (int32 i = 0; i < RenderConfig.FrameBufferCount * RenderConfig.MaxViews; i++)
			if (mDepthPassBindGroups[i] != null) mDevice.DestroyBindGroup(ref mDepthPassBindGroups[i]);

		for (int32 i = 0; i < RenderConfig.FrameBufferCount; i++)
			if (mObjectUniformBuffers[i] != null) mDevice.DestroyBuffer(ref mObjectUniformBuffers[i]);

		for (int32 i = 0; i < RenderConfig.FrameBufferCount * RenderConfig.MaxViews; i++)
			if (mSceneBindGroups[i] != null) mDevice.DestroyBindGroup(ref mSceneBindGroups[i]);

		mDevice.DestroyBindGroupLayout(ref mObjectLayout);
		mDevice.DestroyBindGroupLayout(ref mDepthPassLayout);
		mDevice.DestroyBindGroupLayout(ref mSceneLayout);
	}

	public ~this()
	{
		Shutdown();
	}
}
