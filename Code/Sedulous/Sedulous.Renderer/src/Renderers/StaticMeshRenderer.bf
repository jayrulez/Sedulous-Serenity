namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Shaders;
using Sedulous.Mathematics;

/// Handles rendering of static meshes using the material system.
/// Manages instance buffers and batch building for efficient draw call batching.
class StaticMeshRenderer
{
	private const int32 MAX_INSTANCES = 4096;

	private IDevice mDevice;
	private ShaderLibrary mShaderLibrary;
	private GPUResourceManager mResourceManager;
	private MaterialSystem mMaterialSystem;
	private PipelineCache mPipelineCache;

	private IBindGroupLayout mSceneBindGroupLayout;  // Reference, not owned

	// Default material for meshes without an assigned material
	private MaterialHandle mDefaultMaterialHandle = .Invalid;
	private MaterialInstanceHandle mDefaultMaterial = .Invalid;
	private bool mDefaultMaterialCreated = false;

	// Per-frame instance buffers
	private IBuffer[FrameConfig.MAX_FRAMES_IN_FLIGHT] mMaterialInstanceBuffers ~ { for (var buf in _) delete buf; };

	// CPU-side instance data
	private MaterialInstanceData[] mMaterialInstanceData ~ delete _;
	private int32 mMaterialInstanceCount = 0;

	// Visible mesh count (set during BuildBatches)
	private int32 mVisibleMeshCount = 0;

	// Draw batches (built from visible meshes)
	private List<DrawBatch> mMaterialBatches = new .() ~ delete _;

	// Pipeline configuration
	private TextureFormat mColorFormat = .BGRA8UnormSrgb;
	private TextureFormat mDepthFormat = .Depth24PlusStencil8;

	// Initialization flag
	private bool mInitialized = false;

	/// Gets the material instance count (for shadow rendering).
	public int32 MaterialInstanceCount => mMaterialInstanceCount;

	/// Gets the number of visible meshes (after BuildBatches).
	public int32 VisibleMeshCount => mVisibleMeshCount;

	/// Gets the material batches (for shadow rendering and stats).
	public List<DrawBatch> MaterialBatches => mMaterialBatches;

	/// Gets the material instance buffer for a frame (for shadow rendering).
	public IBuffer GetMaterialInstanceBuffer(int32 frameIndex) => mMaterialInstanceBuffers[frameIndex];

	/// Initializes the static mesh renderer.
	public Result<void> Initialize(IDevice device, ShaderLibrary shaderLibrary,
		GPUResourceManager resourceManager, MaterialSystem materialSystem, PipelineCache pipelineCache,
		IBindGroupLayout sceneBindGroupLayout, TextureFormat colorFormat, TextureFormat depthFormat)
	{
		mDevice = device;
		mShaderLibrary = shaderLibrary;
		mResourceManager = resourceManager;
		mMaterialSystem = materialSystem;
		mPipelineCache = pipelineCache;
		mSceneBindGroupLayout = sceneBindGroupLayout;
		mColorFormat = colorFormat;
		mDepthFormat = depthFormat;

		// Allocate instance data array
		mMaterialInstanceData = new MaterialInstanceData[MAX_INSTANCES];

		// Create per-frame instance buffers
		for (int i = 0; i < FrameConfig.MAX_FRAMES_IN_FLIGHT; i++)
		{
			uint64 bufferSize = (uint64)(sizeof(MaterialInstanceData) * MAX_INSTANCES);
			BufferDescriptor bufferDesc = .(bufferSize, .Vertex, .Upload);
			if (device.CreateBuffer(&bufferDesc) case .Ok(let buffer))
				mMaterialInstanceBuffers[i] = buffer;
			else
				return .Err;
		}

		return .Ok;
	}

