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
	public const int MaxBones = 256;

	/// Bone matrices in model space.
	public Matrix[MaxBones] BoneMatrices;

	/// Size of the struct in bytes.
	public static int Size => MaxBones * sizeof(Matrix);
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
			kv.value.Dispose();
		delete _;
	};

	/// Feature name.
	public override StringView Name => "GPUSkinning";

	/// Skinning runs before depth prepass.
	public override void GetDependencies(List<StringView> outDependencies)
	{
		// No dependencies - runs first to prepare skinned vertex buffers
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
			kv.value.Dispose();
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
		// b1: BoneMatrices (uniform)
		// t0: SourceVertices (storage, read-only)
		// u0: OutputVertices (storage, read-write)
		BindGroupLayoutEntry[4] entries = .(
			.() // Skinning params (b0)
			{
				Binding = 0,
				Visibility = .Compute,
				Type = .UniformBuffer
			},
			.() // Bone matrices (b1)
			{
				Binding = 1,
				Visibility = .Compute,
				Type = .UniformBuffer
			},
			.() // Source vertices (t0) - read-only storage
			{
				Binding = 2,
				Visibility = .Compute,
				Type = .StorageBuffer
			},
			.() // Output vertices (u0) - read-write storage
			{
				Binding = 3,
				Visibility = .Compute,
				Type = .StorageBuffer
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

		let instance = new SkinningInstance();
		instance.VertexCount = (int32)gpuMesh.VertexCount;
		instance.BoneCount = (int32)proxy.BoneCount;
		instance.SourceVertexBuffer = gpuMesh.VertexBuffer;

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

		// Create bone transform buffer
		BufferDescriptor boneBufferDesc = .()
		{
			Label = "Bone Transforms",
			Size = (uint64)GPUBoneTransforms.Size,
			Usage = .Uniform | .CopyDst
		};

		switch (Renderer.Device.CreateBuffer(&boneBufferDesc))
		{
		case .Ok(let buf): instance.BoneBuffer = buf;
		case .Err:
			delete instance;
			return null;
		}

		// Create skinned vertex output buffer
		// Output vertex format: Position (12) + Normal (12) + Tangent (16) + TexCoord (8) = 48 bytes
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

		// Create bind group
		if (!CreateSkinningBindGroup(instance))
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

	private bool CreateSkinningBindGroup(SkinningInstance instance)
	{
		if (mSkinningBindGroupLayout == null)
			return false;

		if (instance.SourceVertexBuffer == null || instance.SkinnedVertexBuffer == null)
			return false;

		BindGroupEntry[4] entries = .(
			.() // Skinning params (binding 0)
			{
				Binding = 0,
				Buffer = instance.ParamsBuffer,
				BufferOffset = 0,
				BufferSize = SkinningParams.Size
			},
			.() // Bone matrices (binding 1)
			{
				Binding = 1,
				Buffer = instance.BoneBuffer,
				BufferOffset = 0,
				BufferSize = (uint64)GPUBoneTransforms.Size
			},
			.() // Source vertices (binding 2)
			{
				Binding = 2,
				Buffer = instance.SourceVertexBuffer,
				BufferOffset = 0,
				BufferSize = 0  // Entire buffer
			},
			.() // Output vertices (binding 3)
			{
				Binding = 3,
				Buffer = instance.SkinnedVertexBuffer,
				BufferOffset = 0,
				BufferSize = 0  // Entire buffer
			}
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
		if (instance.BoneBuffer == null)
			return;

		// Get the bone buffer from the resource manager
		let boneBuffer = Renderer.ResourceManager?.GetBoneBuffer(proxy.BoneBufferHandle);
		if (boneBuffer == null)
			return;

		// The bone matrices are already in the bone buffer managed by the animation system
		// We need to copy them to our skinning instance's bone buffer
		// For now, we assume the bone buffer contains properly formatted matrices

		// If the proxy has a direct bone buffer reference, use it
		// Otherwise, the animation system should have already uploaded the matrices
		// to the bone buffer referenced by BoneBufferHandle

		// Mark that bones have been updated
		proxy.ClearBonesDirty();
	}

	/// Per-mesh skinning data.
	private class SkinningInstance
	{
		/// Skinning parameters uniform buffer.
		public IBuffer ParamsBuffer ~ delete _;

		/// Bone transform uniform buffer.
		public IBuffer BoneBuffer ~ delete _;

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
