namespace Sedulous.Renderer;

using System;
using Sedulous.RHI;
using Sedulous.Core.Mathematics;

using internal Sedulous.Renderer;

/// GPU-uploadable shadow uniform data for cascade shadow maps.
/// Matches the ShadowUniforms cbuffer in forward_pbr.hlsl exactly.
[CRepr]
struct ShadowUniforms
{
	public Matrix[RenderConfig.ShadowCascadeCount] CascadeViewProjection;  // 256 bytes
	public Vector4 CascadeDistances;                                        // 16 bytes (view-space far Z per cascade)
	public Vector4 ShadowParams;                                            // 16 bytes (x=depthBias, y=normalBias, z=blendRange, w=cascadeCount)
	// Total: 288 bytes
}

/// Per-cascade shadow pass uniform data.
/// Matches the ShadowPassUniforms cbuffer in shadow_depth.hlsl.
[CRepr]
struct ShadowPassUniforms
{
	public Matrix LightViewProjection;    // 64 bytes
	public float NormalBias;              // 4 bytes
	public Vector3 LightDirection;        // 12 bytes
	// Total: 80 bytes
}

/// Manages cascaded shadow maps for directional lights.
/// Owned by RenderSystem as shared scene-level infrastructure.
/// Shadow passes run pre-graph (raw encoder), producing a Texture2DArray
/// that the forward shader samples via the scene bind group.
class ShadowSystem
{
	private IDevice mDevice;

	// --- Shadow atlas (point/spot lights) ---
	private ShadowAtlas mShadowAtlas = new .() ~ delete _;

	// --- Cascade shadow map texture ---
	private ITexture mCascadeTexture;
	private ITextureView mCascadeArrayView;                                          // Full array view for sampling in forward pass
	private ITextureView[RenderConfig.ShadowCascadeCount] mCascadeLayerViews;        // Per-layer views for depth rendering
	private ISampler mShadowSampler;

	// --- Shadow uniform buffers (scene bind group, per-frame-per-view) ---
	private IBuffer[RenderConfig.TotalBufferSlots] mShadowUniformBuffers;
	private void*[RenderConfig.TotalBufferSlots] mShadowUniformPtrs;

	// --- Shadow pass resources ---
	private IBindGroupLayout mShadowPassBindGroupLayout;
	private IPipelineLayout mShadowPipelineLayout;
	private IRenderPipeline mShadowPipeline;
	private const int ShadowPassBufferCount = RenderConfig.FrameBufferCount * RenderConfig.ShadowCascadeCount;
	private IBuffer[ShadowPassBufferCount] mShadowPassUniformBuffers;       // Per-cascade-per-frame UBO
	private void*[ShadowPassBufferCount] mShadowPassUniformPtrs;
	private IBindGroup[ShadowPassBufferCount] mShadowPassBindGroups;

	// --- Atlas pass resources (per-tile-per-frame UBOs) ---
	private const int AtlasPassBufferCount = RenderConfig.FrameBufferCount * RenderConfig.ShadowAtlasTotalTiles;
	private IBuffer[AtlasPassBufferCount] mAtlasPassUniformBuffers;
	private void*[AtlasPassBufferCount] mAtlasPassUniformPtrs;
	private IBindGroup[AtlasPassBufferCount] mAtlasPassBindGroups;

	// --- Cascade state ---
	private Matrix[RenderConfig.ShadowCascadeCount] mCascadeViewProjections;
	private float[RenderConfig.ShadowCascadeCount] mCascadeDistances;
	private Vector3 mLightDirection;
	private float mShadowBias = 0.003f;
	private float mShadowNormalBias = 0.02f;
	private float mSplitLambda = 0.85f;
	private float mBlendRange = 5.0f;
	private bool mHasShadowCaster;
	private bool mFirstFrame = true;

	/// True if a shadow-casting directional light was found this frame.
	public bool HasShadowCaster => mHasShadowCaster;

	/// Gets the shadow uniform buffer for the scene bind group.
	public IBuffer GetShadowUniformBuffer(int bufferSlot) => mShadowUniformBuffers[bufferSlot];

	/// Gets the full cascade array view for sampling in the forward shader.
	public ITextureView GetCascadeTextureView() => mCascadeArrayView;
	public ITexture GetCascadeTexture() => mCascadeTexture;

	/// Gets the comparison sampler for shadow sampling.
	public ISampler GetShadowSampler() => mShadowSampler;

	/// Gets the shadow atlas texture view for the forward shader.
	public ITextureView GetAtlasTextureView() => mShadowAtlas.GetAtlasTextureView();
	/// Gets the shadow atlas texture (for initial state transitions).
	public ITexture GetAtlasTexture() => mShadowAtlas.GetAtlasTexture();

	/// Gets the shadow atlas data buffer for the forward shader.
	public IBuffer GetAtlasDataBuffer(int frameIndex) => mShadowAtlas.GetShadowDataBuffer(frameIndex);

