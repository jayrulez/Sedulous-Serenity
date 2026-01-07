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

	// Object bind group layout (Group 1: object + bones) - shared across all skinned pipelines
	private IBindGroupLayout mObjectBindGroupLayout ~ delete _;
	private bool mObjectLayoutCreated = false;

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

		// Object bind group layout will be created lazily when needed
		mObjectLayoutCreated = false;

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

	/// Creates the object bind group layout (shared across all skinned pipelines).
	/// Group 1: b1=object uniforms, b2=bone matrices
	private Result<void> EnsureObjectBindGroupLayout()
	{
		if (mObjectLayoutCreated)
			return .Ok;

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

		mObjectLayoutCreated = true;
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

	/// Renders skinned meshes with materials (PBR, Unlit, etc.).
	/// Pipelines are created/cached based on each material's bind group layout.
	private void RenderMaterials(IRenderPassEncoder renderPass, IBindGroup sceneBindGroup, int32 frameIndex)
	{
		if (mMaterialBatches.Count == 0)
			return;

		// Ensure object bind group layout is created
		if (!mObjectLayoutCreated)
		{
			if (EnsureObjectBindGroupLayout() case .Err)
				return;
		}

		if (mObjectBindGroupLayout == null || mPipelineCache == null)
			return;

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

		IRenderPipeline lastPipeline = null;
		MaterialInstanceHandle lastMaterial = .Invalid;

		for (let batch in mMaterialBatches)
		{
			let instance = mMaterialSystem.GetInstance(batch.Material);
			if (instance == null)
				continue;

			let material = instance.BaseMaterial;
			if (material == null)
				continue;

			// Get the material's bind group layout (derived from material parameters)
			let materialLayout = mMaterialSystem.GetOrCreateBindGroupLayout(material);
			if (materialLayout == null)
				continue;

			// Get pipeline from cache (creates if needed based on material type)
			let pipelineKey = PipelineKey(material, VertexLayoutHelper.ComputeHash(vertexBuffers), mColorFormat, mDepthFormat, 1);
			if (mPipelineCache.GetSkinnedMeshPipeline(pipelineKey, vertexBuffers, mSceneBindGroupLayout, mObjectBindGroupLayout, materialLayout) case .Ok(let cached))
			{
				// Switch pipeline if material type changed (different shader/layout)
				if (cached.Pipeline != lastPipeline)
				{
					renderPass.SetPipeline(cached.Pipeline);
					renderPass.SetBindGroup(0, sceneBindGroup);  // Scene resources
					lastPipeline = cached.Pipeline;
				}

				// Switch material bind group if material instance changed
				if (!batch.Material.Equals(lastMaterial))
				{
					if (instance.BindGroup != null)
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
}
