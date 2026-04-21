namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Core.Mathematics;
using Sedulous.Shaders;
using Sedulous.RenderGraph;

/// GPU compute skinning system.
/// Owned by RenderSystem as infrastructure, not a render feature.
/// Uses compute shaders to transform vertices by bone matrices.
public class SkinningSystem
{
	private RenderSystem mRenderer;
	private IDevice mDevice;
	private bool mInitialized;

	// Compute pipeline
	private IComputePipeline mSkinningPipeline;
	private IBindGroupLayout mSkinningBindGroupLayout;
	private IPipelineLayout mPipelineLayout;

	// Per-mesh skinning data (keyed by source id + handle to support multiple producers)
	private Dictionary<SkinningInstanceKey, SkinningInstance> mSkinningInstances = new .() ~ {
		for (let kv in _) delete kv.value;
		delete _;
	};

	public bool IsInitialized => mInitialized;

	/// Initialize the skinning system
	public Result<void> Initialize(RenderSystem renderer)
	{
		mRenderer = renderer;
		mDevice = renderer.Device;

		if (CreateSkinningPipeline() case .Err)
			return .Err;

		mInitialized = true;
		return .Ok;
	}

	/// Gets the skinned (transformed) vertex buffer for a skinned mesh.
	/// This buffer contains the post-skinning vertices ready for rendering.
	/// Returns null if no skinning instance exists for this mesh.
	///
	/// Uses the current frame's RenderableList source id to scope the lookup.
	public IBuffer GetSkinnedVertexBuffer(SkinnedMeshRenderHandle handle)
	{
		let key = SkinningInstanceKey() { SourceId = mRenderer?.FrameRenderables?.SourceId ?? 0, Handle = handle };
		if (mSkinningInstances.TryGetValue(key, let instance))
			return instance.SkinnedVertexBuffer;
		return null;
	}

	/// Gets the vertex count for a skinned mesh instance.
	public int32 GetSkinnedVertexCount(SkinnedMeshRenderHandle handle)
	{
		let key = SkinningInstanceKey() { SourceId = mRenderer?.FrameRenderables?.SourceId ?? 0, Handle = handle };
		if (mSkinningInstances.TryGetValue(key, let instance))
			return instance.VertexCount;
		return 0;
	}

	/// Add skinning compute pass to the render graph.
	public void AddPasses(RenderGraph graph, ViewContext view, RenderableList renderables)
	{
		if (!mInitialized || mSkinningPipeline == null)
			return;

		if (renderables.SkinnedMeshes.Count == 0)
			return;

		// Collect visible skinned mesh (index, handle) pairs for the lambda.
		// Heap-allocated so it survives to render-pass execute time.
		List<(int32 Index, SkinnedMeshRenderHandle Handle)> meshList = new .();
		for (int32 i = 0; i < (int32)renderables.SkinnedMeshes.Count; i++)
		{
			let mesh = ref renderables.SkinnedMeshes[i];
			if ((mesh.Flags & .Visible) != 0)
				meshList.Add((i, mesh.SkinnedMeshHandle));
		}

		if (meshList.Count == 0)
		{
			delete meshList;
			return;
		}

		let sourceId = renderables.SourceId;
		let renderablesRef = renderables;

		graph.AddComputePass("GPUSkinning", scope (builder) => {
				builder.NeverCull();
				builder.SetComputeExecute(new (encoder) => {
					ExecuteSkinningPass(encoder, renderablesRef, sourceId, meshList);
					delete meshList;
				});
			});
	}