	/// Gets the shadow atlas for direct access (tile allocation, VP updates).
	public ShadowAtlas Atlas => mShadowAtlas;

	public Result<void> Initialize(IDevice device, ShaderLibrary shaderLib, IBindGroupLayout objectBindGroupLayout)
	{
		mDevice = device;

		// --- Cascade shadow map texture (Texture2DArray) ---
		let texResult = device.CreateTexture(TextureDesc.Tex2DArray(
			.Depth32Float,
			(uint32)RenderConfig.ShadowMapResolution,
			(uint32)RenderConfig.ShadowMapResolution,
			(uint32)RenderConfig.ShadowCascadeCount,
			.DepthStencil | .Sampled,
			label: "CascadeShadowMap"
		));
		if (texResult case .Err)
			return .Err;
		mCascadeTexture = texResult.Value;

		// Full array view for sampling in forward pass
		let arrayViewResult = device.CreateTextureView(mCascadeTexture, TextureViewDesc()
		{
			Dimension = .Texture2DArray,
			BaseArrayLayer = 0,
			ArrayLayerCount = (uint32)RenderConfig.ShadowCascadeCount,
			Aspect = .DepthOnly,
			Label = "CascadeShadowMap_ArrayView"
		});
		if (arrayViewResult case .Err)
			return .Err;
		mCascadeArrayView = arrayViewResult.Value;

		// Per-layer views for rendering
		for (uint32 i = 0; i < RenderConfig.ShadowCascadeCount; i++)
		{
			let layerResult = device.CreateTextureView(mCascadeTexture, TextureViewDesc()
			{
				Dimension = .Texture2D,
				BaseArrayLayer = i,
				ArrayLayerCount = 1,
				Aspect = .DepthOnly,
				Label = "CascadeLayer"
			});
			if (layerResult case .Err)
				return .Err;
			mCascadeLayerViews[i] = layerResult.Value;
		}

		// --- Comparison sampler ---
		let samplerResult = device.CreateSampler(SamplerDesc()
		{
			MinFilter = .Linear,
			MagFilter = .Linear,
			MipmapFilter = .Nearest,
			AddressU = .ClampToEdge,
			AddressV = .ClampToEdge,
			AddressW = .ClampToEdge,
			Compare = .LessEqual,
			Label = "ShadowSampler"
		});
		if (samplerResult case .Err)
			return .Err;
		mShadowSampler = samplerResult.Value;

		// --- Shadow uniform buffers (per-frame-per-view, for scene bind group) ---
		for (int i = 0; i < RenderConfig.TotalBufferSlots; i++)
		{
			let bufResult = device.CreateBuffer(BufferDesc()
			{
				Size = (uint64)sizeof(ShadowUniforms),
				Usage = .Uniform,
				Memory = .CpuToGpu,
				Label = "ShadowUniforms"
			});
			if (bufResult case .Err)
				return .Err;
			mShadowUniformBuffers[i] = bufResult.Value;
			mShadowUniformPtrs[i] = mShadowUniformBuffers[i].Map();
		}

		// --- Shadow pass uniform buffers (per-frame-per-cascade) ---
		// Each cascade needs its own buffer because commands are recorded before
		// GPU execution — a single rewritten buffer would only contain the last cascade's data.
		for (int i = 0; i < ShadowPassBufferCount; i++)
		{
			let bufResult = device.CreateBuffer(BufferDesc()
			{
				Size = (uint64)sizeof(ShadowPassUniforms),
				Usage = .Uniform,
				Memory = .CpuToGpu,
				Label = "ShadowPassUniforms"
			});
			if (bufResult case .Err)
				return .Err;
			mShadowPassUniformBuffers[i] = bufResult.Value;
			mShadowPassUniformPtrs[i] = mShadowPassUniformBuffers[i].Map();
		}

		// --- Shadow pass pipeline ---
		if (CreateShadowPipeline(device, shaderLib, objectBindGroupLayout) case .Err)
			return .Err;

		// --- Shadow atlas (point/spot lights) ---
		if (mShadowAtlas.Initialize(device) case .Err)
			return .Err;

		// --- Atlas pass uniform buffers (per-tile-per-frame) ---
		for (int i = 0; i < AtlasPassBufferCount; i++)
		{
			let bufResult = device.CreateBuffer(BufferDesc()
			{
				Size = (uint64)sizeof(ShadowPassUniforms),
				Usage = .Uniform,
				Memory = .CpuToGpu,
				Label = "AtlasPassUniforms"
			});
			if (bufResult case .Err)
				return .Err;
			mAtlasPassUniformBuffers[i] = bufResult.Value;
			mAtlasPassUniformPtrs[i] = mAtlasPassUniformBuffers[i].Map();
		}

		return .Ok;
	}

