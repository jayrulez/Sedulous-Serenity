namespace Sedulous.Render;

using System;
using Sedulous.RHI;
using Sedulous.Profiler;

/// Shared bind group layouts and scene bind group creation.
/// The 15-entry scene layout is used by Forward, Terrain, Grass, Water, and Transparent features.
/// Each feature has its own object uniform buffer, so bind groups are created per-feature
/// via CreateSceneBindGroup(), but the layout is shared.
public class SharedBindGroupLayouts
{
	private IDevice mDevice;
	private RenderSystem mRenderer;

	/// The shared scene bind group layout (15 entries).
	private IBindGroupLayout mSceneBindGroupLayout;

	/// Gets the shared scene bind group layout.
	public IBindGroupLayout SceneLayout => mSceneBindGroupLayout;

	public this(IDevice device, RenderSystem renderer)
	{
		mDevice = device;
		mRenderer = renderer;
	}

	public Result<void> Initialize()
	{
		using (SProfiler.Begin("SharedBindGroupLayouts"))
		{
			Try!(CreateSceneLayout());
		}
		return .Ok;
	}

	private Result<void> CreateSceneLayout()
	{
		// Scene bind group: camera, per-object transforms, lighting, shadows
		// Shader bindings (space0): b0=Camera, b1=ObjectUniforms, b3=LightingUniforms, b5=ShadowUniforms,
		//                           t4=Lights, t5=ClusterLightInfo, t6=LightIndices (read-only StructuredBuffers),
		//                           t7=ShadowMap, s1=ShadowSampler
		// Use HLSL register numbers - RHI applies Vulkan shifts based on Type
		BindGroupLayoutEntry[15] sceneEntries = .(
			.() { Binding = 0, Visibility = .Vertex | .Fragment, Type = .UniformBuffer }, // b0: Camera
			.() { Binding = 1, Visibility = .Vertex, Type = .UniformBuffer, HasDynamicOffset = true }, // b1: ObjectUniforms (dynamic offset per-object)
			.() { Binding = 3, Visibility = .Fragment, Type = .UniformBuffer },           // b3: Lighting uniforms
			.() { Binding = 4, Visibility = .Fragment, Type = .StorageBufferReadOnly },           // t4: Lights (StructuredBuffer)
			.() { Binding = 5, Visibility = .Fragment, Type = .StorageBufferReadOnly },           // t5: ClusterLightInfo (StructuredBuffer)
			.() { Binding = 6, Visibility = .Fragment, Type = .StorageBufferReadOnly },           // t6: LightIndices (StructuredBuffer)
			.() { Binding = 5, Visibility = .Fragment, Type = .UniformBuffer },           // b5: Shadow uniforms
			.() { Binding = 7, Visibility = .Fragment, Type = .SampledTexture },          // t7: ShadowMap
			.() { Binding = 1, Visibility = .Fragment, Type = .ComparisonSampler },       // s1: ShadowSampler
			BindGroupLayoutEntry.SampledTexture(8, .Fragment, .TextureCube),               // t8: Irradiance Map
			BindGroupLayoutEntry.SampledTexture(9, .Fragment, .TextureCube),               // t9: Prefiltered Map
			BindGroupLayoutEntry.SampledTexture(10, .Fragment, .Texture2D),                // t10: BRDF LUT
			BindGroupLayoutEntry.Sampler(2, .Fragment),                                    // s2: IBL Sampler
			.() { Binding = 6, Visibility = .Fragment, Type = .UniformBuffer },           // b6: ProbeUniforms
			BindGroupLayoutEntry.SampledTexture(11, .Fragment, .TextureCubeArray)          // t11: ProbeCubemaps
		);

		BindGroupLayoutDesc sceneDesc = .()
		{
			Label = "Scene BindGroup Layout",
			Entries = sceneEntries
		};

		switch (mDevice.CreateBindGroupLayout(sceneDesc))
		{
		case .Ok(let layout): mSceneBindGroupLayout = layout;
		case .Err: return .Err;
		}

		return .Ok;
	}

