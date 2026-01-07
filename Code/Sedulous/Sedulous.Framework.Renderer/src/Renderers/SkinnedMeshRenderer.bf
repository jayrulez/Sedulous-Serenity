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
	public Vector4 Reserved;  // Padding for 128-byte alignment
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

/// Handles rendering of skinned meshes with skeletal animation and PBR materials.
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

	// Default material for skinned meshes without an assigned material
	private MaterialHandle mDefaultMaterialHandle = .Invalid;
	private MaterialInstanceHandle mDefaultMaterial = .Invalid;
	private bool mDefaultMaterialCreated = false;

	// Material pipeline (for skinned meshes with PBR materials)
	private IRenderPipeline mMaterialPipeline ~ delete _;
	private IBindGroupLayout mObjectBindGroupLayout ~ delete _;  // Group 1: object + bones
	private IPipelineLayout mMaterialPipelineLayout ~ delete _;
	// Note: Object uniform buffers are now per-component (SkinnedMeshRendererComponent.ObjectUniformBuffer)
	private bool mMaterialPipelineCreated = false;

	// Registered skinned meshes
	private List<SkinnedMeshRendererComponent> mSkinnedMeshes = new .() ~ delete _;

	// Batching
	private List<SkinnedMeshRendererComponent> mVisibleMeshes = new .() ~ delete _;
	private List<SkinnedDrawBatch> mMaterialBatches = new .() ~ delete _;

	// Per-frame temporary object bind groups (for material pipeline)
	private List<IBindGroup>[MAX_FRAMES] mTempObjectBindGroups = .(new .(), new .()) ~ {
		for (var list in _) DeleteContainerAndItems!(list);
	};

	// Pipeline configuration
	private TextureFormat mColorFormat = .BGRA8UnormSrgb;
	private TextureFormat mDepthFormat = .Depth24PlusStencil8;

	/// Gets the number of registered skinned meshes.
	public int32 SkinnedMeshCount => (int32)mSkinnedMeshes.Count;

	/// Gets the number of visible skinned meshes (after BuildBatches).
	public int32 VisibleMeshCount => (int32)mVisibleMeshes.Count;

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

		// Material pipeline will be created lazily when needed
		mMaterialPipelineCreated = false;

		return .Ok;
	}

	/// Creates the default gray PBR material for skinned meshes without an assigned material.
	private void EnsureDefaultMaterial()
	{
		if (mDefaultMaterialCreated || mMaterialSystem == null)
			return;

		mDefaultMaterialCreated = true;

		// Create and register a standard PBR material
		let pbrMaterial = Material.CreatePBR("DefaultSkinnedPBR");
		mDefaultMaterialHandle = mMaterialSystem.RegisterMaterial(pbrMaterial);
		if (!mDefaultMaterialHandle.IsValid)
			return;

		// Create a gray instance
		mDefaultMaterial = mMaterialSystem.CreateInstance(mDefaultMaterialHandle);
		if (!mDefaultMaterial.IsValid)
			return;

		// Configure as a neutral gray material
		let instance = mMaterialSystem.GetInstance(mDefaultMaterial);
		if (instance != null)
		{
			instance.SetFloat4("baseColor", .(0.5f, 0.5f, 0.5f, 1.0f));  // Medium gray
			instance.SetFloat("metallic", 0.0f);
			instance.SetFloat("roughness", 0.7f);
			instance.SetFloat("ao", 1.0f);
			instance.SetFloat4("emissive", .(0, 0, 0, 1));
			mMaterialSystem.UploadInstance(mDefaultMaterial);
		}
	}

	/// Gets the effective material for a skinned mesh (uses default if none assigned).
	private MaterialInstanceHandle GetEffectiveMaterial(SkinnedMeshRendererComponent mesh)
	{
		if (mesh.MaterialInstance.IsValid)
			return mesh.MaterialInstance;
		return mDefaultMaterial;
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
		// Note: Object uniform buffers are per-component to support multiple skinned meshes
		BindGroupLayoutEntry[2] objectLayoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(1, .Vertex | .Fragment),  // Object uniforms (per-component)
			BindGroupLayoutEntry.UniformBuffer(2, .Vertex)               // Bone matrices (per-component)
		);
		BindGroupLayoutDescriptor objectLayoutDesc = .(objectLayoutEntries);
		if (mDevice.CreateBindGroupLayout(&objectLayoutDesc) not case .Ok(let layout))
			return .Err;
		mObjectBindGroupLayout = layout;

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
		mVisibleMeshes.Clear();
		mMaterialBatches.Clear();

		// Ensure default material exists for meshes without assigned materials
		EnsureDefaultMaterial();

		// Collect visible meshes (with or without valid materials)
		for (let mesh in mSkinnedMeshes)
		{
			if (!mesh.Visible || !mesh.GPUMeshHandle.IsValid)
				continue;

			// Include mesh if it has a valid material OR we have a default material
			if (mesh.MaterialInstance.IsValid || mDefaultMaterial.IsValid)
				mVisibleMeshes.Add(mesh);
		}

		// Build material batches (sort by material for efficient rendering)
		if (mVisibleMeshes.Count > 0)
		{
			// Sort by effective material
			mVisibleMeshes.Sort(scope (a, b) =>
			{
				let matA = GetEffectiveMaterial(a);
				let matB = GetEffectiveMaterial(b);
				return (int32)matA.Index - (int32)matB.Index;
			});

			// Build batches
			MaterialInstanceHandle currentMaterial = .Invalid;
			int32 batchStart = 0;

			for (int32 i = 0; i < mVisibleMeshes.Count; i++)
			{
				let mesh = mVisibleMeshes[i];
				let material = GetEffectiveMaterial(mesh);

				if (i > 0 && !material.Equals(currentMaterial))
				{
					mMaterialBatches.Add(.(currentMaterial, batchStart, i - batchStart));
					batchStart = i;
				}

				currentMaterial = material;
			}

			// Final batch
			if (mVisibleMeshes.Count > batchStart)
			{
				mMaterialBatches.Add(.(currentMaterial, batchStart, (int32)mVisibleMeshes.Count - batchStart));
			}
		}
	}

	/// Renders all skinned meshes.
	public void Render(IRenderPassEncoder renderPass, IBuffer cameraBuffer, IBindGroup sceneBindGroup, int32 frameIndex)
	{
		// Clean up temporary object bind groups from previous frame
		ClearAndDeleteItems!(mTempObjectBindGroups[frameIndex]);

		// Render material meshes (with PBR materials)
		RenderMaterials(renderPass, sceneBindGroup, frameIndex);
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
				let skinnedComp = mVisibleMeshes[i];
				let meshHandle = skinnedComp.GPUMeshHandle;
				let gpuMesh = mResourceManager.GetSkinnedMesh(meshHandle);
				if (gpuMesh == null)
					continue;

				let boneBuffer = skinnedComp.BoneMatrixBuffer;
				if (boneBuffer == null)
					continue;

				// Use per-component object buffer to avoid shared buffer issues
				let objectBuffer = skinnedComp.ObjectUniformBuffer;
				if (objectBuffer == null)
					continue;

				// Create object bind group (group 1) using per-component buffer
				BindGroupEntry[2] objectEntries = .(
					BindGroupEntry.Buffer(1, objectBuffer),  // Per-component object buffer
					BindGroupEntry.Buffer(2, boneBuffer)
				);
				BindGroupDescriptor objectBindGroupDesc = .(mObjectBindGroupLayout, objectEntries);
				if (mDevice.CreateBindGroup(&objectBindGroupDesc) case .Ok(let objectGroup))
				{
					mTempObjectBindGroups[frameIndex].Add(objectGroup);

					// Update per-component object buffer with this mesh's transform
					Matrix modelMatrix = .Identity;
					if (skinnedComp.Entity != null)
						modelMatrix = skinnedComp.Entity.Transform.WorldMatrix;

					SkinnedObjectUniforms objectData = .() { Model = modelMatrix, Reserved = .(0, 0, 0, 0) };
					Span<uint8> objSpan = .((uint8*)&objectData, sizeof(SkinnedObjectUniforms));
					mDevice.Queue.WriteBuffer(objectBuffer, 0, objSpan);  // Write to per-component buffer

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
