namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Core.Mathematics;
using Sedulous.Shaders;
using Sedulous.Materials;
using Sedulous.RenderGraph;

/// Per-object uniforms for motion vector pass (must match object_uniforms.hlsli).
[CRepr]
struct MotionObjectUniforms
{
	public Matrix WorldMatrix;
	public Matrix PrevWorldMatrix;
	public uint32 ObjectID;
	public uint32 MaterialID;
	public Vector2 _Padding;

	public const uint32 Size = 144; // 2 matrices (128) + 2 uint32 + 2 float (16) = 144
}

/// Motion vector feature.
/// Generates per-pixel motion vectors for TAA and motion blur.
/// Uses the shared scene uniform buffer at Group 0 (matching scene_uniforms.hlsli).
public class MotionVectorFeature : RenderFeatureBase
{
	// Previous frame data
	private Dictionary<MeshProxyHandle, Matrix> mPrevTransforms = new .() ~ delete _;

	// Pipeline
	private IRenderPipeline mMotionVectorPipeline;
	private IPipelineLayout mPipelineLayout;
	private IBindGroupLayout mBindGroupLayout;

	// Combined bind groups (per-frame * per-view): camera + object in one group
	private IBindGroup[RenderConfig.FrameBufferCount * RenderConfig.MaxViews] mBindGroups;

	// Object uniform buffer (single shared buffer, updated per-draw)
	private IBuffer mObjectUniformBuffer;

	/// Feature name.
	public override StringView Name => "MotionVectors";

	/// Depends on depth prepass for depth buffer.
	public override void GetDependencies(List<StringView> outDependencies)
	{
		outDependencies.Add("DepthPrepass");
	}

	protected override Result<void> OnInitialize(InitContext initCtx)
	{
		// Create bind group layout
		if (CreateBindGroupLayout() case .Err)
			return .Err;

		// Create object uniform buffer
		var objectBufferDesc = BufferDesc()
		{
			Label = "MotionVector Object Uniforms",
			Size = MotionObjectUniforms.Size,
			Usage = .Uniform,
			Memory = .CpuToGpu
		};

		if (Renderer.Device.CreateBuffer(objectBufferDesc) case .Ok(let buffer))
			mObjectUniformBuffer = buffer;
		else
			return .Err;

		// Create motion vector pipeline
		if (CreateMotionVectorPipeline() case .Err)
			return .Err;

		return .Ok;
	}

	private Result<void> CreateBindGroupLayout()
	{
		// Single bind group with 2 entries matching HLSL register layout:
		// binding 0 = SceneUniforms (register b0, scene_uniforms.hlsli)
		// binding 1 = ObjectUniforms (register b1, object_uniforms.hlsli)
		BindGroupLayoutEntry[2] entries = .(
			.() // Camera/scene uniforms at b0
			{
				Binding = 0,
				Visibility = .Vertex | .Fragment,
				Type = .UniformBuffer
			},
			.() // Object uniforms at b1
			{
				Binding = 1,
				Visibility = .Vertex,
				Type = .UniformBuffer
			}
		);

		BindGroupLayoutDesc desc = .()
		{
			Label = "MotionVector BindGroup Layout",
			Entries = entries
		};

		switch (Renderer.Device.CreateBindGroupLayout(desc))
		{
		case .Ok(let layout): mBindGroupLayout = layout;
		case .Err: return .Err;
		}

		return .Ok;
	}

	private Result<void> CreateMotionVectorPipeline()
	{
		// Skip if shader system not initialized
		if (Renderer.ShaderSystem == null)
			return .Ok;

		// Load motion vector shaders
		let shaderResult = Renderer.ShaderSystem.GetShaderPair("motion");
		if (shaderResult case .Err)
			return .Ok; // Shaders not available yet

		let (vertShader, fragShader) = shaderResult.Value;

		// Create pipeline layout with single bind group layout:
		// Group 0: binding 0 = SceneUniforms (b0), binding 1 = ObjectUniforms (b1)
		IBindGroupLayout[1] layouts = .(mBindGroupLayout);
		PipelineLayoutDesc layoutDesc = .(layouts);
		switch (Renderer.Device.CreatePipelineLayout(layoutDesc))
		{
		case .Ok(let layout): mPipelineLayout = layout;
		case .Err: return .Err;
		}

		// Vertex layout from material system (uses standard Mesh layout)
		VertexBufferLayout[1] vertexBuffers = .(
			VertexLayoutHelper.CreateBufferLayout(.Mesh)
		);

		// Color target for motion vectors (RG16Float)
		ColorTargetState[1] colorTargets = .(
			.(.RG16Float)
		);

		RenderPipelineDesc pipelineDesc = .()
		{
			Label = "Motion Vector Pipeline",
			Layout = mPipelineLayout,
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
			DepthStencil = .()
			{
				Format = Renderer.DepthFormat,
				DepthTestEnabled = true,
				DepthWriteEnabled = false,
				DepthCompare = .LessEqual
			},
			Multisample = .()
			{
				Count = 1,
				Mask = uint32.MaxValue
			}
		};

		switch (Renderer.Device.CreateRenderPipeline(pipelineDesc))
		{
		case .Ok(let pipeline): mMotionVectorPipeline = pipeline;
		case .Err: return .Err;
		}

		return .Ok;
	}

