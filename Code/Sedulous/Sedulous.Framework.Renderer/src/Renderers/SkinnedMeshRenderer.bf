namespace Sedulous.Framework.Renderer;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;

/// Skinned object uniforms for per-mesh data.
[CRepr]
struct SkinnedObjectUniforms
{
	public Matrix Model;
	public Vector4 BaseColor;  // Only used by legacy shader
}

/// Draw batch for skinned meshes grouped by material.
struct SkinnedDrawBatch
{
	public MaterialInstanceHandle Material;
	public int32 StartIndex;
	public int32 Count;

	public this(MaterialInstanceHandle material, int32 start, int32 count)
	{
		Material = material;
		StartIndex = start;
		Count = count;
	}
}

/// Handles rendering of skinned meshes with skeletal animation.
/// Supports both legacy rendering (no materials) and PBR material rendering.
class SkinnedMeshRenderer
{
	private const int32 MAX_FRAMES = 2;

	private IDevice mDevice;
	private ShaderLibrary mShaderLibrary;
	private MaterialSystem mMaterialSystem;
	private GPUResourceManager mResourceManager;
	private PipelineCache mPipelineCache;

	// Scene bind group layout (reference, not owned - shared with static meshes)
	private IBindGroupLayout mSceneBindGroupLayout;

	// Legacy pipeline (for skinned meshes without materials)
	private IRenderPipeline mLegacyPipeline ~ delete _;
	private IBindGroupLayout mLegacyBindGroupLayout ~ delete _;
	private IPipelineLayout mLegacyPipelineLayout ~ delete _;
	private IBuffer mLegacyObjectBuffer ~ delete _;
	private ISampler mDefaultSampler ~ delete _;
	private ITexture mWhiteTexture ~ delete _;
	private ITextureView mWhiteTextureView ~ delete _;

	// Material pipeline (for skinned meshes with PBR materials)
	private IRenderPipeline mMaterialPipeline ~ delete _;
	private IBindGroupLayout mObjectBindGroupLayout ~ delete _;  // Group 1: object + bones
	private IPipelineLayout mMaterialPipelineLayout ~ delete _;
	private IBuffer mMaterialObjectBuffer ~ delete _;
	private bool mMaterialPipelineCreated = false;

	// Registered skinned meshes
	private List<SkinnedMeshRendererComponent> mSkinnedMeshes = new .() ~ delete _;

	// Batching
	private List<SkinnedMeshRendererComponent> mLegacyMeshes = new .() ~ delete _;
	private List<SkinnedMeshRendererComponent> mMaterialMeshes = new .() ~ delete _;
	private List<SkinnedDrawBatch> mMaterialBatches = new .() ~ delete _;

	// Per-frame temporary bind groups (for legacy pipeline)
	private List<IBindGroup>[MAX_FRAMES] mTempBindGroups = .(new .(), new .()) ~ {
		for (var list in _) DeleteContainerAndItems!(list);
	};

	// Per-frame temporary object bind groups (for material pipeline)
	private List<IBindGroup>[MAX_FRAMES] mTempObjectBindGroups = .(new .(), new .()) ~ {
		for (var list in _) DeleteContainerAndItems!(list);
	};

	// Pipeline configuration
	private TextureFormat mColorFormat = .BGRA8UnormSrgb;
	private TextureFormat mDepthFormat = .Depth24PlusStencil8;

	/// Gets the number of registered skinned meshes.
	public int32 SkinnedMeshCount => (int32)mSkinnedMeshes.Count;

	/// Gets the list of registered skinned meshes (for shadow rendering).
	public List<SkinnedMeshRendererComponent> SkinnedMeshes => mSkinnedMeshes;

	/// Gets the material batches (for stats).
	public List<SkinnedDrawBatch> MaterialBatches => mMaterialBatches;

