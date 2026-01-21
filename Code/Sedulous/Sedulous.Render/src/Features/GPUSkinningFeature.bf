namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;
using Sedulous.Shaders;

/// GPU bone transform buffer for a single skinned mesh.
[CRepr]
public struct GPUBoneTransforms
{
	/// Bone matrices in model space.
	public Matrix[RenderConfig.MaxBonesPerMesh] BoneMatrices;

	/// Size of the struct in bytes.
	public static int Size => RenderConfig.MaxBonesPerMesh * sizeof(Matrix);
}

/// Skinning parameters uniform buffer (must match skinning.comp.hlsl SkinningParams).
[CRepr]
struct SkinningParams
{
	public uint32 VertexCount;
	public uint32 BoneCount;
	public uint32[2] _Padding;

	public const uint32 Size = 16;
}

/// GPU skinning feature.
/// Uses compute shaders to transform vertices by bone matrices.
public class GPUSkinningFeature : RenderFeatureBase
{
	// Compute pipeline
	private IComputePipeline mSkinningPipeline ~ delete _;
	private IBindGroupLayout mSkinningBindGroupLayout ~ delete _;

	// Per-mesh skinning data
	private Dictionary<SkinnedMeshProxyHandle, SkinningInstance> mSkinningInstances = new .() ~ {
		for (let kv in _)
			delete kv.value;
		delete _;
	};

	/// Feature name.
	public override StringView Name => "GPUSkinning";

	/// Skinning runs before depth prepass.
	public override void GetDependencies(List<StringView> outDependencies)
	{
		// No dependencies - runs first to prepare skinned vertex buffers
	}

	/// Gets the skinned (transformed) vertex buffer for a skinned mesh.
	/// This buffer contains the post-skinning vertices ready for rendering.
	/// Returns null if no skinning instance exists for this mesh.
	public IBuffer GetSkinnedVertexBuffer(SkinnedMeshProxyHandle handle)
	{
		if (mSkinningInstances.TryGetValue(handle, let instance))
			return instance.SkinnedVertexBuffer;
		return null;
	}

	/// Gets the vertex count for a skinned mesh instance.
	public int32 GetSkinnedVertexCount(SkinnedMeshProxyHandle handle)
	{
		if (mSkinningInstances.TryGetValue(handle, let instance))
			return instance.VertexCount;
		return 0;
	}

	protected override Result<void> OnInitialize()
	{
		// Create skinning compute pipeline
		if (CreateSkinningPipeline() case .Err)
			return .Err;

		return .Ok;
	}

	protected override void OnShutdown()
	{
		for (let kv in mSkinningInstances)
			delete kv.value;
		mSkinningInstances.Clear();
	}

	public override void AddPasses(RenderGraph graph, RenderView view, RenderWorld world)
	{
		// Find all skinned meshes that need updating
		List<SkinnedMeshProxyHandle> skinnedMeshes = scope .();

		world.ForEachSkinnedMesh(scope [&] (handle, proxy) =>
		{
			if (proxy.IsVisible)
				skinnedMeshes.Add(.() { Handle = handle });
		});

		if (skinnedMeshes.Count == 0)
			return;

		// Copy to heap for closure capture
		List<SkinnedMeshProxyHandle> meshCopy = new .();
		meshCopy.AddRange(skinnedMeshes);

		// Add skinning compute pass
		graph.AddComputePass("GPUSkinning")
			.NeverCull()
			.SetComputeCallback(new (encoder) => {
				ExecuteSkinningPass(encoder, world, meshCopy);
				delete meshCopy;
			});
	}

	private IPipelineLayout mPipelineLayout ~ delete _;

