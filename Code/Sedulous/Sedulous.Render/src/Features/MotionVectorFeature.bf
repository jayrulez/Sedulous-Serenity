namespace Sedulous.Render;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;
using Sedulous.Shaders;
using Sedulous.Materials;

/// Camera uniforms for motion vector pass (must match motion.vert.hlsl CameraUniforms).
[CRepr]
struct MotionCameraUniforms
{
	public Matrix ViewMatrix;
	public Matrix ProjectionMatrix;
	public Matrix ViewProjectionMatrix;
	public Matrix PrevViewProjectionMatrix;
	public Vector3 CameraPosition;
	public float NearPlane;
	public Vector3 CameraForward;
	public float FarPlane;
	public Vector2 JitterOffset;
	public Vector2 PrevJitterOffset;

	public const uint32 Size = 304; // 4 matrices (256) + 2 vec3+float (32) + 2 vec2 (16) = 304
}

/// Per-object uniforms for motion vector pass (must match motion.vert.hlsl ObjectUniforms).
[CRepr]
struct MotionObjectUniforms
{
	public Matrix WorldMatrix;
	public Matrix PrevWorldMatrix;
	public uint32 ObjectID;
	public uint32[3] _Padding;

	public const uint32 Size = 144; // 2 matrices (128) + 4 uint32 (16) = 144
}

/// Motion vector feature.
/// Generates per-pixel motion vectors for TAA and motion blur.
public class MotionVectorFeature : RenderFeatureBase
{
	// Previous frame data
	private Matrix mPrevViewProjection;
	private Dictionary<MeshProxyHandle, Matrix> mPrevTransforms = new .() ~ delete _;

	// Pipeline
	private IRenderPipeline mMotionVectorPipeline ~ delete _;
	private IBindGroupLayout mCameraBindGroupLayout ~ delete _;
	private IBindGroupLayout mObjectBindGroupLayout ~ delete _;

	// Camera uniform buffer (triple-buffered)
	private IBuffer[RenderConfig.FrameBufferCount] mCameraUniformBuffers ~ { for (let b in _) delete b; };
	private IBindGroup[RenderConfig.FrameBufferCount] mCameraBindGroups ~ { for (let b in _) delete b; };
	private int32 mLastFrameIndex = -1;

	// Object uniform buffer (single shared buffer, updated per-draw)
	private IBuffer mObjectUniformBuffer ~ delete _;
	private IBindGroup mObjectBindGroup ~ delete _;

	// Jitter offsets for TAA
	private Vector2 mJitterOffset;
	private Vector2 mPrevJitterOffset;

	/// Feature name.
	public override StringView Name => "MotionVectors";

	/// Depends on depth prepass for depth buffer.
	public override void GetDependencies(List<StringView> outDependencies)
	{
		outDependencies.Add("DepthPrepass");
	}

	protected override Result<void> OnInitialize()
	{
		// Create bind group layout
		if (CreateBindGroupLayout() case .Err)
			return .Err;

		// Create motion vector pipeline
		if (CreateMotionVectorPipeline() case .Err)
			return .Err;

		return .Ok;
	}

	private IPipelineLayout mPipelineLayout ~ delete _;

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

		// Create pipeline layout with two bind group layouts:
		// Group 0: Camera uniforms (b0 in shader)
		// Group 1: Object uniforms (b1 in shader)
		IBindGroupLayout[2] layouts = .(mCameraBindGroupLayout, mObjectBindGroupLayout);
		PipelineLayoutDescriptor layoutDesc = .(layouts);
		switch (Renderer.Device.CreatePipelineLayout(&layoutDesc))
		{
		case .Ok(let layout): mPipelineLayout = layout;
		case .Err: return .Err;
		}

		// Vertex layout from material system (uses standard Mesh layout)
		// Motion vector shader only needs position but uses same vertex buffer format
		VertexBufferLayout[1] vertexBuffers = .(
			VertexLayoutHelper.CreateBufferLayout(.Mesh)
		);

		// Color target for motion vectors (RG16Float)
		ColorTargetState[1] colorTargets = .(
			.(.RG16Float)
		);

		RenderPipelineDescriptor pipelineDesc = .()
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

		switch (Renderer.Device.CreateRenderPipeline(&pipelineDesc))
		{
		case .Ok(let pipeline): mMotionVectorPipeline = pipeline;
		case .Err: return .Err;
		}

