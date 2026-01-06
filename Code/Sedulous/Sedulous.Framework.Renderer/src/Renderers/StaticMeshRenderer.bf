namespace Sedulous.Framework.Renderer;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;

/// Handles rendering of static meshes (both legacy and material-based paths).
/// Manages instance buffers and batch building for efficient draw call batching.
class StaticMeshRenderer
{
	private const int32 MAX_FRAMES = 2;
	private const int32 MAX_INSTANCES = 4096;

	private IDevice mDevice;
	private ShaderLibrary mShaderLibrary;
	private GPUResourceManager mResourceManager;
	private MaterialSystem mMaterialSystem;
	private PipelineCache mPipelineCache;

	// Legacy pipeline (scene_lit shader for meshes without materials)
	private IRenderPipeline mLegacyPipeline ~ delete _;
	private IBindGroupLayout mSceneBindGroupLayout;  // Reference, not owned
	private IPipelineLayout mLegacyPipelineLayout ~ delete _;

	// Per-frame instance buffers
	private IBuffer[MAX_FRAMES] mLegacyInstanceBuffers ~ { for (var buf in _) delete buf; };
	private IBuffer[MAX_FRAMES] mMaterialInstanceBuffers ~ { for (var buf in _) delete buf; };

	// CPU-side instance data
	private RenderSceneInstanceData[] mLegacyInstanceData ~ delete _;
	private MaterialInstanceData[] mMaterialInstanceData ~ delete _;
	private int32 mLegacyInstanceCount = 0;
	private int32 mMaterialInstanceCount = 0;

	// Visible mesh lists (built by RenderSceneComponent, used here)
	private List<MeshProxy*> mLegacyMeshes = new .() ~ delete _;
	private List<DrawBatch> mMaterialBatches = new .() ~ delete _;

	// Pipeline configuration
	private TextureFormat mColorFormat = .BGRA8UnormSrgb;
	private TextureFormat mDepthFormat = .Depth24PlusStencil8;

	// Initialization flag
	private bool mInitialized = false;

	/// Gets the legacy instance count (for shadow rendering).
	public int32 LegacyInstanceCount => mLegacyInstanceCount;

	/// Gets the material instance count (for shadow rendering).
	public int32 MaterialInstanceCount => mMaterialInstanceCount;

	/// Gets the legacy mesh list (for shadow rendering).
	public List<MeshProxy*> LegacyMeshes => mLegacyMeshes;

	/// Gets the material batches (for shadow rendering and stats).
	public List<DrawBatch> MaterialBatches => mMaterialBatches;

	/// Gets the legacy instance buffer for a frame (for shadow rendering).
	public IBuffer GetLegacyInstanceBuffer(int32 frameIndex) => mLegacyInstanceBuffers[frameIndex];

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

		// Allocate instance data arrays
		mLegacyInstanceData = new RenderSceneInstanceData[MAX_INSTANCES];
		mMaterialInstanceData = new MaterialInstanceData[MAX_INSTANCES];

		// Create per-frame buffers
		for (int i = 0; i < MAX_FRAMES; i++)
		{
			// Legacy instance buffer
			uint64 legacyBufferSize = (uint64)(sizeof(RenderSceneInstanceData) * MAX_INSTANCES);
			BufferDescriptor legacyDesc = .(legacyBufferSize, .Vertex, .Upload);
			if (device.CreateBuffer(&legacyDesc) case .Ok(let legacyBuf))
				mLegacyInstanceBuffers[i] = legacyBuf;
			else
				return .Err;

			// Material instance buffer
			uint64 materialBufferSize = (uint64)(sizeof(MaterialInstanceData) * MAX_INSTANCES);
			BufferDescriptor materialDesc = .(materialBufferSize, .Vertex, .Upload);
			if (device.CreateBuffer(&materialDesc) case .Ok(let materialBuf))
				mMaterialInstanceBuffers[i] = materialBuf;
			else
				return .Err;
		}

		// Create legacy pipeline
		if (CreateLegacyPipeline() case .Err)
			return .Err;