	private Result<void> CreateSkinningPipeline()
	{
		// Create bind group layout matching skinning.comp.hlsl:
		// b0: SkinningParams (uniform)
		// t0: BoneMatrices (StructuredBuffer<float4x4>)
		// t1: SourceVertices (ByteAddressBuffer - 72 bytes per vertex)
		// u0: OutputVertices (RWByteAddressBuffer - 48 bytes per vertex)
		BindGroupLayoutEntry[4] entries = .(
			.() // Skinning params (b0)
			{
				Binding = 0,
				Visibility = .Compute,
				Type = .UniformBuffer
			},
			.() // Bone matrices (t0) - read-only storage from GPUBoneBuffer
			{
				Binding = 0,
				Visibility = .Compute,
				Type = .StorageBuffer
			},
			.() // Source vertices (t1) - read-only storage
			{
				Binding = 1,
				Visibility = .Compute,
				Type = .StorageBuffer
			},
			.() // Output vertices (u0) - read-write storage
			{
				Binding = 0,
				Visibility = .Compute,
				Type = .StorageBufferReadWrite
			}
		);

		BindGroupLayoutDescriptor layoutDesc = .()
		{
			Label = "Skinning BindGroup Layout",
			Entries = entries
		};

		switch (Renderer.Device.CreateBindGroupLayout(&layoutDesc))
		{
		case .Ok(let layout): mSkinningBindGroupLayout = layout;
		case .Err: return .Err;
		}

		// Create compute pipeline with skinning shader
		if (Renderer.ShaderSystem != null)
		{
			// Create pipeline layout
			IBindGroupLayout[1] layouts = .(mSkinningBindGroupLayout);
			PipelineLayoutDescriptor plDesc = .(layouts);
			switch (Renderer.Device.CreatePipelineLayout(&plDesc))
			{
			case .Ok(let layout): mPipelineLayout = layout;
			case .Err: return .Ok; // Non-fatal
			}

			let shaderResult = Renderer.ShaderSystem.GetShader("skinning", .Compute);
			if (shaderResult case .Ok(let shader))
			{
				ComputePipelineDescriptor pipelineDesc = .(mPipelineLayout, shader.Module);
				pipelineDesc.Label = "GPU Skinning Pipeline";

				switch (Renderer.Device.CreateComputePipeline(&pipelineDesc))
				{
				case .Ok(let pipeline): mSkinningPipeline = pipeline;
				case .Err: // Non-fatal
				}
			}
		}

		return .Ok;
	}

	private void ExecuteSkinningPass(IComputePassEncoder encoder, RenderWorld world, List<SkinnedMeshProxyHandle> meshes)
	{
		if (mSkinningPipeline == null)
			return;

		encoder.SetPipeline(mSkinningPipeline);

		for (let handle in meshes)
		{
			if (let proxy = world.GetSkinnedMesh(handle))
			{
				// Get or create skinning instance
				SkinningInstance instance;
				if (!mSkinningInstances.TryGetValue(handle, out instance))
				{
					instance = CreateSkinningInstance(proxy);
					if (instance == null)
						continue;
					mSkinningInstances[handle] = instance;
				}

				// Update bone transforms
				UpdateBoneTransforms(instance, proxy);

				// Bind resources
				encoder.SetBindGroup(0, instance.BindGroup, default);

				// Dispatch compute shader
				// Workgroup size of 64, rounded up
				let vertexCount = instance.VertexCount;
				let dispatchX = (vertexCount + 63) / 64;
				encoder.Dispatch((.)dispatchX, 1, 1);

				Renderer.Stats.ComputeDispatches++;
			}
		}
	}