	private Result<void> CreateShadowPipeline(IDevice device, ShaderLibrary shaderLib, IBindGroupLayout objectBindGroupLayout)
	{
		// Shadow pass bind group layout (Set 0): single UBO for light VP + bias
		var shadowPassEntry = BindGroupLayoutEntry.UniformBuffer(0, .Vertex);
		let layoutResult = device.CreateBindGroupLayout(BindGroupLayoutDesc()
		{
			Entries = Span<BindGroupLayoutEntry>(&shadowPassEntry, 1),
			Label = "ShadowPassBindGroupLayout"
		});
		if (layoutResult case .Err)
			return .Err;
		mShadowPassBindGroupLayout = layoutResult.Value;

		// Pipeline layout: Set 0 = shadow pass UBO, Set 1 = object UBO (dynamic offset)
		IBindGroupLayout[2] bgLayouts = .(mShadowPassBindGroupLayout, objectBindGroupLayout);
		let pipeLayoutResult = device.CreatePipelineLayout(PipelineLayoutDesc()
		{
			BindGroupLayouts = Span<IBindGroupLayout>(&bgLayouts[0], 2),
			Label = "ShadowPipelineLayout"
		});
		if (pipeLayoutResult case .Err)
			return .Err;
		mShadowPipelineLayout = pipeLayoutResult.Value;

		// Compile shadow depth shader
		if (shaderLib.RegisterShader("shadow_depth") case .Err)
			return .Err;

		let vsResult = shaderLib.GetCompiledShader("shadow_depth", .Vertex);
		if (vsResult case .Err)
			return .Err;

		// Create depth-only pipeline: no fragment shader, no color targets
		// Front-face culling (render back-faces) to reduce shadow acne
		var vertexLayout = VertexLayoutHelper.GetStaticMeshLayout();
		let pipeResult = device.CreateRenderPipeline(RenderPipelineDesc()
		{
			Layout = mShadowPipelineLayout,
			Vertex = .() { Shader = .(vsResult.Value, "VSMain"), Buffers = Span<VertexBufferLayout>(&vertexLayout, 1) },
			Fragment = null,
			Primitive = PrimitiveState()
			{
				Topology = .TriangleList,
				CullMode = .None,
				FrontFace = .CCW
			},
			DepthStencil = DepthStencilState.DepthDefault(.Depth32Float),
			Label = "ShadowDepthPipeline"
		});
		if (pipeResult case .Err)
			return .Err;
		mShadowPipeline = pipeResult.Value;

		return .Ok;
	}

	/// Finds shadow-casting directional light and computes cascade matrices.
	/// Call during CPU preparation, before recording shadow passes.
	public void Update(RenderWorld world, ViewContext viewCtx, int bufferSlot)
	{
		mHasShadowCaster = false;

		if (world == null)
			return;

		// Find the first directional light with CastShadows
		LightProxy* shadowLight = null;
		world.Lights.ForEach(scope [&] (handle, proxy) =>
		{
			if (mHasShadowCaster)
				return;
			if (proxy.Type == .Directional && proxy.CastShadows)
			{
				shadowLight = &proxy;
				mHasShadowCaster = true;
				mLightDirection = Vector3.Normalize(proxy.Direction);
				mShadowBias = proxy.ShadowBias;
				mShadowNormalBias = proxy.ShadowNormalBias;
			}
		});

		if (!mHasShadowCaster)
		{
			// Upload zeroed shadow uniforms (no shadows)
			UploadShadowUniforms(bufferSlot);
			return;
		}

		// Compute cascade splits
		let nearClip = viewCtx.NearPlane;
		let farClip = viewCtx.FarPlane;
		ComputeCascadeSplits(nearClip, farClip);

		// Compute cascade view-projection matrices
		for (int i = 0; i < RenderConfig.ShadowCascadeCount; i++)
		{
			let cascadeNear = (i == 0) ? nearClip : mCascadeDistances[i - 1];
			let cascadeFar = mCascadeDistances[i];
			mCascadeViewProjections[i] = ComputeCascadeMatrix(viewCtx, cascadeNear, cascadeFar);
		}

		// Upload shadow uniforms to scene bind group buffer
		UploadShadowUniforms(bufferSlot);
	}

	private void ComputeCascadeSplits(float nearClip, float farClip)
	{
		let cascadeCount = RenderConfig.ShadowCascadeCount;
		for (int i = 0; i < cascadeCount; i++)
		{
			let p = (float)(i + 1) / (float)cascadeCount;
			let logSplit = nearClip * Math.Pow(farClip / nearClip, p);
			let uniformSplit = nearClip + (farClip - nearClip) * p;
			mCascadeDistances[i] = Math.Lerp(uniformSplit, logSplit, mSplitLambda);
		}
	}