	/// Creates a scene bind group for the given frame.
	/// objectBuffer: the feature's own per-object uniform buffer for this frame.
	/// probeSystem: the reflection probe system (may be null).
	/// Returns null if required resources are not available.
	public IBindGroup CreateSceneBindGroup(int32 frameIndex, IBuffer objectBuffer, ReflectionProbeSystem probeSystem)
	{
		if (mSceneBindGroupLayout == null)
			return null;

		let lighting = mRenderer.LightingSystem;
		let shadowRenderer = mRenderer.ShadowRenderer;
		let shared = mRenderer.SharedResources;

		// Need all resources to be valid - use frame-specific buffers
		let cameraBuffer = mRenderer.RenderFrameContext?.SceneUniformBuffer;
		let lightingBuffer = lighting?.LightBuffer?.GetUniformBuffer(frameIndex);
		let lightDataBuffer = lighting?.LightBuffer?.GetLightDataBuffer(frameIndex);
		let viewIndex = mRenderer.RenderFrameContext?.ActiveViewIndex ?? 0;
		let clusterInfoBuffer = lighting?.ClusterGrid?.GetClusterLightInfoBuffer(frameIndex, viewIndex);
		let lightIndexBuffer = lighting?.ClusterGrid?.GetLightIndexBuffer(frameIndex, viewIndex);

		// Check required resources
		if (cameraBuffer == null || objectBuffer == null ||
			lightingBuffer == null || lightDataBuffer == null ||
			clusterInfoBuffer == null || lightIndexBuffer == null)
		{
			return null; // Can't create bind group without all resources
		}

		// Build bind group entries
		// Note: Some shadow resources may be null - provide fallbacks or skip
		BindGroupEntry[15] entries = .();

		// b0: Camera uniforms
		entries[0] = BindGroupEntry.Buffer(/*0,*/cameraBuffer, 0, SceneUniforms.Size);

		// b1: Object uniforms (dynamic offset - bind full buffer, use aligned size per object)
		entries[1] = BindGroupEntry.Buffer(/*1,*/objectBuffer, 0, AlignedObjectUniformSize);

		// b3: Lighting uniforms
		entries[2] = BindGroupEntry.Buffer(/*3,*/lightingBuffer, 0, (uint64)LightingUniforms.Size);

		// t4: Lights storage buffer
		entries[3] = BindGroupEntry.Buffer(/*4,*/lightDataBuffer, 0, (uint64)(lighting.LightBuffer.MaxLights * GPULight.Size));

		// t5: ClusterLightInfo storage buffer (8 bytes per cluster: 2 uint32)
		entries[4] = BindGroupEntry.Buffer(/*5,*/clusterInfoBuffer, 0, (uint64)(lighting.ClusterGrid.Config.TotalClusters * 8));

		// t6: LightIndices storage buffer
		entries[5] = BindGroupEntry.Buffer(/*6,*/lightIndexBuffer, 0, (uint64)(lighting.ClusterGrid.Config.MaxLightsPerCluster * lighting.ClusterGrid.Config.TotalClusters * 4));

		// Get shadow resources from ShadowRenderer
		let shadowsEnabled = shadowRenderer != null && shadowRenderer.EnableShadows;
		let shadowData = shadowRenderer?.GetShadowShaderData() ?? .();
		let materialSystem = mRenderer.MaterialSystem;

		// b5: Shadow uniforms
		if (shadowsEnabled && shadowData.CascadedShadowUniforms != null)
			entries[6] = BindGroupEntry.Buffer(/*5,*/shadowData.CascadedShadowUniforms, 0, (uint64)ShadowUniforms.Size);
		else
			entries[6] = BindGroupEntry.Buffer(/*5,*/lightingBuffer, 0, (uint64)LightingUniforms.Size); // Fallback

		// t7: Shadow map texture (cascaded shadow map array)
		// Only use shadow map if shadows are enabled - otherwise use dummy shadow map array
		if (shadowsEnabled && shadowData.CascadedShadowMapView != null)
			entries[7] = BindGroupEntry.Texture(/*7,*/shadowData.CascadedShadowMapView);
		else if (shared?.DummyShadowMapArrayView != null)
			entries[7] = BindGroupEntry.Texture(/*7,*/shared.DummyShadowMapArrayView); // Dummy 4-layer array
		else
			return null; // Can't create without texture

		// s1: Shadow sampler (comparison sampler for PCF)
		// Always use the shadow sampler if available (comparison sampler needed for depth comparison)
		if (shadowData.CascadedShadowSampler != null)
			entries[8] = BindGroupEntry.Sampler(/*1,*/shadowData.CascadedShadowSampler);
		else if (materialSystem?.DefaultSampler != null)
			entries[8] = BindGroupEntry.Sampler(/*1,*/materialSystem.DefaultSampler); // Fallback
		else
			return null; // Can't create without sampler

		// IBL resources (t8: Irradiance, t9: Prefiltered, t10: BRDF LUT, s2: IBL Sampler)
		ITextureView irradianceView = shared?.FallbackIrradianceCubemapView;
		ITextureView prefilteredView = shared?.FallbackPrefilteredCubemapView;
		ITextureView brdfLutView = shared?.FallbackBRDFLutView;
		ISampler iblSampler = shared?.IBLSampler;

		let skyFeature = mRenderer.GetFeature<SkyFeature>();
		if (skyFeature != null)
		{
			if (skyFeature.IrradianceMapView != null) irradianceView = skyFeature.IrradianceMapView;
			if (skyFeature.PrefilteredMapView != null) prefilteredView = skyFeature.PrefilteredMapView;
			if (skyFeature.BRDFLutView != null) brdfLutView = skyFeature.BRDFLutView;
			if (skyFeature.EnvironmentSampler != null) iblSampler = skyFeature.EnvironmentSampler;
		}

		if (irradianceView == null || prefilteredView == null || brdfLutView == null || iblSampler == null)
			return null;

		entries[9] = BindGroupEntry.Texture(/*8,*/irradianceView);
		entries[10] = BindGroupEntry.Texture(/*9,*/prefilteredView);
		entries[11] = BindGroupEntry.Texture(/*10,*/brdfLutView);
		entries[12] = BindGroupEntry.Sampler(/*2,*/iblSampler);

		// Probe resources (b6: ProbeUniforms, t11: ProbeCubemaps)
		if (probeSystem == null || probeSystem.GetProbeUniformBuffer(frameIndex) == null || probeSystem.GetCubemapArrayView() == null)
			return null;

		entries[13] = BindGroupEntry.Buffer(/*6,*/probeSystem.GetProbeUniformBuffer(frameIndex), 0, ProbeUniforms.Size);
		entries[14] = BindGroupEntry.Texture(/*11,*/probeSystem.GetCubemapArrayView());

		// Create bind group
		BindGroupDesc bgDesc = .()
		{
			Label = "Scene BindGroup",
			Layout = mSceneBindGroupLayout,
			Entries = entries
		};

		if (mDevice.CreateBindGroup(bgDesc) case .Ok(let bg))
			return bg;

		return null;
	}

	/// Aligned object uniform size (matches ForwardOpaqueFeature.AlignedObjectUniformSize)
	private static uint64 AlignedObjectUniformSize => 256;

	public void Shutdown()
	{
		mDevice.DestroyBindGroupLayout(ref mSceneBindGroupLayout);
	}

	public ~this()
	{
		Shutdown();
	}
}