	private SkinningInstance CreateSkinningInstance(SkinnedMeshProxy* proxy)
	{
		// Get source mesh to determine vertex count and buffer
		let gpuMesh = Renderer.ResourceManager?.GetMesh(proxy.MeshHandle);
		if (gpuMesh == null)
			return null;

		// Get the bone buffer from the resource manager
		let gpuBoneBuffer = Renderer.ResourceManager?.GetBoneBuffer(proxy.BoneBufferHandle);
		if (gpuBoneBuffer == null || gpuBoneBuffer.Buffer == null)
			return null;

		let instance = new SkinningInstance();
		instance.VertexCount = (int32)gpuMesh.VertexCount;
		instance.BoneCount = (int32)proxy.BoneCount;
		instance.SourceVertexBuffer = gpuMesh.VertexBuffer;
		instance.BoneBufferHandle = proxy.BoneBufferHandle;

		// Create skinning params uniform buffer
		BufferDescriptor paramsBufferDesc = .()
		{
			Label = "Skinning Params",
			Size = SkinningParams.Size,
			Usage = .Uniform | .CopyDst
		};

		switch (Renderer.Device.CreateBuffer(&paramsBufferDesc))
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
		BufferDescriptor skinnedBufferDesc = .()
		{
			Label = "Skinned Vertices",
			Size = (uint64)(gpuMesh.VertexCount * outputVertexSize),
			Usage = .Storage | .Vertex | .CopyDst
		};

		switch (Renderer.Device.CreateBuffer(&skinnedBufferDesc))
		{
		case .Ok(let buf): instance.SkinnedVertexBuffer = buf;
		case .Err:
			delete instance;
			return null;
		}

		// Create bind group with bone buffer
		if (!CreateSkinningBindGroup(instance, gpuBoneBuffer.Buffer))
		{
			delete instance;
			return null;
		}

		// Upload initial skinning params
		SkinningParams skinParams = .()
		{
			VertexCount = gpuMesh.VertexCount,
			BoneCount = proxy.BoneCount,
			_Padding = default
		};
		Renderer.Device.Queue.WriteBuffer(instance.ParamsBuffer, 0,
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
			BindGroupEntry.Buffer(0, instance.ParamsBuffer, 0, SkinningParams.Size),  // b0: SkinningParams
			BindGroupEntry.Buffer(0, boneBuffer, 0, 0),                                // t0: BoneMatrices
			BindGroupEntry.Buffer(1, instance.SourceVertexBuffer, 0, 0),               // t1: SourceVertices
			BindGroupEntry.Buffer(0, instance.SkinnedVertexBuffer, 0, 0)               // u0: OutputVertices
		);

		BindGroupDescriptor desc = .()
		{
			Label = "Skinning BindGroup",
			Layout = mSkinningBindGroupLayout,
			Entries = entries
		};

		if (Renderer.Device.CreateBindGroup(&desc) case .Ok(let bindGroup))
		{
			instance.BindGroup = bindGroup;
			return true;
		}

		return false;
	}

	private void UpdateBoneTransforms(SkinningInstance instance, SkinnedMeshProxy* proxy)
	{
		// Check if the bone buffer handle changed - if so, recreate the bind group
		if (instance.BoneBufferHandle.Index != proxy.BoneBufferHandle.Index ||
			instance.BoneBufferHandle.Generation != proxy.BoneBufferHandle.Generation)
		{
			let gpuBoneBuffer = Renderer.ResourceManager?.GetBoneBuffer(proxy.BoneBufferHandle);
			if (gpuBoneBuffer != null && gpuBoneBuffer.Buffer != null)
			{
				// Delete old bind group and create new one
				if (instance.BindGroup != null)
				{
					delete instance.BindGroup;
					instance.BindGroup = null;
				}
				CreateSkinningBindGroup(instance, gpuBoneBuffer.Buffer);
				instance.BoneBufferHandle = proxy.BoneBufferHandle;
			}
		}

		// The bone matrices are uploaded to the GPUBoneBuffer by the animation system
		// The bind group directly references the GPUBoneBuffer, so no copy is needed

		// Mark that bones have been updated
		proxy.ClearBonesDirty();
	}

	/// Per-mesh skinning data.
	private class SkinningInstance
	{
		/// Skinning parameters uniform buffer.
		public IBuffer ParamsBuffer ~ delete _;

		/// Handle to the bone buffer (not owned, from GPUResourceManager).
		public GPUBoneBufferHandle BoneBufferHandle;

		/// Reference to source vertex buffer (not owned, from GPUMesh).
		public IBuffer SourceVertexBuffer;

		/// Skinned vertex output buffer (owned).
		public IBuffer SkinnedVertexBuffer ~ delete _;

		/// Bind group for compute dispatch.
		public IBindGroup BindGroup ~ delete _;

		/// Number of vertices in the mesh.
		public int32 VertexCount;

		/// Number of bones in the skeleton.
		public int32 BoneCount;

		public void Dispose()
		{
			// Handled by destructors
		}
	}
}