	private Matrix ComputeCascadeMatrix(ViewContext viewCtx, float cascadeNear, float cascadeFar)
	{
		// Get the full frustum corners in world space from the camera VP
		Matrix.Invert(viewCtx.ViewProjectionMatrix, let invVP);

		// 8 NDC corners → world space (full camera frustum)
		Vector3[8] fullCorners = .();
		int idx = 0;
		for (int z = 0; z < 2; z++)
		{
			for (int y = 0; y < 2; y++)
			{
				for (int x = 0; x < 2; x++)
				{
					let ndcCorner = Vector4(
						x * 2.0f - 1.0f,
						y * 2.0f - 1.0f,
						z * 1.0f,  // DX-style: 0 = near, 1 = far
						1.0f
					);
					var worldCorner = Vector4.Transform(ndcCorner, invVP);
					worldCorner /= worldCorner.W;
					fullCorners[idx++] = .(worldCorner.X, worldCorner.Y, worldCorner.Z);
				}
			}
		}

		// Interpolate between near and far corners to get cascade slice
		let nearT = (cascadeNear - viewCtx.NearPlane) / (viewCtx.FarPlane - viewCtx.NearPlane);
		let farT = (cascadeFar - viewCtx.NearPlane) / (viewCtx.FarPlane - viewCtx.NearPlane);

		Vector3[8] corners = .();
		// Near plane corners (indices 0-3 are NDC near, 4-7 are NDC far)
		for (int i = 0; i < 4; i++)
		{
			let nearCorner = fullCorners[i];          // NDC near
			let farCorner = fullCorners[i + 4];       // NDC far
			corners[i] = Vector3.Lerp(nearCorner, farCorner, nearT);
			corners[i + 4] = Vector3.Lerp(nearCorner, farCorner, farT);
		}

		// Compute frustum center
		var center = Vector3.Zero;
		for (let c in corners)
			center += c;
		center /= 8.0f;

		// Light view matrix: looking from center along light direction
		let lightUp = (Math.Abs(mLightDirection.Y) > 0.99f)
			? Vector3(1, 0, 0)
			: Vector3(0, 1, 0);
		let lightView = Matrix.CreateLookAt(center - mLightDirection * 100.0f, center, lightUp);

		// Transform corners to light space and compute AABB
		var minBounds = Vector3(float.MaxValue, float.MaxValue, float.MaxValue);
		var maxBounds = Vector3(float.MinValue, float.MinValue, float.MinValue);
		for (let c in corners)
		{
			let lightSpaceCorner = Vector3.Transform(c, lightView);
			minBounds = Vector3.Min(minBounds, lightSpaceCorner);
			maxBounds = Vector3.Max(maxBounds, lightSpaceCorner);
		}

		// Texel snapping: snap bounds to shadow map texel grid
		let texelSize = (float)RenderConfig.ShadowMapResolution;
		let worldUnitsPerTexelX = (maxBounds.X - minBounds.X) / texelSize;
		let worldUnitsPerTexelY = (maxBounds.Y - minBounds.Y) / texelSize;

		minBounds.X = Math.Floor(minBounds.X / worldUnitsPerTexelX) * worldUnitsPerTexelX;
		maxBounds.X = Math.Floor(maxBounds.X / worldUnitsPerTexelX) * worldUnitsPerTexelX;
		minBounds.Y = Math.Floor(minBounds.Y / worldUnitsPerTexelY) * worldUnitsPerTexelY;
		maxBounds.Y = Math.Floor(maxBounds.Y / worldUnitsPerTexelY) * worldUnitsPerTexelY;

		// Extend depth range to catch shadow casters behind the camera frustum
		let zRange = maxBounds.Z - minBounds.Z;
		minBounds.Z -= zRange * 0.5f;

		// Orthographic projection from AABB.
		// CreateOrthographicOffCenter expects positive near/far distances, but
		// light view space is right-handed (negative Z in front of camera).
		// Negate and swap Z bounds to convert to positive distances.
		let lightProj = Matrix.CreateOrthographicOffCenter(
			minBounds.X, maxBounds.X,
			minBounds.Y, maxBounds.Y,
			-maxBounds.Z, -minBounds.Z
		);

		return lightView * lightProj;
	}

	private void UploadShadowUniforms(int bufferSlot)
	{
		ShadowUniforms uniforms = .();

		if (mHasShadowCaster)
		{
			for (int i = 0; i < RenderConfig.ShadowCascadeCount; i++)
				uniforms.CascadeViewProjection[i] = mCascadeViewProjections[i];

			uniforms.CascadeDistances = .(
				mCascadeDistances[0], mCascadeDistances[1],
				mCascadeDistances[2], mCascadeDistances[3]
			);
			uniforms.ShadowParams = .(mShadowBias, mShadowNormalBias, mBlendRange, (float)RenderConfig.ShadowCascadeCount);
		}

		if (mShadowUniformPtrs[bufferSlot] != null)
			Internal.MemCpy(mShadowUniformPtrs[bufferSlot], &uniforms, sizeof(ShadowUniforms));
	}