	/// Creates the default gray PBR material for meshes without an assigned material.
	private void EnsureDefaultMaterial()
	{
		if (mDefaultMaterialCreated || mMaterialSystem == null)
			return;

		mDefaultMaterialCreated = true;

		// Create and register a standard PBR material
		let pbrMaterial = Material.CreatePBR("DefaultPBR");
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

	/// Builds instance data and batches from visible meshes.
	/// Called during OnUpdate after visibility determination.
	public void BuildBatches(List<StaticMeshProxy*> visibleMeshes)
	{
		mMaterialInstanceCount = 0;
		mMaterialBatches.Clear();
		mVisibleMeshCount = (int32)visibleMeshes.Count;

		// Ensure default material exists for meshes without assigned materials
		EnsureDefaultMaterial();

		// Build material batches from all visible meshes
		if (visibleMeshes.Count > 0)
		{
			BuildMaterialBatches(visibleMeshes);
		}
	}

	/// Gets the effective material for a mesh proxy (uses default if none assigned).
	private MaterialInstanceHandle GetEffectiveMaterial(StaticMeshProxy* proxy)
	{
		if (proxy.UsesMaterialInstances && proxy.MaterialInstances[0].IsValid)
			return proxy.MaterialInstances[0];
		return mDefaultMaterial;
	}

	/// Builds draw batches from meshes, sorted by (mesh, material).
	/// Uses default material for meshes without an assigned material.
	private void BuildMaterialBatches(List<StaticMeshProxy*> meshes)
	{
		if (meshes.Count == 0)
			return;

		// Create working list (may filter if no default material)
		List<StaticMeshProxy*> workingMeshes = scope .();

		// Skip if no default material available (shouldn't render meshes without materials)
		if (!mDefaultMaterial.IsValid)
		{
			// Filter to only meshes with valid materials
			for (let proxy in meshes)
			{
				if (proxy.UsesMaterialInstances && proxy.MaterialInstances[0].IsValid)
					workingMeshes.Add(proxy);
			}
		}
		else
		{
			// Use all meshes (default material fills in for missing materials)
			for (let proxy in meshes)
				workingMeshes.Add(proxy);
		}

		if (workingMeshes.Count == 0)
			return;

		// Sort by mesh handle then material handle for batching efficiency
		workingMeshes.Sort(scope (a, b) =>
		{
			// First compare mesh handles
			let meshCmp = (int32)a.MeshHandle.Index - (int32)b.MeshHandle.Index;
			if (meshCmp != 0)
				return meshCmp;
			// Then compare material handles (using effective material)
			let matA = GetEffectiveMaterial(a);
			let matB = GetEffectiveMaterial(b);
			return (int32)matA.Index - (int32)matB.Index;
		});

		// Build batches
		GPUStaticMeshHandle currentMesh = .Invalid;
		MaterialInstanceHandle currentMaterial = .Invalid;
		int32 batchStart = 0;

		for (int32 i = 0; i < workingMeshes.Count; i++)
		{
			if (mMaterialInstanceCount >= MAX_INSTANCES)
				break;

			let proxy = workingMeshes[i];
			let meshHandle = proxy.MeshHandle;
			let materialHandle = GetEffectiveMaterial(proxy);

			// Check if we need to start a new batch
			if (i > 0 && (!meshHandle.Equals(currentMesh) || !materialHandle.Equals(currentMaterial)))
			{
				// Finish previous batch
				mMaterialBatches.Add(.(currentMesh, currentMaterial, batchStart, mMaterialInstanceCount - batchStart));
				batchStart = mMaterialInstanceCount;
			}

			// Add instance data
			mMaterialInstanceData[mMaterialInstanceCount] = .(proxy.Transform, .(1, 1, 1));  // Default white tint
			mMaterialInstanceCount++;

			currentMesh = meshHandle;
			currentMaterial = materialHandle;
		}

		// Finish final batch
		if (mMaterialInstanceCount > batchStart)
		{
			mMaterialBatches.Add(.(currentMesh, currentMaterial, batchStart, mMaterialInstanceCount - batchStart));
		}
	}

	/// Uploads instance data to GPU buffers.
	/// Called during PrepareGPU after the fence wait.
	public void PrepareGPU(int32 frameIndex)
	{
		if (mDevice?.Queue == null || frameIndex < 0 || frameIndex >= FrameConfig.MAX_FRAMES_IN_FLIGHT)
			return;

		// Upload material instance data
		if (mMaterialInstanceCount > 0 && mMaterialInstanceBuffers[frameIndex] != null)
		{
			uint64 dataSize = (uint64)(sizeof(MaterialInstanceData) * mMaterialInstanceCount);
			Span<uint8> data = .((uint8*)mMaterialInstanceData.Ptr, (int)dataSize);
			var buf = mMaterialInstanceBuffers[frameIndex];// beef bug
			mDevice.Queue.WriteBuffer(buf, 0, data);
		}
	}

	/// Renders meshes with materials (PBR/custom).
	public void RenderMaterials(IRenderPassEncoder renderPass, IBindGroup sceneBindGroup, int32 frameIndex)
	{
		if (mMaterialBatches.Count == 0)
			return;

		if (mPipelineCache == null || mMaterialSystem == null)
			return;

		let instanceBuffer = mMaterialInstanceBuffers[frameIndex];

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

			// Get the material's bind group layout
			let materialLayout = mMaterialSystem.GetOrCreateBindGroupLayout(material);
			if (materialLayout == null)
				continue;

			// Build vertex buffer layouts for pipeline creation
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
				.(VertexFormat.Float4, 64, 7)   // TintAndFlags
			);
			VertexBufferLayout[2] vertexBuffers = .(
				.(48, meshAttrs, .Vertex),
				.(80, instanceAttrs, .Instance)
			);

			// Get pipeline from cache (creates if needed)
			let pipelineKey = PipelineKey(material, VertexLayoutHelper.ComputeHash(vertexBuffers), mColorFormat, mDepthFormat, 1);
			if (mPipelineCache.GetMaterialPipeline(pipelineKey, vertexBuffers, mSceneBindGroupLayout, materialLayout) case .Ok(let cached))
			{
				// Switch pipeline if shader changed
				if (cached.Pipeline != lastPipeline)
				{
					renderPass.SetPipeline(cached.Pipeline);
					renderPass.SetBindGroup(0, sceneBindGroup);  // Scene resources (shared)
					lastPipeline = cached.Pipeline;
				}

				// Switch material bind group if material changed
				if (!batch.Material.Equals(lastMaterial))
				{
					// Ensure bind group is created/updated
					if (instance.BindGroup == null)
					{
						mMaterialSystem.UploadInstance(batch.Material);
					}

					if (instance.BindGroup != null)
					{
						renderPass.SetBindGroup(1, instance.BindGroup);  // Material resources
					}
					lastMaterial = batch.Material;
				}

				// Draw batch
				let gpuMesh = mResourceManager.GetStaticMesh(batch.Mesh);
				if (gpuMesh != null)
				{
					renderPass.SetVertexBuffer(0, gpuMesh.VertexBuffer, 0);
					renderPass.SetVertexBuffer(1, instanceBuffer,
						(uint64)(batch.InstanceOffset * sizeof(MaterialInstanceData)));

					if (gpuMesh.IndexBuffer != null)
					{
						renderPass.SetIndexBuffer(gpuMesh.IndexBuffer, gpuMesh.IndexFormat, 0);
						renderPass.DrawIndexed(gpuMesh.IndexCount, (uint32)batch.InstanceCount, 0, 0, 0);
					}
					else
					{
						renderPass.Draw(gpuMesh.VertexCount, (uint32)batch.InstanceCount, 0, 0);
					}
				}
			}
		}
	}
}