		return .Ok;
	}

	protected override void OnShutdown()
	{
	}

	public override void AddPasses(RenderGraph graph, RenderView view, RenderWorld world)
	{
		// Get existing depth buffer
		let depthHandle = graph.GetResource("SceneDepth");
		if (!depthHandle.IsValid)
			return;

		// Create motion vector buffer (R16G16 for 2D velocity)
		let motionDesc = TextureResourceDesc(view.Width, view.Height, .RG16Float, .RenderTarget | .Sampled);

		let motionHandle = graph.CreateTexture("MotionVectors", motionDesc);

		// Add motion vector pass
		graph.AddGraphicsPass("MotionVectors")
			.WriteColor(motionHandle, .Clear, .Store, .(0.0f, 0.0f, 0.0f, 0.0f))
			.ReadDepth(depthHandle)
			.SetExecuteCallback(new (encoder) => {
				ExecuteMotionVectorPass(encoder, world, view);
			});

		// Store current VP for next frame
		mPrevViewProjection = view.ViewProjectionMatrix;
	}

	private Result<void> CreateBindGroupLayout()
	{
		// Camera bind group layout (binding 0 - matches b0 in shader)
		BindGroupLayoutEntry[1] cameraEntries = .(
			.()
			{
				Binding = 0,
				Visibility = .Vertex | .Fragment,
				Type = .UniformBuffer
			}
		);

		BindGroupLayoutDescriptor cameraDesc = .()
		{
			Label = "MotionVector Camera BindGroup Layout",
			Entries = cameraEntries
		};

		switch (Renderer.Device.CreateBindGroupLayout(&cameraDesc))
		{
		case .Ok(let layout): mCameraBindGroupLayout = layout;
		case .Err: return .Err;
		}

		// Object bind group layout (binding 0 - matches b1 in shader, but in separate group)
		BindGroupLayoutEntry[1] objectEntries = .(
			.()
			{
				Binding = 0,
				Visibility = .Vertex,
				Type = .UniformBuffer
			}
		);

		BindGroupLayoutDescriptor objectDesc = .()
		{
			Label = "MotionVector Object BindGroup Layout",
			Entries = objectEntries
		};

		switch (Renderer.Device.CreateBindGroupLayout(&objectDesc))
		{
		case .Ok(let layout): mObjectBindGroupLayout = layout;
		case .Err: return .Err;
		}

		// Create camera uniform buffers (triple-buffered)
		for (int32 i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			var bufferDesc = BufferDescriptor()
			{
				Size = MotionCameraUniforms.Size,
				Usage = .Uniform,
				MemoryAccess = .Upload
			};

			if (Renderer.Device.CreateBuffer(&bufferDesc) case .Ok(let buffer))
				mCameraUniformBuffers[i] = buffer;
			else
				return .Err;
		}

		// Create object uniform buffer (single, updated per-draw)
		var objectBufferDesc = BufferDescriptor()
		{
			Size = MotionObjectUniforms.Size,
			Usage = .Uniform,
			MemoryAccess = .Upload
		};

		if (Renderer.Device.CreateBuffer(&objectBufferDesc) case .Ok(let buffer))
			mObjectUniformBuffer = buffer;
		else
			return .Err;

		return .Ok;
	}

	private void ExecuteMotionVectorPass(IRenderPassEncoder encoder, RenderWorld world, RenderView view)
	{
		// Set viewport
		encoder.SetViewport(0, 0, (float)view.Width, (float)view.Height, 0.0f, 1.0f);
		encoder.SetScissorRect(0, 0, view.Width, view.Height);

		// Set motion vector pipeline
		if (mMotionVectorPipeline == null)
			return;

		encoder.SetPipeline(mMotionVectorPipeline);

		// Ensure camera bind group exists and is up to date
		EnsureCameraBindGroup(view);

		// Ensure object bind group exists
		EnsureObjectBindGroup();

		// Bind camera uniforms (group 0)
		let frameContext = Renderer.RenderFrameContext;
		if (frameContext == null)
			return;

		let frameIndex = frameContext.FrameIndex;
		if (mCameraBindGroups[frameIndex] != null)
			encoder.SetBindGroup(0, mCameraBindGroups[frameIndex], null);

		// Get depth prepass for visibility
		let depthFeature = Renderer.GetFeature<DepthPrepassFeature>();
		if (depthFeature == null)
			return;

		// Render motion vectors for visible objects
		uint32 objectID = 0;
		for (let visibleMesh in depthFeature.Visibility.VisibleMeshes)
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

				// Update object uniform buffer
				MotionObjectUniforms objectUniforms = .()
				{
					WorldMatrix = proxy.WorldMatrix,
					PrevWorldMatrix = prevTransform,
					ObjectID = objectID++,
					_Padding = default
				};

				Renderer.Device.Queue.WriteBuffer(mObjectUniformBuffer, 0,
					Span<uint8>((uint8*)&objectUniforms, MotionObjectUniforms.Size));

				// Bind object uniforms (group 1)
				if (mObjectBindGroup != null)
					encoder.SetBindGroup(1, mObjectBindGroup, null);

				if (let mesh = Renderer.ResourceManager.GetMesh(proxy.MeshHandle))
				{
					encoder.SetVertexBuffer(0, mesh.VertexBuffer, 0);
					if (mesh.IndexBuffer != null)
					{
						encoder.SetIndexBuffer(mesh.IndexBuffer, mesh.IndexFormat);
						encoder.DrawIndexed(mesh.IndexCount, 1, 0, 0, 0);
					}
					else
					{
						encoder.Draw(mesh.VertexCount, 1, 0, 0);
					}

					Renderer.Stats.DrawCalls++;
				}
			}
		}

		// Clean up old transforms
		CleanupPreviousTransforms(world);
	}

	private void EnsureCameraBindGroup(RenderView view)
	{
		let frameContext = Renderer.RenderFrameContext;
		if (frameContext == null)
			return;

		let frameIndex = frameContext.FrameIndex;

		// Update camera uniform buffer with current view data
		MotionCameraUniforms cameraUniforms = .()
		{
			ViewMatrix = view.ViewMatrix,
			ProjectionMatrix = view.ProjectionMatrix,
			ViewProjectionMatrix = view.ViewProjectionMatrix,
			PrevViewProjectionMatrix = mPrevViewProjection,
			CameraPosition = view.CameraPosition,
			NearPlane = view.NearPlane,
			CameraForward = view.CameraForward,
			FarPlane = view.FarPlane,
			JitterOffset = mJitterOffset,
			PrevJitterOffset = mPrevJitterOffset
		};

		Renderer.Device.Queue.WriteBuffer(mCameraUniformBuffers[frameIndex], 0,
			Span<uint8>((uint8*)&cameraUniforms, MotionCameraUniforms.Size));

		// Create camera bind group if needed (or recreate on frame index change)
		if (mCameraBindGroups[frameIndex] == null)
		{
			BindGroupEntry[1] entries = .(
				.()
				{
					Binding = 0,
					Buffer = mCameraUniformBuffers[frameIndex],
					BufferOffset = 0,
					BufferSize = MotionCameraUniforms.Size
				}
			);

			BindGroupDescriptor desc = .()
			{
				Label = "MotionVector Camera BindGroup",
				Layout = mCameraBindGroupLayout,
				Entries = entries
			};

			if (Renderer.Device.CreateBindGroup(&desc) case .Ok(let bindGroup))
				mCameraBindGroups[frameIndex] = bindGroup;
		}

		mLastFrameIndex = frameIndex;
	}

	private void EnsureObjectBindGroup()
	{
		if (mObjectBindGroup != null)
			return;

		if (mObjectUniformBuffer == null || mObjectBindGroupLayout == null)
			return;

		BindGroupEntry[1] entries = .(
			.()
			{
				Binding = 0,
				Buffer = mObjectUniformBuffer,
				BufferOffset = 0,
				BufferSize = MotionObjectUniforms.Size
			}
		);

		BindGroupDescriptor desc = .()
		{
			Label = "MotionVector Object BindGroup",
			Layout = mObjectBindGroupLayout,
			Entries = entries
		};

		if (Renderer.Device.CreateBindGroup(&desc) case .Ok(let bindGroup))
			mObjectBindGroup = bindGroup;
	}

	/// Sets the jitter offset for TAA. Call this before rendering.
	public void SetJitterOffset(Vector2 jitterOffset)
	{
		mPrevJitterOffset = mJitterOffset;
		mJitterOffset = jitterOffset;
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