	/// Records shadow cascade depth passes on the raw encoder (pre-graph).
	/// Call after light data upload and cluster culling, before graph execution.
	public void RecordShadowPasses(
		ICommandEncoder encoder,
		int frameIndex,
		RenderWorld world,
		GPUResourceManager resources,
		DrawBatcher batcher,
		ObjectUniformManager objectUniforms,
		IBindGroup objectBindGroup,
		SkinningSystem skinning = null)
	{
		// On first frame, transition BOTH cascade and atlas textures to ShaderRead.
		// Both are bound in the scene bind group and must be in a valid state
		// even if no shadow passes run this frame.
		if (mFirstFrame)
		{
			TextureBarrier[2] firstFrameBarriers = .();
			int barrierCount = 0;

			// Cascade texture: Undefined/InitialState → ShaderRead
			firstFrameBarriers[barrierCount++] = TextureBarrier()
			{
				Texture = mCascadeTexture,
				OldState = mHasShadowCaster ? mCascadeTexture.InitialState : .Undefined,
				NewState = .ShaderRead,
				BaseArrayLayer = 0,
				ArrayLayerCount = (uint32)RenderConfig.ShadowCascadeCount
			};

			// Atlas texture: InitialState → ShaderRead
			let atlasTexture = mShadowAtlas.GetAtlasTexture();
			if (atlasTexture != null)
			{
				firstFrameBarriers[barrierCount++] = TextureBarrier()
				{
					Texture = atlasTexture,
					OldState = atlasTexture.InitialState,
					NewState = .ShaderRead
				};
				mShadowAtlas.ClearFirstFrame();
			}

			encoder.Barrier(BarrierGroup()
			{
				TextureBarriers = Span<TextureBarrier>(&firstFrameBarriers[0], barrierCount)
			});
			mFirstFrame = false;

			if (!mHasShadowCaster)
				return;
		}
		else if (!mHasShadowCaster)
		{
			return;
		}

		// (First-frame cascade transition is handled above)

		let resolution = (uint32)RenderConfig.ShadowMapResolution;

		for (int cascade = 0; cascade < RenderConfig.ShadowCascadeCount; cascade++)
		{
			let bufSlot = frameIndex * RenderConfig.ShadowCascadeCount + cascade;

			// Upload shadow pass uniforms for this cascade
			ShadowPassUniforms passUniforms = .();
			passUniforms.LightViewProjection = mCascadeViewProjections[cascade];
			passUniforms.NormalBias = mShadowNormalBias;
			passUniforms.LightDirection = mLightDirection;

			if (mShadowPassUniformPtrs[bufSlot] != null)
				Internal.MemCpy(mShadowPassUniformPtrs[bufSlot], &passUniforms, sizeof(ShadowPassUniforms));

			// Rebuild bind group for this cascade's buffer
			RebuildShadowPassBindGroup(bufSlot);

			// Barrier: transition cascade layer for depth writing
			{
				var texBarrier = TextureBarrier()
				{
					Texture = mCascadeTexture,
					OldState = .ShaderRead,
					NewState = .DepthStencilWrite,
					BaseArrayLayer = (uint32)cascade,
					ArrayLayerCount = 1
				};
				encoder.Barrier(BarrierGroup()
				{
					TextureBarriers = Span<TextureBarrier>(&texBarrier, 1)
				});
			}

			// Begin render pass for this cascade layer
			var depthAttachment = DepthStencilAttachment()
			{
				View = mCascadeLayerViews[cascade],
				DepthLoadOp = .Clear,
				DepthStoreOp = .Store,
				DepthClearValue = 1.0f
			};
			var rpDesc = RenderPassDesc()
			{
				DepthStencilAttachment = depthAttachment,
				Label = "ShadowCascade"
			};
			let rp = encoder.BeginRenderPass(rpDesc);

			rp.SetViewport(0, 0, (float)resolution, (float)resolution, 0.0f, 1.0f);
			rp.SetScissor(0, 0, resolution, resolution);
			rp.SetPipeline(mShadowPipeline);
			rp.SetBindGroup(0, mShadowPassBindGroups[bufSlot]);

			// Draw shadow-casting meshes
			DrawShadowCasters(rp, world, resources, batcher, objectUniforms, objectBindGroup);
			if (skinning != null)
				DrawSkinnedShadowCasters(rp, world, resources, skinning, objectUniforms, objectBindGroup);

			rp.End();

			// Barrier: transition cascade layer back to shader read
			{
				var texBarrier = TextureBarrier()
				{
					Texture = mCascadeTexture,
					OldState = .DepthStencilWrite,
					NewState = .ShaderRead,
					BaseArrayLayer = (uint32)cascade,
					ArrayLayerCount = 1
				};
				encoder.Barrier(BarrierGroup()
				{
					TextureBarriers = Span<TextureBarrier>(&texBarrier, 1)
				});
			}
		}
	}