	protected override void OnShutdown()
	{
		let device = Renderer.Device;
		for (int32 i = 0; i < RenderConfig.FrameBufferCount * RenderConfig.MaxViews; i++)
		{
			if (mBindGroups[i] != null)
				device.DestroyBindGroup(ref mBindGroups[i]);
		}
		device.DestroyBuffer(ref mObjectUniformBuffer);
		device.DestroyRenderPipeline(ref mMotionVectorPipeline);
		device.DestroyPipelineLayout(ref mPipelineLayout);
		device.DestroyBindGroupLayout(ref mBindGroupLayout);
	}

	public override void AddPasses(RenderGraph graph, ViewContext view, RenderWorld world)
	{
		// Get existing depth buffer
		let depthHandle = graph.GetResource("SceneDepth");
		if (!depthHandle.IsValid)
			return;

		// Create motion vector buffer (R16G16 for 2D velocity)
		let motionDesc = RGTextureDesc(.RG16Float, view.Width, view.Height) { Usage = .RenderTarget | .Sampled };

		let motionHandle = graph.CreateTransient("MotionVectors", motionDesc);

		// Add motion vector pass
		graph.AddRenderPass("MotionVectors", scope (builder) => {
				builder.SetColorTarget(0, motionHandle, .Clear, .Store, ClearColor(0.0f, 0.0f, 0.0f, 0.0f));
				builder.ReadDepth(depthHandle);
				builder.SetExecute(new (encoder) => {
					ExecuteMotionVectorPass(encoder, world, view);
				});
			});
	}

	private void ExecuteMotionVectorPass(IRenderPassEncoder encoder, RenderWorld world, ViewContext view)
	{
		// Set viewport
		encoder.SetViewport(0, 0, (float)view.Width, (float)view.Height, 0.0f, 1.0f);
		encoder.SetScissor(0, 0, view.Width, view.Height);

		// Set motion vector pipeline
		if (mMotionVectorPipeline == null)
			return;

		encoder.SetPipeline(mMotionVectorPipeline);

		// Get frame data from view context
		let bgIndex = view.GetBindGroupIndex();
		let cameraBuffer = view.SceneUniformBuffer;
		if (cameraBuffer == null)
			return;

		// Recreate combined bind group each frame (scene uniform buffer changes per frame+view)
		if (mBindGroups[bgIndex] != null)
			Renderer.Device.DestroyBindGroup(ref mBindGroups[bgIndex]);

		BindGroupEntry[2] bgEntries = .(
			BindGroupEntry.Buffer(/*0,*/cameraBuffer, 0, SceneUniforms.Size),
			BindGroupEntry.Buffer(/*1,*/mObjectUniformBuffer, 0, MotionObjectUniforms.Size)
		);

		BindGroupDesc bgDesc = .()
		{
			Label = "MotionVector BindGroup",
			Layout = mBindGroupLayout,
			Entries = bgEntries
		};

		if (Renderer.Device.CreateBindGroup(bgDesc) case .Ok(let bindGroup))
			mBindGroups[bgIndex] = bindGroup;
		else
			return;

		// Get depth prepass for visibility
		let depthFeature = Renderer.GetFeature<DepthPrepassFeature>();
		if (depthFeature == null)
			return;

		// Render motion vectors for visible objects
		uint32 objectID = 0;
		for (let visibleMesh in Renderer.Visibility.VisibleMeshes)
		{
			if (let proxy = world.GetMesh(visibleMesh.Handle))
			{
				// Get previous frame transform
				Matrix prevTransform = .Identity;
				if (mPrevTransforms.TryGetValue(visibleMesh.Handle, out prevTransform))
				{
					// Use previous transform
				}
				else
				{
					// First frame - use current transform (zero motion)
					prevTransform = proxy.WorldMatrix;
				}

				// Store current transform for next frame
				mPrevTransforms[visibleMesh.Handle] = proxy.WorldMatrix;

				// Update object uniform buffer (matches object_uniforms.hlsli layout)
				MotionObjectUniforms objectUniforms = .()
				{
					WorldMatrix = proxy.WorldMatrix,
					PrevWorldMatrix = prevTransform,

					ObjectID = objectID++,
					MaterialID = 0,
					_Padding = default
				};

				TransferHelper.WriteMappedBuffer(mObjectUniformBuffer, 0,
					Span<uint8>((uint8*)&objectUniforms, MotionObjectUniforms.Size));

				// Bind combined bind group (group 0: camera + object)
				encoder.SetBindGroup(0, mBindGroups[bgIndex], null);

				if (let mesh = Renderer.ResourceManager.GetMesh(proxy.MeshHandle))
				{
					encoder.SetVertexBuffer(0, mesh.VertexBuffer, 0);
					if (mesh.IndexBuffer != null && mesh.SubMeshes != null)
					{
						encoder.SetIndexBuffer(mesh.IndexBuffer, mesh.IndexFormat);
						for (let sub in mesh.SubMeshes)
						{
							encoder.DrawIndexed(sub.IndexCount, 1, sub.IndexStart, sub.BaseVertex, 0);
							Renderer.Stats.DrawCalls++;
						}
					}
					else if (mesh.IndexBuffer == null)
					{
						encoder.Draw(mesh.VertexCount, 1, 0, 0);
						Renderer.Stats.DrawCalls++;
					}
				}
			}
		}

		// Clean up old transforms
		CleanupPreviousTransforms(world);
	}

	private void CleanupPreviousTransforms(RenderWorld world)
	{
		// Remove transforms for objects that no longer exist
		List<MeshProxyHandle> toRemove = scope .();

		for (let handle in mPrevTransforms.Keys)
		{
			if (world.GetMesh(handle) == null)
				toRemove.Add(handle);
		}

		for (let handle in toRemove)
			mPrevTransforms.Remove(handle);
	}
}
