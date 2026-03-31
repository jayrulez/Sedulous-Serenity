using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Core.Mathematics;
using Sedulous.Profiler;
using Sedulous.Shaders;

namespace Sedulous.Renderer;

/// Skinning parameters uniform buffer (must match skinning.comp.hlsl SkinningParams).
[CRepr]
struct SkinningParams
{
	public uint32 VertexCount;
	public uint32 BoneCount;
	public uint32[2] _Padding;

	public const uint32 Size = 16;
}

/// Composite key for skinning instances (world + mesh handle).
struct SkinningInstanceKey : IHashable
{
	public RenderWorld World;
	public SkinnedMeshProxyHandle Handle;

	public int GetHashCode()
	{
		int worldHash = World != null ? (int)Internal.UnsafeCastToPtr(World) : 0;
		return worldHash ^ (Handle.GetHashCode() * 31);
	}

	public static bool operator==(Self lhs, Self rhs)
	{
		return lhs.World == rhs.World && lhs.Handle.Handle == rhs.Handle.Handle;
	}
}

/// Per-mesh skinning data.
class SkinningInstance
{
	public IBuffer ParamsBuffer;
	public GPUBoneBufferHandle BoneBufferHandle;
	public IBuffer SourceVertexBuffer;
	public IBuffer SkinnedVertexBuffer;
	public IBindGroup BindGroup;
	public int32 VertexCount;
	public int32 BoneCount;

	public void Destroy(IDevice device)
	{
		device.DestroyBuffer(ref ParamsBuffer);
		device.DestroyBuffer(ref SkinnedVertexBuffer);
		device.DestroyBindGroup(ref BindGroup);
	}
}

/// GPU compute skinning infrastructure.
/// Owned by RenderSystem, not a render feature.
/// Uses compute shaders to transform vertices by bone matrices.
public class SkinningSystem
{
	private IDevice mDevice;
	private RenderSystem mRenderer;
	private bool mInitialized;

	// Compute pipeline
	private IComputePipeline mSkinningPipeline;
	private IBindGroupLayout mSkinningBindGroupLayout;
	private IPipelineLayout mPipelineLayout;

	// Per-mesh skinning data
	private Dictionary<SkinningInstanceKey, SkinningInstance> mSkinningInstances = new .() ~ {
		for (let kv in _) delete kv.value;
		delete _;
	};

	public this(IDevice device)
	{
		mDevice = device;
	}

	/// Initialize skinning infrastructure
	public Result<void> Initialize(RenderSystem renderer)
	{
		using (SProfiler.Begin("Renderer.SkinningSystem"))
		{
			mRenderer = renderer;

			if (CreateSkinningPipeline() case .Err)
				return .Err;

			mInitialized = true;
		}
		return .Ok;
	}

	public bool IsInitialized => mInitialized;

	/// Gets the skinned vertex buffer for a skinned mesh.
	public IBuffer GetSkinnedVertexBuffer(RenderWorld world, SkinnedMeshProxyHandle handle)
	{
		let key = SkinningInstanceKey() { World = world, Handle = handle };
		if (mSkinningInstances.TryGetValue(key, let instance))
			return instance.SkinnedVertexBuffer;
		return null;
	}

	/// Gets the vertex count for a skinned mesh instance.
	public int32 GetSkinnedVertexCount(RenderWorld world, SkinnedMeshProxyHandle handle)
	{
		let key = SkinningInstanceKey() { World = world, Handle = handle };
		if (mSkinningInstances.TryGetValue(key, let instance))
			return instance.VertexCount;
		return 0;
	}