	/// Allocates atlas tiles and updates VP matrices for shadow-casting point/spot lights.
	/// Must be called BEFORE LightingSystem.Update() so shadow indices are available
	/// for GPULightData upload.
	public void UpdateAtlas(RenderWorld world, int frameIndex)
	{
		if (world == null)
			return;

		world.Lights.ForEach(scope [&] (handle, proxy) =>
		{
			if (!proxy.CastShadows || proxy.Type == .Directional)
				return;

			let lightKey = (uint64)handle.Index;

			// Allocate tiles if not already allocated
			if (!mShadowAtlas.HasAllocation(lightKey))
			{
				if (proxy.Type == .Spot)
					mShadowAtlas.AllocateSpotLight(lightKey);
				else if (proxy.Type == .Point)
					mShadowAtlas.AllocatePointLight(lightKey);
			}

			// Update VP matrices
			if (proxy.Type == .Spot)
				mShadowAtlas.UpdateSpotLight(lightKey, ref proxy);
			else if (proxy.Type == .Point)
				mShadowAtlas.UpdatePointLight(lightKey, ref proxy);
		});

		// Upload shadow data to GPU
		mShadowAtlas.UploadShadowData(frameIndex);
	}

	/// Gets the shadow data index for a light in the atlas.
	/// Returns uint32.MaxValue if no shadow allocated.
	public uint32 GetAtlasShadowIndex(uint64 lightKey)
	{
		let idx = mShadowAtlas.GetShadowDataIndex(lightKey);
		return (idx >= 0) ? (uint32)idx : uint32.MaxValue;
	}

	/// Records atlas shadow passes after cascade passes.
	/// Renders all allocated atlas tiles with viewport/scissor per tile.
	public void RecordAtlasShadowPasses(
		ICommandEncoder encoder,
		int frameIndex,
		RenderWorld world,
		GPUResourceManager resources,
		DrawBatcher batcher,
		ObjectUniformManager objectUniforms,
		IBindGroup objectBindGroup,
		SkinningSystem skinning = null)
	{
		if (mShadowAtlas.ActiveShadowCount == 0)
		{
			// Still need first-frame transition for the atlas texture
			if (mShadowAtlas.IsFirstFrame)
			{
				var texBarrier = TextureBarrier()
				{
					Texture = mShadowAtlas.GetAtlasTexture(),
					OldState = mShadowAtlas.GetAtlasTexture().InitialState,
					NewState = .ShaderRead
				};
				encoder.Barrier(BarrierGroup()
				{
					TextureBarriers = Span<TextureBarrier>(&texBarrier, 1)
				});
				mShadowAtlas.ClearFirstFrame();
			}
			return;
		}

		// Copy shadow data from staging → GPU
		mShadowAtlas.RecordUpload(encoder, frameIndex);

		// First-frame or normal: transition atlas to DepthWrite for all passes
		{
			var texBarrier = TextureBarrier()
			{
				Texture = mShadowAtlas.GetAtlasTexture(),
				OldState = mShadowAtlas.IsFirstFrame ? mShadowAtlas.GetAtlasTexture().InitialState : .ShaderRead,
				NewState = .DepthStencilWrite
			};
			encoder.Barrier(BarrierGroup()
			{
				TextureBarriers = Span<TextureBarrier>(&texBarrier, 1)
			});
			mShadowAtlas.ClearFirstFrame();
		}

		let tileSize = (uint32)RenderConfig.ShadowAtlasTileSize;

		// Render each allocated tile as a separate render pass with viewport/scissor
		// First pass: clear entire atlas
		{
			var depthAttachment = DepthStencilAttachment()
			{
				View = mShadowAtlas.GetAtlasDsvView(),
				DepthLoadOp = .Clear,
				DepthStoreOp = .Store,
				DepthClearValue = 1.0f
			};
			var rpDesc = RenderPassDesc()
			{
				DepthStencilAttachment = depthAttachment,
				Label = "ShadowAtlasClear"
			};
			let rp = encoder.BeginRenderPass(rpDesc);
			rp.End();
		}

		// Render each allocated tile with its own buffer slot
		int atlasTileIndex = 0;
		for (int i = 0; i < RenderConfig.ShadowAtlasTotalTiles; i++)
		{
			let tile = mShadowAtlas.GetTile(i);
			if (tile == null || !tile.IsAllocated)
				continue;

			// Each atlas tile needs its own UBO to avoid CpuToGpu overwrite.
			let atlasSlot = frameIndex * RenderConfig.ShadowAtlasTotalTiles + atlasTileIndex;

			if (atlasSlot >= AtlasPassBufferCount || mAtlasPassUniformPtrs[atlasSlot] == null)
			{
				atlasTileIndex++;
				continue;
			}

			// Upload shadow pass uniforms for this tile
			ShadowPassUniforms passUniforms = .();
			passUniforms.LightViewProjection = tile.ViewProjection;
			passUniforms.NormalBias = mShadowNormalBias;
			passUniforms.LightDirection = mLightDirection;

			Internal.MemCpy(mAtlasPassUniformPtrs[atlasSlot], &passUniforms, sizeof(ShadowPassUniforms));
			RebuildAtlasPassBindGroup(atlasSlot);

			// Begin render pass for this tile
			var depthAttachment = DepthStencilAttachment()
			{
				View = mShadowAtlas.GetAtlasDsvView(),
				DepthLoadOp = .Load,
				DepthStoreOp = .Store,
				DepthClearValue = 1.0f
			};
			var rpDesc = RenderPassDesc()
			{
				DepthStencilAttachment = depthAttachment,
				Label = "ShadowAtlasTile"
			};
			let rp = encoder.BeginRenderPass(rpDesc);

			rp.SetViewport(
				(float)tile.ViewportX, (float)tile.ViewportY,
				(float)tileSize, (float)tileSize,
				0.0f, 1.0f);
			rp.SetScissor(
				(int32)tile.ViewportX, (int32)tile.ViewportY,
				tileSize, tileSize);
			rp.SetPipeline(mShadowPipeline);
			rp.SetBindGroup(0, mAtlasPassBindGroups[atlasSlot]);

			// Draw shadow casters
			DrawShadowCasters(rp, world, resources, batcher, objectUniforms, objectBindGroup);
			if (skinning != null)
				DrawSkinnedShadowCasters(rp, world, resources, skinning, objectUniforms, objectBindGroup);

			rp.End();
			atlasTileIndex++;
		}

		// Transition atlas back to ShaderRead
		{
			var texBarrier = TextureBarrier()
			{
				Texture = mShadowAtlas.GetAtlasTexture(),
				OldState = .DepthStencilWrite,
				NewState = .ShaderRead
			};
			encoder.Barrier(BarrierGroup()
			{
				TextureBarriers = Span<TextureBarrier>(&texBarrier, 1)
			});
		}
	}

