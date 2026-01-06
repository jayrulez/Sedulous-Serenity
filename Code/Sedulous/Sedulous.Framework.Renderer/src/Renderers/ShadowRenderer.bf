namespace Sedulous.Framework.Renderer;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;

/// Shadow pass uniform data for the shadow renderer.
[CRepr]
struct ShadowRendererUniforms
{
	public Matrix LightViewProjection;
	public Vector4 DepthBias;
}

/// Handles shadow map rendering for all mesh types.
/// Owns shadow pipelines, bind groups, and uniform buffers.
class ShadowRenderer
{
	private const int32 MAX_FRAMES = 2;
	private const int32 CASCADE_COUNT = 4;
	private const int32 SHADOW_MAP_SIZE = 2048;

	private IDevice mDevice;
	private ShaderLibrary mShaderLibrary;
	private LightingSystem mLightingSystem;
	private GPUResourceManager mResourceManager;

	// Static shadow pipeline
	private IRenderPipeline mStaticShadowPipeline ~ delete _;
	private IBindGroupLayout mStaticShadowBindGroupLayout ~ delete _;
	private IPipelineLayout mStaticShadowPipelineLayout ~ delete _;

	// Skinned shadow pipeline
	private IRenderPipeline mSkinnedShadowPipeline ~ delete _;
	private IBindGroupLayout mSkinnedShadowBindGroupLayout ~ delete _;
	private IPipelineLayout mSkinnedShadowPipelineLayout ~ delete _;
	private IBuffer mSkinnedShadowObjectBuffer ~ delete _;

	// Per-frame, per-cascade resources
	private IBuffer[MAX_FRAMES][CASCADE_COUNT] mShadowUniformBuffers ~ {
		for (int i = 0; i < MAX_FRAMES; i++)
			for (int c = 0; c < CASCADE_COUNT; c++)
				delete _[i][c];
	};
	private IBindGroup[MAX_FRAMES][CASCADE_COUNT] mStaticShadowBindGroups ~ {
		for (int i = 0; i < MAX_FRAMES; i++)
			for (int c = 0; c < CASCADE_COUNT; c++)
				delete _[i][c];
	};

	// Per-frame temporary bind groups for skinned meshes (cleaned up each frame)
	private List<IBindGroup>[MAX_FRAMES] mTempSkinnedBindGroups = .(new .(), new .()) ~ {
		for (var list in _) DeleteContainerAndItems!(list);
	};

	/// Initializes the shadow renderer.
	public Result<void> Initialize(IDevice device, ShaderLibrary shaderLibrary,
		LightingSystem lightingSystem, GPUResourceManager resourceManager)
	{
		mDevice = device;
		mShaderLibrary = shaderLibrary;
		mLightingSystem = lightingSystem;
		mResourceManager = resourceManager;

		// Create per-frame, per-cascade uniform buffers
		BufferDescriptor shadowDesc = .((uint64)sizeof(ShadowRendererUniforms), .Uniform, .Upload);
		for (int i = 0; i < MAX_FRAMES; i++)
		{
			for (int32 c = 0; c < CASCADE_COUNT; c++)
			{
				if (device.CreateBuffer(&shadowDesc) case .Ok(let buf))
					mShadowUniformBuffers[i][c] = buf;
				else
					return .Err;
			}
		}

		// Create static shadow pipeline
		if (CreateStaticShadowPipeline() case .Err)
			return .Err;

		// Create static shadow bind groups
		for (int i = 0; i < MAX_FRAMES; i++)
		{
			for (int32 c = 0; c < CASCADE_COUNT; c++)
			{
				BindGroupEntry[1] entries = .(
					BindGroupEntry.Buffer(0, mShadowUniformBuffers[i][c])
				);
				BindGroupDescriptor bindGroupDesc = .(mStaticShadowBindGroupLayout, entries);
				if (device.CreateBindGroup(&bindGroupDesc) case .Ok(let group))
					mStaticShadowBindGroups[i][c] = group;
				else
					return .Err;
			}
		}

		// Create skinned shadow pipeline
		if (CreateSkinnedShadowPipeline() case .Err)
			return .Err;

		return .Ok;
	}