	private Result<void> CreateSkinningPipeline()
	{
		// Create bind group layout matching skinning.comp.hlsl:
		// b0: SkinningParams (uniform)
		// t0: BoneMatrices (StructuredBuffer<float4x4>)
		// t1: SourceVertices (ByteAddressBuffer - 72 bytes per vertex)
		// u0: OutputVertices (RWByteAddressBuffer - 48 bytes per vertex)
		BindGroupLayoutEntry[4] entries = .(
			.() { Binding = 0, Visibility = .Compute, Type = .UniformBuffer }, // Skinning params (b0)
			.() { Binding = 0, Visibility = .Compute, Type = .StorageBufferReadOnly }, // Bone matrices (t0) - read-only storage from GPUBoneBuffer
			.() { Binding = 1, Visibility = .Compute, Type = .StorageBufferReadOnly }, // Source vertices (t1) - read-only storage
			.() { Binding = 0, Visibility = .Compute, Type = .StorageBufferReadWrite } // Output vertices (u0) - read-write storage
		);

		BindGroupLayoutDesc layoutDesc = .()
		{
			Label = "Skinning BindGroup Layout",
			Entries = entries
		};

		switch (mDevice.CreateBindGroupLayout(layoutDesc))
		{
		case .Ok(let layout): mSkinningBindGroupLayout = layout;
		case .Err: return .Err;
		}

		// Create compute pipeline with skinning shader
		if (mRenderer.ShaderSystem != null)
		{
			// Create pipeline layout
			IBindGroupLayout[1] layouts = .(mSkinningBindGroupLayout);
			PipelineLayoutDesc plDesc = .(layouts);
			switch (mDevice.CreatePipelineLayout(plDesc))
			{
			case .Ok(let layout): mPipelineLayout = layout;
			case .Err: return .Ok; // Non-fatal
			}

			let shaderResult = mRenderer.ShaderSystem.GetShader("skinning", .Compute);
			if (shaderResult case .Ok(let shader))
			{
				ComputePipelineDesc pipelineDesc = .(mPipelineLayout, shader.Module);
				pipelineDesc.Label = "GPU Skinning Pipeline";

				switch (mDevice.CreateComputePipeline(pipelineDesc))
				{
				case .Ok(let pipeline): mSkinningPipeline = pipeline;
				case .Err: // Non-fatal
				}
			}
		}

		return .Ok;
	}

	private void ExecuteSkinningPass(IComputePassEncoder encoder, RenderableList renderables, uint32 sourceId, List<(int32 Index, SkinnedMeshRenderHandle Handle)> meshes)
	{
		if (mSkinningPipeline == null)
			return;

		encoder.SetPipeline(mSkinningPipeline);

		for (let entry in meshes)
		{
			let mesh = ref renderables.SkinnedMeshes[entry.Index];

			// Get or create skinning instance (keyed by source id + handle)
			let key = SkinningInstanceKey() { SourceId = sourceId, Handle = entry.Handle };
			SkinningInstance instance;
			if (!mSkinningInstances.TryGetValue(key, out instance))
			{
				instance = CreateSkinningInstance(mesh);
				if (instance == null)
					continue;
				mSkinningInstances[key] = instance;
			}

			// Update bone transforms (rebuilds bind group if the bone buffer handle changed)
			UpdateBoneTransforms(instance, mesh);

			// Bind resources
			encoder.SetBindGroup(0, instance.BindGroup, default);

			// Dispatch compute shader
			// Workgroup size of 64, rounded up
			let vertexCount = instance.VertexCount;
			let dispatchX = (vertexCount + 63) / 64;
			encoder.Dispatch((.)dispatchX, 1, 1);

			mRenderer.Stats.ComputeDispatches++;
		}
	}

	private SkinningInstance CreateSkinningInstance(SkinnedMeshRenderable mesh)
	{
		// Get source mesh to determine vertex count and buffer
		let gpuMesh = mRenderer.ResourceManager?.GetMesh(mesh.MeshHandle);
		if (gpuMesh == null)
			return null;

		// Get the bone buffer from the resource manager
		let gpuBoneBuffer = mRenderer.ResourceManager?.GetBoneBuffer(mesh.BoneBufferHandle);
		if (gpuBoneBuffer == null || gpuBoneBuffer.Buffer == null)
			return null;

		let instance = new SkinningInstance();
		instance.VertexCount = (int32)gpuMesh.VertexCount;
		instance.BoneCount = (int32)mesh.BoneCount;
		instance.SourceVertexBuffer = gpuMesh.VertexBuffer;
		instance.BoneBufferHandle = mesh.BoneBufferHandle;

		// Create skinning params uniform buffer
		BufferDesc paramsBufferDesc = BufferDesc()
		{
			Label = "Skinning Params",
			Size = SkinningParams.Size,
			Usage = .Uniform | .CopyDst
		};

		switch (mDevice.CreateBuffer(paramsBufferDesc))
		{
		case .Ok(let buf): instance.ParamsBuffer = buf;
		case .Err:
			delete instance;
			return null;
		}

		// Create skinned vertex output buffer
		// Output vertex format (VertexLayoutHelper.Mesh - 48 bytes):
		// Position (12) + Normal (12) + TexCoord (8) + Color (4) + Tangent (12) = 48 bytes
		let outputVertexSize = 48;

		BufferDesc skinnedBufferDesc = BufferDesc()
		{
			Label = "Skinned Vertices",
			Size = (uint64)(gpuMesh.VertexCount * outputVertexSize),
			Usage = .Storage | .Vertex | .CopyDst
		};

		switch (mDevice.CreateBuffer(skinnedBufferDesc))
		{
		case .Ok(let buf): instance.SkinnedVertexBuffer = buf;
		case .Err:
			instance.Destroy(mDevice);
			delete instance;
			return null;
		}

		// Create bind group with bone buffer
		if (!CreateSkinningBindGroup(instance, gpuBoneBuffer.Buffer))
		{
			instance.Destroy(mDevice);
			delete instance;
			return null;
		}

		// Upload initial skinning params
		SkinningParams skinParams = .()
		{
			VertexCount = gpuMesh.VertexCount,
			BoneCount = mesh.BoneCount,
			_Padding = default
		};
		TransferHelper.WriteStagedBufferSync(mDevice.GetQueue(.Graphics), mDevice, instance.ParamsBuffer, 0,
			Span<uint8>((uint8*)&skinParams, SkinningParams.Size));

		return instance;
	}