	private void DrawShadowCasters(
		IRenderPassEncoder rp,
		RenderWorld world,
		GPUResourceManager resources,
		DrawBatcher batcher,
		ObjectUniformManager objectUniforms,
		IBindGroup objectBindGroup)
	{
		for (int i = 0; i < batcher.OpaqueBatches.Count; i++)
		{
			let batch = batcher.OpaqueBatches[i];
			let group = batcher.InstanceGroups[i];

			let mesh = resources.GetMesh(batch.MeshHandle);
			if (mesh == null) continue;
			if (batch.SubMeshIndex >= (uint32)mesh.SubMeshes.Count) continue;
			let subMesh = mesh.SubMeshes[batch.SubMeshIndex];

			rp.SetVertexBuffer(0, mesh.VertexBuffer, 0);
			if (mesh.IndexBuffer != null)
				rp.SetIndexBuffer(mesh.IndexBuffer, mesh.IndexFormat, 0);

			for (uint32 j = 0; j < group.Count; j++)
			{
				let proxyHandle = batcher.InstanceProxies[group.StartIndex + j];
				let proxy = world.StaticMeshes.Get(proxyHandle);
				if (proxy == null) continue;

				// Skip meshes that don't cast shadows
				if (!proxy.Flags.HasFlag(.CastShadows))
					continue;

				var objUniforms = ObjectUniforms();
				objUniforms.WorldMatrix = proxy.Transform;
				objUniforms.PrevWorldMatrix = proxy.Transform;
				Matrix.Invert(proxy.Transform, out objUniforms.NormalMatrix);
				objUniforms.NormalMatrix = Matrix.Transpose(objUniforms.NormalMatrix);

				let dynamicOffset = objectUniforms.AllocateObject(objUniforms);
				if (dynamicOffset == uint32.MaxValue) return;

				uint32[1] offsets = .(dynamicOffset);
				rp.SetBindGroup(1, objectBindGroup, Span<uint32>(&offsets[0], 1));

				rp.DrawIndexed(subMesh.IndexCount, 1, subMesh.IndexStart, subMesh.BaseVertex, 0);
			}
		}
	}

	private void DrawSkinnedShadowCasters(
		IRenderPassEncoder rp,
		RenderWorld world,
		GPUResourceManager resources,
		SkinningSystem skinning,
		ObjectUniformManager objectUniforms,
		IBindGroup objectBindGroup)
	{
		for (let draw in skinning.OpaqueDraws)
		{
			let proxy = world.SkinnedMeshes.Get(draw.ProxyHandle);
			if (proxy == null) continue;
			if (!proxy.Flags.HasFlag(.CastShadows)) continue;

			let mesh = resources.GetMesh(draw.MeshHandle);
			if (mesh == null) continue;
			if (draw.SubMeshIndex >= (uint32)mesh.SubMeshes.Count) continue;
			let subMesh = mesh.SubMeshes[draw.SubMeshIndex];

			rp.SetVertexBuffer(0, draw.OutputVertexBuffer, 0);

			var objUniforms = ObjectUniforms();
			objUniforms.WorldMatrix = proxy.Transform;
			objUniforms.PrevWorldMatrix = proxy.PrevTransform;
			Matrix.Invert(proxy.Transform, out objUniforms.NormalMatrix);
			objUniforms.NormalMatrix = Matrix.Transpose(objUniforms.NormalMatrix);

			let dynamicOffset = objectUniforms.AllocateObject(objUniforms);
			if (dynamicOffset == uint32.MaxValue) return;

			uint32[1] offsets = .(dynamicOffset);
			rp.SetBindGroup(1, objectBindGroup, Span<uint32>(&offsets[0], 1));

			if (mesh.IndexBuffer != null && subMesh.IndexCount > 0)
			{
				rp.SetIndexBuffer(mesh.IndexBuffer, mesh.IndexFormat, 0);
				rp.DrawIndexed(subMesh.IndexCount, 1, subMesh.IndexStart, subMesh.BaseVertex, 0);
			}
			else
			{
				rp.Draw(subMesh.IndexCount > 0 ? subMesh.IndexCount : mesh.VertexCount, 1, 0, 0);
			}
		}
	}