		return .Ok;
	}

	/// Creates the legacy pipeline (scene_lit shader).
	private Result<void> CreateLegacyPipeline()
	{
		// Load lit shaders with lighting and shadow support
		let vertResult = mShaderLibrary.GetShader("scene_lit", .Vertex);
		if (vertResult case .Err)
			return .Err;
		let vertShader = vertResult.Get();

		let fragResult = mShaderLibrary.GetShader("scene_lit", .Fragment);
		if (fragResult case .Err)
			return .Err;
		let fragShader = fragResult.Get();

		// Pipeline layout with scene bind group only
		IBindGroupLayout[1] layouts = .(mSceneBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (mDevice.CreatePipelineLayout(&pipelineLayoutDesc) not case .Ok(let pipelineLayout))
			return .Err;
		mLegacyPipelineLayout = pipelineLayout;

		// Vertex layouts - mesh attributes
		Sedulous.RHI.VertexAttribute[3] meshAttrs = .(
			.(VertexFormat.Float3, 0, 0),   // Position
			.(VertexFormat.Float3, 12, 1),  // Normal
			.(VertexFormat.Float2, 24, 2)   // UV
		);

		// Instance attributes
		Sedulous.RHI.VertexAttribute[5] instanceAttrs = .(
			.(VertexFormat.Float4, 0, 3),   // Row0
			.(VertexFormat.Float4, 16, 4),  // Row1
			.(VertexFormat.Float4, 32, 5),  // Row2
			.(VertexFormat.Float4, 48, 6),  // Row3
			.(VertexFormat.Float4, 64, 7)   // Color
		);

		VertexBufferLayout[2] vertexBuffers = .(
			.(48, meshAttrs, .Vertex),
			.(80, instanceAttrs, .Instance)
		);

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

	/// Builds instance data and batches from visible meshes.
	/// Called during OnUpdate after visibility determination.
	public void BuildBatches(List<MeshProxy*> visibleMeshes)
	{
		mLegacyInstanceCount = 0;
		mMaterialInstanceCount = 0;
		mMaterialBatches.Clear();
		mLegacyMeshes.Clear();

		// First pass: separate material meshes from legacy meshes
		List<MeshProxy*> materialMeshes = scope .();

		for (let proxy in visibleMeshes)
		{
			if (proxy.UsesMaterialInstances)
				materialMeshes.Add(proxy);
			else
				mLegacyMeshes.Add(proxy);
		}

		// Build legacy instance data
		for (let proxy in mLegacyMeshes)
		{
			if (mLegacyInstanceCount >= MAX_INSTANCES)
				break;

			let color = GetColorForMaterial(proxy.GetMaterial(0));
			mLegacyInstanceData[mLegacyInstanceCount] = .(proxy.Transform, color);
			mLegacyInstanceCount++;
		}

		// Build material batches
		if (materialMeshes.Count > 0)
		{
			BuildMaterialBatches(materialMeshes);
		}
	}

	/// Builds draw batches from material meshes, sorted by (mesh, material).
	private void BuildMaterialBatches(List<MeshProxy*> meshes)
	{
		if (meshes.Count == 0)
			return;

		// Sort by mesh handle then material handle for batching efficiency
		meshes.Sort(scope (a, b) =>
		{
			// First compare mesh handles
			let meshCmp = (int32)a.MeshHandle.Index - (int32)b.MeshHandle.Index;
			if (meshCmp != 0)
				return meshCmp;
			// Then compare material handles
			return (int32)a.MaterialInstances[0].Index - (int32)b.MaterialInstances[0].Index;
		});

		// Build batches
		GPUMeshHandle currentMesh = .Invalid;
		MaterialInstanceHandle currentMaterial = .Invalid;
		int32 batchStart = 0;

		for (int32 i = 0; i < meshes.Count; i++)
		{
			if (mMaterialInstanceCount >= MAX_INSTANCES)
				break;

			let proxy = meshes[i];
			let meshHandle = proxy.MeshHandle;
			let materialHandle = proxy.MaterialInstances[0];

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

	/// Helper to get a color for legacy material rendering.
	private Vector4 GetColorForMaterial(uint32 materialId)
	{
		// Simple color palette based on material ID
		switch (materialId % 8)
		{
		case 0: return .(0.9f, 0.3f, 0.3f, 1.0f);  // Red
		case 1: return .(0.3f, 0.9f, 0.3f, 1.0f);  // Green
		case 2: return .(0.3f, 0.3f, 0.9f, 1.0f);  // Blue
		case 3: return .(0.9f, 0.9f, 0.3f, 1.0f);  // Yellow
		case 4: return .(0.9f, 0.3f, 0.9f, 1.0f);  // Magenta
		case 5: return .(0.3f, 0.9f, 0.9f, 1.0f);  // Cyan
		case 6: return .(0.9f, 0.6f, 0.3f, 1.0f);  // Orange
		case 7: return .(0.7f, 0.7f, 0.7f, 1.0f);  // Gray
		default: return .(1.0f, 1.0f, 1.0f, 1.0f);
		}
	}

	/// Uploads instance data to GPU buffers.
	/// Called during PrepareGPU after the fence wait.
	public void PrepareGPU(int32 frameIndex)
	{
		if (mDevice?.Queue == null || frameIndex < 0 || frameIndex >= MAX_FRAMES)
			return;

		// Upload legacy instance data
		if (mLegacyInstanceCount > 0 && mLegacyInstanceBuffers[frameIndex] != null)
		{
			uint64 dataSize = (uint64)(sizeof(RenderSceneInstanceData) * mLegacyInstanceCount);
			Span<uint8> data = .((uint8*)mLegacyInstanceData.Ptr, (int)dataSize);
			var buf = mLegacyInstanceBuffers[frameIndex];// beef bug
			mDevice.Queue.WriteBuffer(buf, 0, data);
		}

		// Upload material instance data
		if (mMaterialInstanceCount > 0 && mMaterialInstanceBuffers[frameIndex] != null)
		{
			uint64 dataSize = (uint64)(sizeof(MaterialInstanceData) * mMaterialInstanceCount);
			Span<uint8> data = .((uint8*)mMaterialInstanceData.Ptr, (int)dataSize);
			var buf = mMaterialInstanceBuffers[frameIndex];// beef bug
			mDevice.Queue.WriteBuffer(buf, 0, data);
		}
	}

	/// Renders legacy meshes (without MaterialInstance).
	public void RenderLegacy(IRenderPassEncoder renderPass, IBindGroup sceneBindGroup, int32 frameIndex)
	{
		if (mLegacyInstanceCount == 0)
			return;

		renderPass.SetPipeline(mLegacyPipeline);
		renderPass.SetBindGroup(0, sceneBindGroup);

		// Draw all legacy visible meshes using their GPU mesh
		int32 instanceOffset = 0;
		GPUMeshHandle lastMesh = .Invalid;
		let instanceBuffer = mLegacyInstanceBuffers[frameIndex];

		for (int32 i = 0; i < mLegacyInstanceCount; i++)
		{
			let proxy = mLegacyMeshes[i];
			let meshHandle = proxy.MeshHandle;

			// When mesh changes, draw the batch
			if (i > 0 && !meshHandle.Equals(lastMesh))
			{
				DrawMeshBatch(renderPass, lastMesh, instanceBuffer, instanceOffset, i - instanceOffset);
				instanceOffset = i;
			}

			lastMesh = meshHandle;
		}

		// Draw final batch
		if (mLegacyInstanceCount > instanceOffset)
		{
			DrawMeshBatch(renderPass, lastMesh, instanceBuffer, instanceOffset, mLegacyInstanceCount - instanceOffset);
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
				let gpuMesh = mResourceManager.GetMesh(batch.Mesh);
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

	/// Draws a batch of mesh instances.
	private void DrawMeshBatch(IRenderPassEncoder renderPass, GPUMeshHandle meshHandle,
		IBuffer instanceBuffer, int32 instanceOffset, int32 instanceCount)
	{
		let gpuMesh = mResourceManager.GetMesh(meshHandle);
		if (gpuMesh == null)
			return;

		renderPass.SetVertexBuffer(0, gpuMesh.VertexBuffer, 0);
		renderPass.SetVertexBuffer(1, instanceBuffer, (uint64)(instanceOffset * sizeof(RenderSceneInstanceData)));

		if (gpuMesh.IndexBuffer != null)
		{
			renderPass.SetIndexBuffer(gpuMesh.IndexBuffer, gpuMesh.IndexFormat, 0);
			renderPass.DrawIndexed(gpuMesh.IndexCount, (uint32)instanceCount, 0, 0, 0);
		}
		else
		{
			renderPass.Draw(gpuMesh.VertexCount, (uint32)instanceCount, 0, 0);
		}
	}
}