	/// Add skinning compute pass to the render graph
	public void AddPasses(Sedulous.RenderGraph.RenderGraph graph, RenderWorld world)
	{
		if (!mInitialized || mSkinningPipeline == null)
			return;

		let skinnedMeshes = scope List<SkinnedMeshProxyHandle>();
		world.ForEachSkinnedMesh(scope [&](handle, proxy) =>
		{
			if (proxy.IsVisible)
				skinnedMeshes.Add(.() { Handle = handle });
		});

		if (skinnedMeshes.Count == 0)
			return;

		let meshCopy = new List<SkinnedMeshProxyHandle>();
		meshCopy.AddRange(skinnedMeshes);

		let system = this;
		let worldRef = world;

		graph.AddComputePass("GPUSkinning", scope (builder) =>
		{
			builder.NeverCull();
			builder.SetComputeExecute(new [=](encoder) => {
				system.ExecuteSkinningPass(encoder, worldRef, meshCopy);
				delete meshCopy;
			});
		});
	}

	/// Overload without world (no-op)
	public void AddPasses(Sedulous.RenderGraph.RenderGraph graph)
	{
	}

	private Result<void> CreateSkinningPipeline()
	{
		// Must match skinning.comp.hlsl register layout:
		// b0: SkinningParams (uniform)
		// t0: BoneMatrices (StructuredBuffer<float4x4>)
		// t1: SourceVertices (ByteAddressBuffer)
		// u0: OutputVertices (RWByteAddressBuffer)
		BindGroupLayoutEntry[4] entries = .(
			.() { Binding = 0, Visibility = .Compute, Type = .UniformBuffer },           // b0
			.() { Binding = 0, Visibility = .Compute, Type = .StorageBufferReadOnly },    // t0
			.() { Binding = 1, Visibility = .Compute, Type = .StorageBufferReadOnly },    // t1
			.() { Binding = 0, Visibility = .Compute, Type = .StorageBufferReadWrite }    // u0
		);

		BindGroupLayoutDesc layoutDesc = .(entries);
		layoutDesc.Label = "Skinning BindGroup Layout";

		switch (mDevice.CreateBindGroupLayout(layoutDesc))
		{
		case .Ok(let layout): mSkinningBindGroupLayout = layout;
		case .Err: return .Err;
		}

		if (mRenderer.ShaderSystem != null)
		{
			IBindGroupLayout[1] layouts = .(mSkinningBindGroupLayout);
			PipelineLayoutDesc plDesc = .(layouts);
			switch (mDevice.CreatePipelineLayout(plDesc))
			{
			case .Ok(let layout): mPipelineLayout = layout;
			case .Err: return .Ok;
			}

			let shaderResult = mRenderer.ShaderSystem.GetShader("skinning", .Compute);
			if (shaderResult case .Ok(let shader))
			{
				ComputePipelineDesc pipelineDesc = .(mPipelineLayout, shader.Module);
				pipelineDesc.Label = "GPU Skinning Pipeline";

				switch (mDevice.CreateComputePipeline(pipelineDesc))
				{
				case .Ok(let pipeline): mSkinningPipeline = pipeline;
				case .Err:
				}
			}
		}

		return .Ok;
	}

	private void ExecuteSkinningPass(IComputePassEncoder encoder, RenderWorld world, List<SkinnedMeshProxyHandle> meshes)
	{
		if (mSkinningPipeline == null)
			return;

		using (SProfiler.Begin("SkinningSystem.Execute"))
		{
			encoder.SetPipeline(mSkinningPipeline);

			for (let handle in meshes)
			{
				if (let proxy = world.GetSkinnedMesh(handle))
				{
					let key = SkinningInstanceKey() { World = world, Handle = handle };
					SkinningInstance instance;
					if (!mSkinningInstances.TryGetValue(key, out instance))
					{
						instance = CreateSkinningInstance(proxy);
						if (instance == null)
							continue;
						mSkinningInstances[key] = instance;
					}

					UpdateBoneTransforms(instance, proxy);
					encoder.SetBindGroup(0, instance.BindGroup, default);

					let dispatchX = (instance.VertexCount + 63) / 64;
					encoder.Dispatch((.)dispatchX, 1, 1);
				}
			}
		}
	}