	private void RebuildShadowPassBindGroup(int bufSlot)
	{
		if (mShadowPassBindGroups[bufSlot] != null)
			mDevice.DestroyBindGroup(ref mShadowPassBindGroups[bufSlot]);

		var entry = BindGroupEntry.Buffer(mShadowPassUniformBuffers[bufSlot], 0, (uint64)sizeof(ShadowPassUniforms));
		let result = mDevice.CreateBindGroup(BindGroupDesc()
		{
			Layout = mShadowPassBindGroupLayout,
			Entries = Span<BindGroupEntry>(&entry, 1),
			Label = "ShadowPassBindGroup"
		});
		if (result case .Ok(let bg))
			mShadowPassBindGroups[bufSlot] = bg;
	}

	private void RebuildAtlasPassBindGroup(int bufSlot)
	{
		if (mAtlasPassBindGroups[bufSlot] != null)
			mDevice.DestroyBindGroup(ref mAtlasPassBindGroups[bufSlot]);

		var entry = BindGroupEntry.Buffer(mAtlasPassUniformBuffers[bufSlot], 0, (uint64)sizeof(ShadowPassUniforms));
		let result = mDevice.CreateBindGroup(BindGroupDesc()
		{
			Layout = mShadowPassBindGroupLayout,
			Entries = Span<BindGroupEntry>(&entry, 1),
			Label = "AtlasPassBindGroup"
		});
		if (result case .Ok(let bg))
			mAtlasPassBindGroups[bufSlot] = bg;
	}

	public void Shutdown()
	{
		if (mDevice == null)
			return;

		// Shadow atlas
		mShadowAtlas.Shutdown();

		// Atlas pass resources
		for (int i = 0; i < AtlasPassBufferCount; i++)
		{
			if (mAtlasPassBindGroups[i] != null)
				mDevice.DestroyBindGroup(ref mAtlasPassBindGroups[i]);
		}
		for (int i = 0; i < AtlasPassBufferCount; i++)
		{
			if (mAtlasPassUniformBuffers[i] != null)
			{
				mAtlasPassUniformBuffers[i].Unmap();
				mAtlasPassUniformPtrs[i] = null;
				mDevice.DestroyBuffer(ref mAtlasPassUniformBuffers[i]);
			}
		}

		// Shadow pass resources — destroy consumers before producers:
		// pipeline → pipeline layout → bind groups → bind group layout → buffers
		if (mShadowPipeline != null)
			mDevice.DestroyRenderPipeline(ref mShadowPipeline);
		if (mShadowPipelineLayout != null)
			mDevice.DestroyPipelineLayout(ref mShadowPipelineLayout);

		for (int i = 0; i < ShadowPassBufferCount; i++)
		{
			if (mShadowPassBindGroups[i] != null)
				mDevice.DestroyBindGroup(ref mShadowPassBindGroups[i]);
		}

		if (mShadowPassBindGroupLayout != null)
			mDevice.DestroyBindGroupLayout(ref mShadowPassBindGroupLayout);

		for (int i = 0; i < ShadowPassBufferCount; i++)
		{
			if (mShadowPassUniformBuffers[i] != null)
			{
				mShadowPassUniformBuffers[i].Unmap();
				mShadowPassUniformPtrs[i] = null;
				mDevice.DestroyBuffer(ref mShadowPassUniformBuffers[i]);
			}
		}

		// Shadow uniform buffers (per-frame-per-view)
		for (int i = 0; i < RenderConfig.TotalBufferSlots; i++)
		{
			if (mShadowUniformBuffers[i] != null)
			{
				mShadowUniformBuffers[i].Unmap();
				mShadowUniformPtrs[i] = null;
				mDevice.DestroyBuffer(ref mShadowUniformBuffers[i]);
			}
		}

		// Sampler
		if (mShadowSampler != null)
			mDevice.DestroySampler(ref mShadowSampler);

		// Texture views
		if (mCascadeArrayView != null)
			mDevice.DestroyTextureView(ref mCascadeArrayView);
		for (int i = 0; i < RenderConfig.ShadowCascadeCount; i++)
		{
			if (mCascadeLayerViews[i] != null)
				mDevice.DestroyTextureView(ref mCascadeLayerViews[i]);
		}

		// Texture
		if (mCascadeTexture != null)
			mDevice.DestroyTexture(ref mCascadeTexture);
	}
}