	/// Creates the static mesh shadow pipeline.
	private Result<void> CreateStaticShadowPipeline()
	{
		// Load shadow depth shader
		let vertResult = mShaderLibrary.GetShader("shadow_depth_instanced", .Vertex);
		if (vertResult case .Err)
			return .Err;
		let shadowVertShader = vertResult.Get();

		// Shadow bind group layout - just the shadow uniform buffer
		BindGroupLayoutEntry[1] shadowLayoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex)
		);

		BindGroupLayoutDescriptor shadowLayoutDesc = .(shadowLayoutEntries);
		if (mDevice.CreateBindGroupLayout(&shadowLayoutDesc) not case .Ok(let bindLayout))
			return .Err;
		mStaticShadowBindGroupLayout = bindLayout;

		// Shadow pipeline layout
		IBindGroupLayout[1] shadowBindGroupLayouts = .(mStaticShadowBindGroupLayout);
		PipelineLayoutDescriptor shadowPipelineLayoutDesc = .(shadowBindGroupLayouts);
		if (mDevice.CreatePipelineLayout(&shadowPipelineLayoutDesc) not case .Ok(let pipLayout))
			return .Err;
		mStaticShadowPipelineLayout = pipLayout;

		// Vertex layouts - same as main mesh pipeline
		Sedulous.RHI.VertexAttribute[3] meshAttrs = .(
			.(VertexFormat.Float3, 0, 0),   // Position
			.(VertexFormat.Float3, 12, 1),  // Normal
			.(VertexFormat.Float2, 24, 2)   // UV
		);

		Sedulous.RHI.VertexAttribute[5] instanceAttrs = .(
			.(VertexFormat.Float4, 0, 3),   // Row0
			.(VertexFormat.Float4, 16, 4),  // Row1
			.(VertexFormat.Float4, 32, 5),  // Row2
			.(VertexFormat.Float4, 48, 6),  // Row3
			.(VertexFormat.Float4, 64, 7)   // Color/Material
		);

		VertexBufferLayout[2] shadowVertexBuffers = .(
			.(48, meshAttrs, .Vertex),
			.(80, instanceAttrs, .Instance)
		);

		// Shadow depth state with depth bias to reduce shadow acne
		DepthStencilState shadowDepthState = .();
		shadowDepthState.DepthTestEnabled = true;
		shadowDepthState.DepthWriteEnabled = true;
		shadowDepthState.DepthCompare = .Less;
		shadowDepthState.Format = .Depth32Float;
		shadowDepthState.DepthBias = 2;
		shadowDepthState.DepthBiasSlopeScale = 2.0f;

		RenderPipelineDescriptor shadowPipelineDesc = .()
		{
			Layout = mStaticShadowPipelineLayout,
			Vertex = .()
			{
				Shader = .(shadowVertShader.Module, "main"),
				Buffers = shadowVertexBuffers
			},
			Fragment = null,  // Depth-only pass
			Primitive = .()
			{
				Topology = .TriangleList,
				FrontFace = .CCW,
				CullMode = .Front  // Front-face culling reduces shadow acne
			},
			DepthStencil = shadowDepthState,
			Multisample = .()
			{
				Count = 1,
				Mask = uint32.MaxValue
			}
		};

		if (mDevice.CreateRenderPipeline(&shadowPipelineDesc) not case .Ok(let pipeline))
			return .Err;
		mStaticShadowPipeline = pipeline;

		return .Ok;
	}

	/// Creates the skinned mesh shadow pipeline.
	private Result<void> CreateSkinnedShadowPipeline()
	{
		// Load skinned shadow shader
		let vertResult = mShaderLibrary.GetShader("shadow_depth_skinned", .Vertex);
		if (vertResult case .Err)
			return .Err;
		let vertShader = vertResult.Get();

		// Bind group layout: b0=shadow uniforms, b1=object, b2=bones
		BindGroupLayoutEntry[3] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex),  // Shadow pass uniforms
			BindGroupLayoutEntry.UniformBuffer(1, .Vertex),  // Object transform
			BindGroupLayoutEntry.UniformBuffer(2, .Vertex)   // Bone matrices
		);
		BindGroupLayoutDescriptor bindLayoutDesc = .(layoutEntries);
		if (mDevice.CreateBindGroupLayout(&bindLayoutDesc) not case .Ok(let layout))
			return .Err;
		mSkinnedShadowBindGroupLayout = layout;

		// Pipeline layout
		IBindGroupLayout[1] layouts = .(mSkinnedShadowBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (mDevice.CreatePipelineLayout(&pipelineLayoutDesc) not case .Ok(let pipelineLayout))
			return .Err;
		mSkinnedShadowPipelineLayout = pipelineLayout;

		// Create object uniform buffer (64 bytes for Model matrix)
		BufferDescriptor objectDesc = .(64, .Uniform, .Upload);
		if (mDevice.CreateBuffer(&objectDesc) case .Ok(let buf))
			mSkinnedShadowObjectBuffer = buf;
		else
			return .Err;

		// Skinned vertex layout - only attributes needed by shadow shader
		Sedulous.RHI.VertexAttribute[5] vertexAttrs = .(
			.(VertexFormat.Float3, 0, 0),     // Position - location 0
			.(VertexFormat.Float3, 12, 1),    // Normal - location 1
			.(VertexFormat.Float2, 24, 2),    // TexCoord - location 2
			.(VertexFormat.Float4, 56, 3),    // Weights (boneWeights) - location 3
			.(VertexFormat.UShort4, 48, 4)    // Joints (boneIndices) - location 4
		);
		VertexBufferLayout[1] vertexBuffers = .(.(72, vertexAttrs));

		// Shadow depth state with bias
		DepthStencilState depthState = .();
		depthState.DepthTestEnabled = true;
		depthState.DepthWriteEnabled = true;
		depthState.DepthCompare = .Less;
		depthState.Format = .Depth32Float;
		depthState.DepthBias = 2;
		depthState.DepthBiasSlopeScale = 2.0f;

		RenderPipelineDescriptor pipelineDesc = .()
		{
			Layout = mSkinnedShadowPipelineLayout,
			Vertex = .()
			{
				Shader = .(vertShader.Module, "main"),
				Buffers = vertexBuffers
			},
			Fragment = null,  // Depth-only
			Primitive = .()
			{
				Topology = .TriangleList,
				FrontFace = .CCW,
				CullMode = .Front  // Front-face culling for shadow pass
			},
			DepthStencil = depthState,
			Multisample = .()
			{
				Count = 1,
				Mask = uint32.MaxValue
			}
		};

		if (mDevice.CreateRenderPipeline(&pipelineDesc) not case .Ok(let pipeline))
			return .Err;
		mSkinnedShadowPipeline = pipeline;

		return .Ok;
	}

	/// Renders shadows for all cascade levels.
	/// Returns true if shadows were rendered (texture barrier needed).
	public bool RenderShadows(ICommandEncoder encoder, int32 frameIndex,
		StaticMeshRenderer staticRenderer, SkinnedMeshRenderer skinnedRenderer)
	{
		if (mLightingSystem == null || !mLightingSystem.HasDirectionalShadows)
			return false;

		// Check if we have any meshes to render
		let hasStaticMeshes = staticRenderer != null && staticRenderer.MaterialBatches.Count > 0;
		let hasSkinnedMeshes = skinnedRenderer != null && skinnedRenderer.SkinnedMeshCount > 0;

		if (!hasStaticMeshes && !hasSkinnedMeshes)
			return false;

		// Clean up temporary bind groups from this frame slot
		ClearAndDeleteItems!(mTempSkinnedBindGroups[frameIndex]);

		// Render each cascade
		for (int32 cascade = 0; cascade < CASCADE_COUNT; cascade++)
		{
			let cascadeView = mLightingSystem.GetCascadeRenderView(cascade);
			if (cascadeView == null) continue;

			let cascadeData = mLightingSystem.GetCascadeData(cascade);

			// Upload shadow uniforms for this cascade
			var shadowUniforms = ShadowRendererUniforms();
			shadowUniforms.LightViewProjection = cascadeData.ViewProjection;
			shadowUniforms.DepthBias = .(0.001f, 0.002f, 0, 0);
			Span<uint8> shadowSpan = .((uint8*)&shadowUniforms, sizeof(ShadowRendererUniforms));

			let shadowBuffer = mShadowUniformBuffers[frameIndex][cascade];
			if (shadowBuffer != null && mDevice.Queue != null)
				mDevice.Queue.WriteBuffer(shadowBuffer, 0, shadowSpan);

			// Begin shadow render pass for this cascade
			RenderPassDepthStencilAttachment depthAttachment = .()
			{
				View = cascadeView,
				DepthLoadOp = .Clear,
				DepthStoreOp = .Store,
				DepthClearValue = 1.0f,
				StencilLoadOp = .Clear,
				StencilStoreOp = .Discard,
				StencilClearValue = 0
			};

			RenderPassDescriptor passDesc = .();
			passDesc.DepthStencilAttachment = depthAttachment;

			let shadowPass = encoder.BeginRenderPass(&passDesc);
			if (shadowPass == null) continue;

			shadowPass.SetViewport(0, 0, SHADOW_MAP_SIZE, SHADOW_MAP_SIZE, 0, 1);
			shadowPass.SetScissorRect(0, 0, SHADOW_MAP_SIZE, SHADOW_MAP_SIZE);

			// Render static meshes
			if (hasStaticMeshes)
			{
				RenderStaticShadows(shadowPass, staticRenderer, frameIndex, cascade);
			}

			// Render skinned meshes
			if (hasSkinnedMeshes)
			{
				RenderSkinnedShadows(shadowPass, skinnedRenderer, shadowBuffer, frameIndex);
			}

			shadowPass.End();
			delete shadowPass;
		}

		// Transition shadow map from depth attachment to shader read
		if (let shadowMapTexture = mLightingSystem.CascadeShadowMapTexture)
			encoder.TextureBarrier(shadowMapTexture, .DepthStencilAttachment, .ShaderReadOnly);

		return true;
	}

	/// Renders static mesh shadows.
	private void RenderStaticShadows(IRenderPassEncoder shadowPass, StaticMeshRenderer staticRenderer,
		int32 frameIndex, int32 cascade)
	{
		shadowPass.SetPipeline(mStaticShadowPipeline);
		shadowPass.SetBindGroup(0, mStaticShadowBindGroups[frameIndex][cascade]);

		let instanceBuffer = staticRenderer.GetMaterialInstanceBuffer(frameIndex);

		// Draw material meshes to shadow map
		for (let batch in staticRenderer.MaterialBatches)
		{
			DrawStaticShadowBatch(shadowPass, batch.Mesh, instanceBuffer, batch.InstanceOffset, batch.InstanceCount);
		}
	}

	/// Draws a batch of static mesh instances to the shadow map.
	private void DrawStaticShadowBatch(IRenderPassEncoder shadowPass, GPUMeshHandle meshHandle,
		IBuffer instanceBuffer, int32 instanceOffset, int32 instanceCount)
	{
		let gpuMesh = mResourceManager.GetMesh(meshHandle);
		if (gpuMesh == null)
			return;

		shadowPass.SetVertexBuffer(0, gpuMesh.VertexBuffer, 0);
		shadowPass.SetVertexBuffer(1, instanceBuffer, (uint64)(instanceOffset * sizeof(MaterialInstanceData)));

		if (gpuMesh.IndexBuffer != null)
		{
			shadowPass.SetIndexBuffer(gpuMesh.IndexBuffer, gpuMesh.IndexFormat, 0);
			shadowPass.DrawIndexed(gpuMesh.IndexCount, (uint32)instanceCount, 0, 0, 0);
		}
		else
		{
			shadowPass.Draw(gpuMesh.VertexCount, (uint32)instanceCount, 0, 0);
		}
	}

	/// Renders skinned mesh shadows.
	private void RenderSkinnedShadows(IRenderPassEncoder shadowPass, SkinnedMeshRenderer skinnedRenderer,
		IBuffer shadowBuffer, int32 frameIndex)
	{
		shadowPass.SetPipeline(mSkinnedShadowPipeline);

		for (let skinnedComp in skinnedRenderer.SkinnedMeshes)
		{
			if (!skinnedComp.Visible)
				continue;

			let meshHandle = skinnedComp.GPUMeshHandle;
			if (!meshHandle.IsValid)
				continue;

			let gpuMesh = mResourceManager.GetSkinnedMesh(meshHandle);
			if (gpuMesh == null)
				continue;

			let boneBuffer = skinnedComp.BoneMatrixBuffer;
			if (boneBuffer == null)
				continue;

			// Upload model matrix to skinned shadow object buffer
			Matrix modelMatrix = .Identity;
			if (skinnedComp.Entity != null)
				modelMatrix = skinnedComp.Entity.Transform.WorldMatrix;

			Span<uint8> modelSpan = .((uint8*)&modelMatrix, sizeof(Matrix));
			mDevice.Queue.WriteBuffer(mSkinnedShadowObjectBuffer, 0, modelSpan);

			// Create bind group for this skinned mesh shadow render
			BindGroupEntry[3] bindEntries = .(
				BindGroupEntry.Buffer(0, shadowBuffer),              // Shadow uniforms (b0)
				BindGroupEntry.Buffer(1, mSkinnedShadowObjectBuffer), // Object transform (b1)
				BindGroupEntry.Buffer(2, boneBuffer)                  // Bone matrices (b2)
			);
			BindGroupDescriptor bindGroupDesc = .(mSkinnedShadowBindGroupLayout, bindEntries);
			if (mDevice.CreateBindGroup(&bindGroupDesc) case .Ok(let bindGroup))
			{
				// Store for later cleanup
				mTempSkinnedBindGroups[frameIndex].Add(bindGroup);

				shadowPass.SetBindGroup(0, bindGroup);
				shadowPass.SetVertexBuffer(0, gpuMesh.VertexBuffer, 0);

				if (gpuMesh.IndexBuffer != null)
				{
					shadowPass.SetIndexBuffer(gpuMesh.IndexBuffer, gpuMesh.IndexFormat, 0);
					shadowPass.DrawIndexed(gpuMesh.IndexCount, 1, 0, 0, 0);
				}
				else
				{
					shadowPass.Draw(gpuMesh.VertexCount, 1, 0, 0);
				}
			}
		}
	}
}