	private bool CreateSkinningBindGroup(SkinningInstance instance, IBuffer boneBuffer)
	{
		if (mSkinningBindGroupLayout == null)
			return false;

		if (instance.SourceVertexBuffer == null || instance.SkinnedVertexBuffer == null || boneBuffer == null)
			return false;

		BindGroupEntry[4] entries = .(
			BindGroupEntry.Buffer(/*0,*/instance.ParamsBuffer, 0, SkinningParams.Size),  // b0: SkinningParams
			BindGroupEntry.Buffer(/*0,*/boneBuffer, 0, 0),                                // t0: BoneMatrices
			BindGroupEntry.Buffer(/*1,*/instance.SourceVertexBuffer, 0, 0),               // t1: SourceVertices
			BindGroupEntry.Buffer(/*0,*/instance.SkinnedVertexBuffer, 0, 0)               // u0: OutputVertices
		);

		BindGroupDesc desc = .()
		{
			Label = "Skinning BindGroup",
			Layout = mSkinningBindGroupLayout,
			Entries = entries
		};

		if (mDevice.CreateBindGroup(desc) case .Ok(let bindGroup))
		{
			instance.BindGroup = bindGroup;
			return true;
		}

		return false;
	}

	private void UpdateBoneTransforms(SkinningInstance instance, SkinnedMeshRenderable mesh)
	{
		// Check if the bone buffer handle changed - if so, recreate the bind group
		if (instance.BoneBufferHandle.Index != mesh.BoneBufferHandle.Index ||
			instance.BoneBufferHandle.Generation != mesh.BoneBufferHandle.Generation)
		{
			let gpuBoneBuffer = mRenderer.ResourceManager?.GetBoneBuffer(mesh.BoneBufferHandle);
			if (gpuBoneBuffer != null && gpuBoneBuffer.Buffer != null)
			{
				// Destroy old bind group and create new one
				if (instance.BindGroup != null)
					mDevice.DestroyBindGroup(ref instance.BindGroup);
				CreateSkinningBindGroup(instance, gpuBoneBuffer.Buffer);
				instance.BoneBufferHandle = mesh.BoneBufferHandle;
			}
		}

		// The bone matrices are uploaded to the GPUBoneBuffer by the animation system.
		// The bind group directly references the GPUBoneBuffer, so no copy is needed.
		//
		// NOTE: the previous implementation called proxy.ClearBonesDirty() here. Now that
		// skinning consumes a RenderableList snapshot instead of the proxy directly,
		// the dirty flag lives on the proxy and is expected to be managed by the
		// animation system. If a regression shows up, surface a ClearBonesDirty path
		// through RenderWorld instead of reintroducing a world reference here.
	}

	public void Shutdown()
	{
		for (let kv in mSkinningInstances)
		{
			kv.value.Destroy(mDevice);
			delete kv.value;
		}
		mSkinningInstances.Clear();

		mDevice.DestroyComputePipeline(ref mSkinningPipeline);
		mDevice.DestroyBindGroupLayout(ref mSkinningBindGroupLayout);
		mDevice.DestroyPipelineLayout(ref mPipelineLayout);

		mInitialized = false;
	}

	public ~this()
	{
		Shutdown();
	}
}