	private SkinningInstance CreateSkinningInstance(SkinnedMeshProxy* proxy)
	{
		let gpuMesh = mRenderer.ResourceManager?.GetMesh(proxy.MeshHandle);
		if (gpuMesh == null) return null;

		let gpuBoneBuffer = mRenderer.ResourceManager?.GetBoneBuffer(proxy.BoneBufferHandle);
		if (gpuBoneBuffer == null || gpuBoneBuffer.Buffer == null) return null;

		let instance = new SkinningInstance();
		instance.VertexCount = (int32)gpuMesh.VertexCount;
		instance.BoneCount = (int32)proxy.BoneCount;
		instance.SourceVertexBuffer = gpuMesh.VertexBuffer;
		instance.BoneBufferHandle = proxy.BoneBufferHandle;

		if (mDevice.CreateBuffer(BufferDesc()
		{
			Label = "Skinning Params",
			Size = SkinningParams.Size,
			Usage = .Uniform | .CopyDst
		}) case .Ok(let paramsBuf))
			instance.ParamsBuffer = paramsBuf;
		else
		{
			delete instance;
			return null;
		}

		if (mDevice.CreateBuffer(BufferDesc()
		{
			Label = "Skinned Vertices",
			Size = (uint64)(gpuMesh.VertexCount * 48),
			Usage = .Storage | .Vertex | .CopyDst
		}) case .Ok(let skinnedBuf))
			instance.SkinnedVertexBuffer = skinnedBuf;
		else
		{
			instance.Destroy(mDevice);
			delete instance;
			return null;
		}

		if (!CreateSkinningBindGroup(instance, gpuBoneBuffer.Buffer))
		{
			instance.Destroy(mDevice);
			delete instance;
			return null;
		}

		SkinningParams skinParams = .()
		{
			VertexCount = gpuMesh.VertexCount,
			BoneCount = proxy.BoneCount,
			_Padding = default
		};
		TransferHelper.WriteStagedBufferSync(mDevice.GetQueue(.Graphics), mDevice, instance.ParamsBuffer, 0,
			Span<uint8>((uint8*)&skinParams, SkinningParams.Size));

		return instance;
	}

	private bool CreateSkinningBindGroup(SkinningInstance instance, IBuffer boneBuffer)
	{
		if (mSkinningBindGroupLayout == null) return false;
		if (instance.SourceVertexBuffer == null || instance.SkinnedVertexBuffer == null || boneBuffer == null) return false;

		BindGroupEntry[4] entries = .(
			BindGroupEntry.Buffer(instance.ParamsBuffer, 0, SkinningParams.Size),
			BindGroupEntry.Buffer(boneBuffer, 0, 0),
			BindGroupEntry.Buffer(instance.SourceVertexBuffer, 0, 0),
			BindGroupEntry.Buffer(instance.SkinnedVertexBuffer, 0, 0)
		);

		BindGroupDesc desc = .(mSkinningBindGroupLayout, entries);
		desc.Label = "Skinning BindGroup";

		if (mDevice.CreateBindGroup(desc) case .Ok(let bindGroup))
		{
			instance.BindGroup = bindGroup;
			return true;
		}

		return false;
	}

	private void UpdateBoneTransforms(SkinningInstance instance, SkinnedMeshProxy* proxy)
	{
		if (instance.BoneBufferHandle != proxy.BoneBufferHandle)
		{
			let gpuBoneBuffer = mRenderer.ResourceManager?.GetBoneBuffer(proxy.BoneBufferHandle);
			if (gpuBoneBuffer != null && gpuBoneBuffer.Buffer != null)
			{
				if (instance.BindGroup != null)
					mDevice.DestroyBindGroup(ref instance.BindGroup);
				CreateSkinningBindGroup(instance, gpuBoneBuffer.Buffer);
				instance.BoneBufferHandle = proxy.BoneBufferHandle;
			}
		}

		proxy.ClearBonesDirty();
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