	/// Initializes the skinned mesh renderer.
	public Result<void> Initialize(IDevice device, ShaderLibrary shaderLibrary,
		MaterialSystem materialSystem, GPUResourceManager resourceManager, PipelineCache pipelineCache,
		IBindGroupLayout sceneBindGroupLayout, TextureFormat colorFormat, TextureFormat depthFormat)
	{
		mDevice = device;
		mShaderLibrary = shaderLibrary;
		mMaterialSystem = materialSystem;
		mResourceManager = resourceManager;
		mPipelineCache = pipelineCache;
		mSceneBindGroupLayout = sceneBindGroupLayout;
		mColorFormat = colorFormat;
		mDepthFormat = depthFormat;

		// Create legacy pipeline
		if (CreateLegacyPipeline() case .Err)
			return .Err;

		// Try to create material pipeline (may fail if shaders not found - that's ok)
		// Will be created lazily when needed
		mMaterialPipelineCreated = false;

		return .Ok;
	}

	/// Creates the legacy skinned mesh pipeline.
	private Result<void> CreateLegacyPipeline()
	{
		// Load skinned mesh shaders
		let vertResult = mShaderLibrary.GetShader("skinned", .Vertex);
		if (vertResult case .Err)
			return .Err;
		let vertShader = vertResult.Get();

		let fragResult = mShaderLibrary.GetShader("skinned", .Fragment);
		if (fragResult case .Err)
			return .Err;
		let fragShader = fragResult.Get();

		// Bind group layout: b0=camera, b1=object, b2=bones, t0=texture, s0=sampler
		BindGroupLayoutEntry[5] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex | .Fragment),  // Camera
			BindGroupLayoutEntry.UniformBuffer(1, .Vertex | .Fragment),  // Object
			BindGroupLayoutEntry.UniformBuffer(2, .Vertex),              // Bones
			BindGroupLayoutEntry.SampledTexture(0, .Fragment, .Texture2D),
			BindGroupLayoutEntry.Sampler(0, .Fragment)
		);
		BindGroupLayoutDescriptor bindLayoutDesc = .(layoutEntries);
		if (mDevice.CreateBindGroupLayout(&bindLayoutDesc) not case .Ok(let layout))
			return .Err;
		mLegacyBindGroupLayout = layout;

		// Pipeline layout
		IBindGroupLayout[1] layouts = .(mLegacyBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (mDevice.CreatePipelineLayout(&pipelineLayoutDesc) not case .Ok(let pipelineLayout))
			return .Err;
		mLegacyPipelineLayout = pipelineLayout;

		// Create object uniform buffer
		BufferDescriptor objectDesc = .(128, .Uniform, .Upload);
		if (mDevice.CreateBuffer(&objectDesc) case .Ok(let buf))
			mLegacyObjectBuffer = buf;
		else
			return .Err;

		// Create default sampler
		SamplerDescriptor samplerDesc = .();
		samplerDesc.MinFilter = .Linear;
		samplerDesc.MagFilter = .Linear;
		samplerDesc.MipmapFilter = .Linear;
		samplerDesc.AddressModeU = .ClampToEdge;
		samplerDesc.AddressModeV = .ClampToEdge;
		if (mDevice.CreateSampler(&samplerDesc) case .Ok(let sampler))
			mDefaultSampler = sampler;
		else
			return .Err;

		// Create 1x1 white texture fallback
		TextureDescriptor texDesc = .Texture2D(1, 1, .RGBA8Unorm, .Sampled | .CopyDst);
		if (mDevice.CreateTexture(&texDesc) case .Ok(let tex))
		{
			mWhiteTexture = tex;
			uint8[4] white = .(255, 255, 255, 255);
			TextureDataLayout texLayout = .() { Offset = 0, BytesPerRow = 4, RowsPerImage = 1 };
			Extent3D size = .(1, 1, 1);
			Span<uint8> data = .(&white, 4);
			mDevice.Queue.WriteTexture(mWhiteTexture, data, &texLayout, &size, 0, 0);

			TextureViewDescriptor viewDesc = .() { Format = .RGBA8Unorm, Dimension = .Texture2D, MipLevelCount = 1, ArrayLayerCount = 1 };
			if (mDevice.CreateTextureView(mWhiteTexture, &viewDesc) case .Ok(let view))
				mWhiteTextureView = view;
			else
				return .Err;
		}
		else
			return .Err;

		// SkinnedVertex layout: Position(12) + Normal(12) + UV(8) + Color(4) + Tangent(12) + Joints(8) + Weights(16) = 72 bytes
		Sedulous.RHI.VertexAttribute[7] vertexAttrs = .(
			.(VertexFormat.Float3, 0, 0),              // Position
			.(VertexFormat.Float3, 12, 1),             // Normal
			.(VertexFormat.Float2, 24, 2),             // TexCoord
			.(VertexFormat.UByte4Normalized, 32, 3),   // Color
			.(VertexFormat.Float3, 36, 4),             // Tangent
			.(VertexFormat.UShort4, 48, 5),            // Joints
			.(VertexFormat.Float4, 56, 6)              // Weights
		);
		VertexBufferLayout[1] vertexBuffers = .(.(72, vertexAttrs));

		ColorTargetState[1] colorTargets = .(.(mColorFormat));

		DepthStencilState depthState = .();
		depthState.DepthTestEnabled = true;
		depthState.DepthWriteEnabled = true;
		depthState.DepthCompare = .Less;
		depthState.Format = mDepthFormat;

		RenderPipelineDescriptor pipelineDesc = .()
		{
			Layout = mLegacyPipelineLayout,
			Vertex = .()
			{
				Shader = .(vertShader.Module, "main"),
				Buffers = vertexBuffers
			},
			Fragment = .()
			{
				Shader = .(fragShader.Module, "main"),
				Targets = colorTargets
			},
			Primitive = .()
			{
				Topology = .TriangleList,
				FrontFace = .CCW,
				CullMode = .Back
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
		mLegacyPipeline = pipeline;

		return .Ok;
	}

	/// Creates the material-based skinned mesh pipeline.
	/// Uses 3 bind groups: Scene (0), Object+Bones (1), Material (2).
	private Result<void> CreateMaterialPipeline()
	{
		if (mMaterialPipelineCreated)
			return .Ok;

		// Load skinned PBR shaders
		let vertResult = mShaderLibrary.GetShader("skinned_pbr", .Vertex);
		if (vertResult case .Err)
			return .Err;
		let vertShader = vertResult.Get();

		let fragResult = mShaderLibrary.GetShader("skinned_pbr", .Fragment);
		if (fragResult case .Err)
			return .Err;
		let fragShader = fragResult.Get();

		// Object bind group layout (Group 1): b1=object, b2=bones
		BindGroupLayoutEntry[2] objectLayoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(1, .Vertex | .Fragment),  // Object uniforms
			BindGroupLayoutEntry.UniformBuffer(2, .Vertex)               // Bone matrices
		);
		BindGroupLayoutDescriptor objectLayoutDesc = .(objectLayoutEntries);
		if (mDevice.CreateBindGroupLayout(&objectLayoutDesc) not case .Ok(let layout))
			return .Err;
		mObjectBindGroupLayout = layout;

		// Create object uniform buffer for material pipeline
		BufferDescriptor objectDesc = .(128, .Uniform, .Upload);
		if (mDevice.CreateBuffer(&objectDesc) case .Ok(let buf))
			mMaterialObjectBuffer = buf;
		else
			return .Err;

		// Create a default material bind group layout for the standard PBR material
		// This matches the layout expected by skinned_pbr shaders and MaterialSystem
		BindGroupLayoutEntry[7] materialLayoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(1, .Fragment),           // Material uniforms
			BindGroupLayoutEntry.SampledTexture(0, .Fragment, .Texture2D), // Albedo
			BindGroupLayoutEntry.SampledTexture(1, .Fragment, .Texture2D), // Normal
			BindGroupLayoutEntry.SampledTexture(2, .Fragment, .Texture2D), // MetallicRoughness
			BindGroupLayoutEntry.SampledTexture(3, .Fragment, .Texture2D), // AO
			BindGroupLayoutEntry.SampledTexture(4, .Fragment, .Texture2D), // Emissive
			BindGroupLayoutEntry.Sampler(0, .Fragment)                   // Sampler
		);
		BindGroupLayoutDescriptor materialLayoutDesc = .(materialLayoutEntries);
		IBindGroupLayout materialBindGroupLayout = null;
		if (mDevice.CreateBindGroupLayout(&materialLayoutDesc) case .Ok(let matLayout))
			materialBindGroupLayout = matLayout;
		else
			return .Err;
		defer delete materialBindGroupLayout;

		// Create pipeline layout with all 3 bind groups
		IBindGroupLayout[3] layouts = .(mSceneBindGroupLayout, mObjectBindGroupLayout, materialBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (mDevice.CreatePipelineLayout(&pipelineLayoutDesc) not case .Ok(let pipelineLayout))
			return .Err;
		mMaterialPipelineLayout = pipelineLayout;

		// SkinnedVertex layout: Position(12) + Normal(12) + UV(8) + Color(4) + Tangent(12) + Joints(8) + Weights(16) = 72 bytes
		Sedulous.RHI.VertexAttribute[7] vertexAttrs = .(
			.(VertexFormat.Float3, 0, 0),              // Position
			.(VertexFormat.Float3, 12, 1),             // Normal
			.(VertexFormat.Float2, 24, 2),             // TexCoord
			.(VertexFormat.UByte4Normalized, 32, 3),   // Color
			.(VertexFormat.Float3, 36, 4),             // Tangent
			.(VertexFormat.UShort4, 48, 5),            // Joints
			.(VertexFormat.Float4, 56, 6)              // Weights
		);
		VertexBufferLayout[1] vertexBuffers = .(.(72, vertexAttrs));

		ColorTargetState[1] colorTargets = .(.(mColorFormat));

		DepthStencilState depthState = .();
		depthState.DepthTestEnabled = true;
		depthState.DepthWriteEnabled = true;
		depthState.DepthCompare = .Less;
		depthState.Format = mDepthFormat;

		RenderPipelineDescriptor pipelineDesc = .()
		{
			Layout = mMaterialPipelineLayout,
			Vertex = .()
			{
				Shader = .(vertShader.Module, "main"),
				Buffers = vertexBuffers
			},
			Fragment = .()
			{
				Shader = .(fragShader.Module, "main"),
				Targets = colorTargets
			},
			Primitive = .()
			{
				Topology = .TriangleList,
				FrontFace = .CCW,
				CullMode = .Back
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
		mMaterialPipeline = pipeline;

		mMaterialPipelineCreated = true;
		return .Ok;
	}

	/// Registers a skinned mesh component.
	public void Register(SkinnedMeshRendererComponent mesh)
	{
		if (!mSkinnedMeshes.Contains(mesh))
			mSkinnedMeshes.Add(mesh);
	}

	/// Unregisters a skinned mesh component.
	public void Unregister(SkinnedMeshRendererComponent mesh)
	{
		mSkinnedMeshes.Remove(mesh);
	}

	/// Builds batches sorted by material.
	/// Called during OnUpdate after animation updates.
	public void BuildBatches()
	{
		mLegacyMeshes.Clear();
		mMaterialMeshes.Clear();
		mMaterialBatches.Clear();

		// Separate meshes by material status
		for (let mesh in mSkinnedMeshes)
		{
			if (!mesh.Visible || !mesh.GPUMeshHandle.IsValid)
				continue;

			if (mesh.MaterialInstance.IsValid)
				mMaterialMeshes.Add(mesh);
			else
				mLegacyMeshes.Add(mesh);
		}

		// Build material batches (sort by material for efficient rendering)
		if (mMaterialMeshes.Count > 0)
		{
			// Sort by material
			mMaterialMeshes.Sort(scope (a, b) =>
				(int32)a.MaterialInstance.Index - (int32)b.MaterialInstance.Index);

			// Build batches
			MaterialInstanceHandle currentMaterial = .Invalid;
			int32 batchStart = 0;

			for (int32 i = 0; i < mMaterialMeshes.Count; i++)
			{
				let mesh = mMaterialMeshes[i];
				let material = mesh.MaterialInstance;

				if (i > 0 && !material.Equals(currentMaterial))
				{
					mMaterialBatches.Add(.(currentMaterial, batchStart, i - batchStart));
					batchStart = i;
				}

				currentMaterial = material;
			}

			// Final batch
			if (mMaterialMeshes.Count > batchStart)
			{
				mMaterialBatches.Add(.(currentMaterial, batchStart, (int32)mMaterialMeshes.Count - batchStart));
			}
		}
	}

	/// Renders all skinned meshes.
	public void Render(IRenderPassEncoder renderPass, IBuffer cameraBuffer, IBindGroup sceneBindGroup, int32 frameIndex)
	{
		// Clean up temporary bind groups from previous frame
		ClearAndDeleteItems!(mTempBindGroups[frameIndex]);
		ClearAndDeleteItems!(mTempObjectBindGroups[frameIndex]);

		// Render legacy meshes (without materials)
		RenderLegacy(renderPass, cameraBuffer, frameIndex);

		// Render material meshes (with PBR materials)
		RenderMaterials(renderPass, sceneBindGroup, frameIndex);
	}

	/// Renders skinned meshes without materials using the legacy pipeline.
	private void RenderLegacy(IRenderPassEncoder renderPass, IBuffer cameraBuffer, int32 frameIndex)
	{
		if (mLegacyPipeline == null || mLegacyMeshes.Count == 0)
			return;

		renderPass.SetPipeline(mLegacyPipeline);

		for (let skinnedComp in mLegacyMeshes)
		{
			let meshHandle = skinnedComp.GPUMeshHandle;
			let gpuMesh = mResourceManager.GetSkinnedMesh(meshHandle);
			if (gpuMesh == null)
				continue;

			let boneBuffer = skinnedComp.BoneMatrixBuffer;
			if (boneBuffer == null)
				continue;

			// Create bind group for this mesh
			ITextureView textureView = skinnedComp.TextureView;
			if (textureView == null)
				textureView = mWhiteTextureView;

			BindGroupEntry[5] entries = .(
				BindGroupEntry.Buffer(0, cameraBuffer),
				BindGroupEntry.Buffer(1, mLegacyObjectBuffer),
				BindGroupEntry.Buffer(2, boneBuffer),
				BindGroupEntry.Texture(0, textureView),
				BindGroupEntry.Sampler(0, mDefaultSampler)
			);
			BindGroupDescriptor bindGroupDesc = .(mLegacyBindGroupLayout, entries);
			if (mDevice.CreateBindGroup(&bindGroupDesc) case .Ok(let group))
			{
				mTempBindGroups[frameIndex].Add(group);

				// Update object buffer with this mesh's transform
				Matrix modelMatrix = .Identity;
				if (skinnedComp.Entity != null)
					modelMatrix = skinnedComp.Entity.Transform.WorldMatrix;
				Vector4 baseColor = .(1, 1, 1, 1);

				SkinnedObjectUniforms objectData = .() { Model = modelMatrix, BaseColor = baseColor };
				Span<uint8> objSpan = .((uint8*)&objectData, sizeof(SkinnedObjectUniforms));
				mDevice.Queue.WriteBuffer(mLegacyObjectBuffer, 0, objSpan);

				renderPass.SetBindGroup(0, group);
				renderPass.SetVertexBuffer(0, gpuMesh.VertexBuffer, 0);

				if (gpuMesh.IndexBuffer != null)
				{
					renderPass.SetIndexBuffer(gpuMesh.IndexBuffer, gpuMesh.IndexFormat, 0);
					renderPass.DrawIndexed(gpuMesh.IndexCount, 1, 0, 0, 0);
				}
				else
				{
					renderPass.Draw(gpuMesh.VertexCount, 1, 0, 0);
				}
			}
		}
	}

	/// Renders skinned meshes with PBR materials.
	private void RenderMaterials(IRenderPassEncoder renderPass, IBindGroup sceneBindGroup, int32 frameIndex)
	{
		if (mMaterialBatches.Count == 0)
			return;

		// Ensure material pipeline is created
		if (!mMaterialPipelineCreated)
		{
			if (CreateMaterialPipeline() case .Err)
				return;
		}

		if (mMaterialPipeline == null || mObjectBindGroupLayout == null)
			return;

		renderPass.SetPipeline(mMaterialPipeline);
		renderPass.SetBindGroup(0, sceneBindGroup);  // Scene resources

		MaterialInstanceHandle lastMaterial = .Invalid;

		for (let batch in mMaterialBatches)
		{
			// Switch material bind group if material changed
			if (!batch.Material.Equals(lastMaterial))
			{
				let instance = mMaterialSystem.GetInstance(batch.Material);
				if (instance != null && instance.BindGroup != null)
				{
					renderPass.SetBindGroup(2, instance.BindGroup);  // Material resources (group 2)
				}
				lastMaterial = batch.Material;
			}

			// Render all meshes in this batch
			for (int32 i = batch.StartIndex; i < batch.StartIndex + batch.Count; i++)
			{
				let skinnedComp = mMaterialMeshes[i];
				let meshHandle = skinnedComp.GPUMeshHandle;
				let gpuMesh = mResourceManager.GetSkinnedMesh(meshHandle);
				if (gpuMesh == null)
					continue;

				let boneBuffer = skinnedComp.BoneMatrixBuffer;
				if (boneBuffer == null)
					continue;

				// Create object bind group (group 1)
				BindGroupEntry[2] objectEntries = .(
					BindGroupEntry.Buffer(1, mMaterialObjectBuffer),
					BindGroupEntry.Buffer(2, boneBuffer)
				);
				BindGroupDescriptor objectBindGroupDesc = .(mObjectBindGroupLayout, objectEntries);
				if (mDevice.CreateBindGroup(&objectBindGroupDesc) case .Ok(let objectGroup))
				{
					mTempObjectBindGroups[frameIndex].Add(objectGroup);

					// Update object buffer
					Matrix modelMatrix = .Identity;
					if (skinnedComp.Entity != null)
						modelMatrix = skinnedComp.Entity.Transform.WorldMatrix;

					SkinnedObjectUniforms objectData = .() { Model = modelMatrix, BaseColor = .(1, 1, 1, 1) };
					Span<uint8> objSpan = .((uint8*)&objectData, sizeof(SkinnedObjectUniforms));
					mDevice.Queue.WriteBuffer(mMaterialObjectBuffer, 0, objSpan);

					renderPass.SetBindGroup(1, objectGroup);  // Object + Bones (group 1)
					renderPass.SetVertexBuffer(0, gpuMesh.VertexBuffer, 0);

					if (gpuMesh.IndexBuffer != null)
					{
						renderPass.SetIndexBuffer(gpuMesh.IndexBuffer, gpuMesh.IndexFormat, 0);
						renderPass.DrawIndexed(gpuMesh.IndexCount, 1, 0, 0, 0);
					}
					else
					{
						renderPass.Draw(gpuMesh.VertexCount, 1, 0, 0);
					}
				}
			}
		}
	}
}
