namespace Sedulous.Framework.Renderer;

using System;
using System.Collections;
using Sedulous.Framework.Core;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.Serialization;

/// Per-instance GPU data (80 bytes) - transform matrix rows + color.
/// Internal to RenderSceneComponent.
[CRepr]
struct RenderSceneInstanceData
{
	public Vector4 Row0;
	public Vector4 Row1;
	public Vector4 Row2;
	public Vector4 Row3;
	public Vector4 Color;

	public this(Matrix transform, Vector4 color)
	{
		Row0 = .(transform.M11, transform.M12, transform.M13, transform.M14);
		Row1 = .(transform.M21, transform.M22, transform.M23, transform.M24);
		Row2 = .(transform.M31, transform.M32, transform.M33, transform.M34);
		Row3 = .(transform.M41, transform.M42, transform.M43, transform.M44);
		Color = color;
	}
}

/// Camera uniform buffer data
[CRepr]
struct SceneCameraUniforms
{
	public Matrix ViewProjection;
	public Vector3 CameraPosition;
	public float _pad0;
}

/// Per-frame GPU resources to avoid GPU/CPU synchronization issues.
struct SceneFrameResources
{
	public IBuffer CameraBuffer;
	public IBuffer InstanceBuffer;
	public IBindGroup BindGroup;

	public void Dispose() mut
	{
		delete CameraBuffer;
		delete InstanceBuffer;
		delete BindGroup;
		this = default;
	}
}

/// Scene component that manages rendering for a scene.
/// Owns the RenderWorld (proxy pool), VisibilityResolver, GPU resources,
/// and coordinates entity-to-proxy synchronization.
class RenderSceneComponent : ISceneComponent
{
	private const int32 MAX_FRAMES_IN_FLIGHT = 2;
	private const int32 MAX_INSTANCES = 4096;

	private RendererService mRendererService;
	private Scene mScene;
	private RenderWorld mRenderWorld ~ delete _;
	private VisibilityResolver mVisibilityResolver ~ delete _;

	// Entity → Proxy mapping for each proxy type
	private Dictionary<EntityId, ProxyHandle> mMeshProxies = new .() ~ delete _;
	private Dictionary<EntityId, ProxyHandle> mLightProxies = new .() ~ delete _;
	private Dictionary<EntityId, ProxyHandle> mCameraProxies = new .() ~ delete _;

	// Cached lists for iteration
	private List<MeshProxy*> mVisibleMeshes = new .() ~ delete _;
	private List<LightProxy*> mActiveLights = new .() ~ delete _;

	// Main camera handle
	private ProxyHandle mMainCamera = .Invalid;

	// ==================== GPU Rendering Infrastructure ====================

	// Per-frame resources
	private SceneFrameResources[MAX_FRAMES_IN_FLIGHT] mFrameResources = .();
	private int32 mCurrentFrameIndex = 0;

	// Pipeline resources (shared across frames)
	private IBindGroupLayout mBindGroupLayout ~ delete _;
	private IPipelineLayout mPipelineLayout ~ delete _;
	private IRenderPipeline mPipeline ~ delete _;

	// CPU-side instance data (built in OnUpdate, uploaded in PrepareGPU)
	private RenderSceneInstanceData[] mInstanceData ~ delete _;
	private int32 mInstanceCount = 0;

	// Rendering state
	private bool mRenderingInitialized = false;
	private TextureFormat mColorFormat = .BGRA8UnormSrgb;
	private TextureFormat mDepthFormat = .Depth24PlusStencil8;
	private bool mFlipProjection = false;

	// ==================== Properties ====================

	/// Gets the renderer service.
	public RendererService RendererService => mRendererService;

	/// Gets the render world for proxy management.
	public RenderWorld RenderWorld => mRenderWorld;

	/// Gets the visibility resolver.
	public VisibilityResolver VisibilityResolver => mVisibilityResolver;

	/// Gets or sets the main camera proxy handle.
	public ProxyHandle MainCamera
	{
		get => mMainCamera;
		set
		{
			mMainCamera = value;
			if (mRenderWorld != null)
				mRenderWorld.SetMainCamera(value);
		}
	}

	/// Gets the scene this component is attached to.
	public Scene Scene => mScene;

	/// Gets the list of visible meshes after culling.
	public List<MeshProxy*> VisibleMeshes => mVisibleMeshes;

	/// Gets the list of active lights.
	public List<LightProxy*> ActiveLights => mActiveLights;

	/// Gets the main camera proxy.
	public CameraProxy* GetMainCameraProxy() => mRenderWorld.MainCamera;

	/// Gets mesh count for statistics.
	public uint32 MeshCount => mRenderWorld.MeshCount;

	/// Gets light count for statistics.
	public uint32 LightCount => mRenderWorld.LightCount;

	/// Gets camera count for statistics.
	public uint32 CameraCount => mRenderWorld.CameraCount;

	/// Gets visible instance count for statistics.
	public int32 VisibleInstanceCount => mInstanceCount;

	// ==================== Constructor ====================

	/// Creates a new RenderSceneComponent.
	/// The RendererService must be initialized before passing here.
	public this(RendererService rendererService)
	{
		mRendererService = rendererService;
		mRenderWorld = new RenderWorld();
		mVisibilityResolver = new VisibilityResolver();
		mInstanceData = new RenderSceneInstanceData[MAX_INSTANCES];
	}

	// ==================== ISceneComponent Implementation ====================

	/// Called when the component is attached to a scene.
	public void OnAttach(Scene scene)
	{
		mScene = scene;
	}

	/// Called when the component is detached from a scene.
	public void OnDetach()
	{
		CleanupRendering();
		mRenderWorld.Clear();
		mMeshProxies.Clear();
		mLightProxies.Clear();
		mCameraProxies.Clear();
		mScene = null;
	}

	/// Called each frame to update the component.
	/// Syncs entity transforms to proxies, performs visibility culling,
	/// and builds CPU-side instance data.
	public void OnUpdate(float deltaTime)
	{
		if (mScene == null)
			return;

		// Sync entity transforms to proxies
		SyncProxies();

		// Prepare render world for this frame
		mRenderWorld.BeginFrame();

		// Perform visibility determination and build instance data
		if (let camera = mRenderWorld.MainCamera)
		{
			// Resolve visibility (frustum culling, LOD selection, sorting)
			mVisibilityResolver.Resolve(mRenderWorld, camera);

			// Get visible meshes
			mVisibleMeshes.Clear();
			mVisibleMeshes.AddRange(mVisibilityResolver.OpaqueMeshes);
			mVisibleMeshes.AddRange(mVisibilityResolver.TransparentMeshes);

			// Build CPU-side instance data from visible meshes
			BuildInstanceData();
		}

		// Gather active lights
		mRenderWorld.GetValidLightProxies(mActiveLights);
	}

	/// Called when the scene state changes.
	public void OnSceneStateChanged(SceneState oldState, SceneState newState)
	{
		if (newState == .Unloaded)
		{
			CleanupRendering();
			mRenderWorld.Clear();
			mMeshProxies.Clear();
			mLightProxies.Clear();
			mCameraProxies.Clear();
		}
	}

	// ==================== ISerializable Implementation ====================

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer serializer)
	{
		var version = SerializationVersion;
		var result = serializer.Version(ref version);
		if (result != .Ok)
			return result;

		// RenderSceneComponent doesn't serialize its proxies - they're recreated
		// from entity components when the scene loads
		return .Ok;
	}

	// ==================== Rendering Initialization ====================

	/// Initializes GPU rendering resources.
	/// Call this after the swap chain is created to set up pipelines and buffers.
	public Result<void> InitializeRendering(TextureFormat colorFormat, TextureFormat depthFormat, bool flipProjection = false)
	{
		if (mRenderingInitialized)
			return .Ok;

		if (mRendererService?.Device == null)
			return .Err;

		mColorFormat = colorFormat;
		mDepthFormat = depthFormat;
		mFlipProjection = flipProjection;

		let device = mRendererService.Device;

		// Create per-frame buffers
		for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++)
		{
			// Camera uniform buffer
			BufferDescriptor cameraDesc = .((uint64)sizeof(SceneCameraUniforms), .Uniform, .Upload);
			if (device.CreateBuffer(&cameraDesc) case .Ok(let buf))
				mFrameResources[i].CameraBuffer = buf;
			else
				return .Err;

			// Instance buffer
			uint64 instanceBufferSize = (uint64)(sizeof(RenderSceneInstanceData) * MAX_INSTANCES);
			BufferDescriptor instanceDesc = .(instanceBufferSize, .Vertex, .Upload);
			if (device.CreateBuffer(&instanceDesc) case .Ok(let instBuf))
				mFrameResources[i].InstanceBuffer = instBuf;
			else
				return .Err;
		}

		// Create pipeline
		if (CreatePipeline() case .Err)
			return .Err;

		mRenderingInitialized = true;
		return .Ok;
	}

	private Result<void> CreatePipeline()
	{
		let device = mRendererService.Device;
		let shaderLibrary = mRendererService.ShaderLibrary;

		// Load shaders from Framework.Renderer shaders folder
		let vertResult = shaderLibrary.GetShader("scene_instanced", .Vertex);
		if (vertResult case .Err)
			return .Err;
		let vertShader = vertResult.Get();

		let fragResult = shaderLibrary.GetShader("scene_instanced", .Fragment);
		if (fragResult case .Err)
			return .Err;
		let fragShader = fragResult.Get();

		// Bind group layout
		BindGroupLayoutEntry[1] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex | .Fragment)
		);
		BindGroupLayoutDescriptor bindLayoutDesc = .(layoutEntries);
		if (device.CreateBindGroupLayout(&bindLayoutDesc) not case .Ok(let layout))
			return .Err;
		mBindGroupLayout = layout;

		// Pipeline layout
		IBindGroupLayout[1] layouts = .(mBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (device.CreatePipelineLayout(&pipelineLayoutDesc) not case .Ok(let pipelineLayout))
			return .Err;
		mPipelineLayout = pipelineLayout;

		// Create per-frame bind groups
		for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++)
		{
			BindGroupEntry[1] entries = .(
				BindGroupEntry.Buffer(0, mFrameResources[i].CameraBuffer)
			);
			BindGroupDescriptor bindGroupDesc = .(mBindGroupLayout, entries);
			if (device.CreateBindGroup(&bindGroupDesc) not case .Ok(let group))
				return .Err;
			mFrameResources[i].BindGroup = group;
		}

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
			DepthStencil = depthState,
			Multisample = .()
			{
				Count = 1,
				Mask = uint32.MaxValue
			}
		};

		if (device.CreateRenderPipeline(&pipelineDesc) not case .Ok(let pipeline))
			return .Err;
		mPipeline = pipeline;

		return .Ok;
	}

	private void CleanupRendering()
	{
		if (!mRenderingInitialized)
			return;

		// Delete per-frame resources
		for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++)
			mFrameResources[i].Dispose();

		mRenderingInitialized = false;
	}

	// ==================== Frame Rendering ====================

	/// Builds CPU-side instance data from visible meshes.
	/// Called during OnUpdate.
	private void BuildInstanceData()
	{
		mInstanceCount = 0;

		for (let proxy in mVisibleMeshes)
		{
			if (mInstanceCount >= MAX_INSTANCES)
				break;

			// Get color based on material ID (simple palette for now)
			let color = GetColorForMaterial(proxy.GetMaterial(0));
			mInstanceData[mInstanceCount] = .(proxy.Transform, color);
			mInstanceCount++;
		}
	}

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

	/// Uploads per-frame GPU data.
	/// Call this in OnPrepareFrame after the fence wait.
	public void PrepareGPU(int32 frameIndex)
	{
		if (!mRenderingInitialized || mRendererService?.Device == null)
			return;

		mCurrentFrameIndex = frameIndex;
		ref SceneFrameResources frame = ref mFrameResources[frameIndex];
		let device = mRendererService.Device;

		// Upload instance data
		if (mInstanceCount > 0)
		{
			uint64 dataSize = (uint64)(sizeof(RenderSceneInstanceData) * mInstanceCount);
			Span<uint8> data = .((uint8*)mInstanceData.Ptr, (int)dataSize);
			device.Queue.WriteBuffer(frame.InstanceBuffer, 0, data);
		}

		// Upload camera uniforms
		if (let cameraProxy = mRenderWorld.MainCamera)
		{
			var projection = cameraProxy.ProjectionMatrix;
			let view = cameraProxy.ViewMatrix;

			if (mFlipProjection)
				projection.M22 = -projection.M22;

			SceneCameraUniforms cameraData = .();
			cameraData.ViewProjection = view * projection;
			cameraData.CameraPosition = cameraProxy.Position;

			// DEBUG: Print camera info on first few frames
			static int32 debugCount = 0;
			if (debugCount < 3)
			{
				debugCount++;
				Console.WriteLine($"[CAM DEBUG] Pos=({cameraProxy.Position.X:F2},{cameraProxy.Position.Y:F2},{cameraProxy.Position.Z:F2}) Fwd=({cameraProxy.Forward.X:F2},{cameraProxy.Forward.Y:F2},{cameraProxy.Forward.Z:F2})");
				Console.WriteLine($"  View M11={view.M11:F4} M22={view.M22:F4} M33={view.M33:F4} M43={view.M43:F4}");
				Console.WriteLine($"  Proj M11={projection.M11:F4} M22={projection.M22:F4}");
			}

			Span<uint8> camData = .((uint8*)&cameraData, sizeof(SceneCameraUniforms));
			device.Queue.WriteBuffer(frame.CameraBuffer, 0, camData);
		}
	}

	/// Renders the scene to the given render pass.
	/// Call this in OnRender.
	public void Render(IRenderPassEncoder renderPass, uint32 viewportWidth, uint32 viewportHeight)
	{
		if (!mRenderingInitialized || mInstanceCount == 0)
			return;

		renderPass.SetViewport(0, 0, viewportWidth, viewportHeight, 0, 1);
		renderPass.SetScissorRect(0, 0, viewportWidth, viewportHeight);

		ref SceneFrameResources frame = ref mFrameResources[mCurrentFrameIndex];

		renderPass.SetPipeline(mPipeline);
		renderPass.SetBindGroup(0, frame.BindGroup);

		// Draw each visible mesh
		// For now, we batch by mesh handle - all instances with same mesh drawn together
		// TODO: Implement proper batching by mesh handle

		let resourceManager = mRendererService.ResourceManager;
		if (resourceManager == null)
			return;

		// Simple approach: draw all visible meshes using their GPU mesh
		int32 instanceOffset = 0;
		GPUMeshHandle lastMesh = .Invalid;

		for (int32 i = 0; i < mInstanceCount; i++)
		{
			let proxy = mVisibleMeshes[i];
			let meshHandle = proxy.MeshHandle;

			// When mesh changes, draw the batch
			if (i > 0 && !meshHandle.Equals(lastMesh))
			{
				DrawMeshBatch(renderPass, resourceManager, lastMesh, frame.InstanceBuffer, instanceOffset, i - instanceOffset);
				instanceOffset = i;
			}

			lastMesh = meshHandle;
		}

		// Draw final batch
		if (mInstanceCount > instanceOffset)
		{
			DrawMeshBatch(renderPass, resourceManager, lastMesh, frame.InstanceBuffer, instanceOffset, mInstanceCount - instanceOffset);
		}

		// End frame on render world
		mRenderWorld.EndFrame();
	}

	private void DrawMeshBatch(IRenderPassEncoder renderPass, GPUResourceManager resourceManager,
		GPUMeshHandle meshHandle, IBuffer instanceBuffer, int32 instanceOffset, int32 instanceCount)
	{
		let gpuMesh = resourceManager.GetMesh(meshHandle);
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

	/// Ends the current frame.
	/// Call this after rendering is complete (called automatically by Render).
	public void EndFrame()
	{
		mRenderWorld.EndFrame();
	}

	// ==================== Proxy Management ====================

	/// Creates a mesh proxy for an entity.
	public ProxyHandle CreateMeshProxy(EntityId entityId, GPUMeshHandle mesh, Matrix transform, BoundingBox bounds)
	{
		// Remove existing proxy if any
		if (mMeshProxies.TryGetValue(entityId, let existing))
		{
			mRenderWorld.DestroyMeshProxy(existing);
			mMeshProxies.Remove(entityId);
		}

		let handle = mRenderWorld.CreateMeshProxy(mesh, transform, bounds);
		if (handle.IsValid)
			mMeshProxies[entityId] = handle;

		return handle;
	}

	/// Creates a directional light proxy for an entity.
	public ProxyHandle CreateDirectionalLight(EntityId entityId, Vector3 direction, Vector3 color, float intensity)
	{
		RemoveLightProxy(entityId);
		let handle = mRenderWorld.CreateDirectionalLight(direction, color, intensity);
		if (handle.IsValid)
			mLightProxies[entityId] = handle;
		return handle;
	}

	/// Creates a point light proxy for an entity.
	public ProxyHandle CreatePointLight(EntityId entityId, Vector3 position, Vector3 color, float intensity, float range)
	{
		RemoveLightProxy(entityId);
		let handle = mRenderWorld.CreatePointLight(position, color, intensity, range);
		if (handle.IsValid)
			mLightProxies[entityId] = handle;
		return handle;
	}

	/// Creates a spot light proxy for an entity.
	public ProxyHandle CreateSpotLight(EntityId entityId, Vector3 position, Vector3 direction, Vector3 color,
		float intensity, float range, float innerAngle, float outerAngle)
	{
		RemoveLightProxy(entityId);
		let handle = mRenderWorld.CreateSpotLight(position, direction, color, intensity, range, innerAngle, outerAngle);
		if (handle.IsValid)
			mLightProxies[entityId] = handle;
		return handle;
	}

	/// Creates a camera proxy for an entity.
	public ProxyHandle CreateCameraProxy(EntityId entityId, Camera camera, uint32 viewportWidth, uint32 viewportHeight, bool isMain = false)
	{
		RemoveCameraProxy(entityId);
		let handle = mRenderWorld.CreateCamera(camera, viewportWidth, viewportHeight, isMain);
		if (handle.IsValid)
		{
			mCameraProxies[entityId] = handle;
			if (isMain)
				mMainCamera = handle;
		}
		return handle;
	}

	/// Destroys a mesh proxy for an entity.
	public void DestroyMeshProxy(EntityId entityId)
	{
		if (mMeshProxies.TryGetValue(entityId, let handle))
		{
			mRenderWorld.DestroyMeshProxy(handle);
			mMeshProxies.Remove(entityId);
		}
	}

	/// Destroys a light proxy for an entity.
	public void RemoveLightProxy(EntityId entityId)
	{
		if (mLightProxies.TryGetValue(entityId, let handle))
		{
			mRenderWorld.DestroyLightProxy(handle);
			mLightProxies.Remove(entityId);
		}
	}

	/// Destroys a camera proxy for an entity.
	public void RemoveCameraProxy(EntityId entityId)
	{
		if (mCameraProxies.TryGetValue(entityId, let handle))
		{
			if (mMainCamera.Equals(handle))
				mMainCamera = .Invalid;
			mRenderWorld.DestroyCameraProxy(handle);
			mCameraProxies.Remove(entityId);
		}
	}

	/// Gets the mesh proxy handle for an entity.
	public ProxyHandle GetMeshProxy(EntityId entityId)
	{
		if (mMeshProxies.TryGetValue(entityId, let handle))
			return handle;
		return .Invalid;
	}

	/// Gets the light proxy handle for an entity.
	public ProxyHandle GetLightProxy(EntityId entityId)
	{
		if (mLightProxies.TryGetValue(entityId, let handle))
			return handle;
		return .Invalid;
	}

	/// Gets the camera proxy handle for an entity.
	public ProxyHandle GetCameraProxy(EntityId entityId)
	{
		if (mCameraProxies.TryGetValue(entityId, let handle))
			return handle;
		return .Invalid;
	}

	// ==================== Frame Sync ====================

	/// Synchronizes all entity transforms to their proxies.
	/// Called each frame during OnUpdate.
	private void SyncProxies()
	{
		if (mScene == null)
			return;

		// Iterate all entities and sync transforms
		for (let entity in mScene.EntityManager)
		{
			let worldMatrix = entity.Transform.WorldMatrix;
			let entityId = entity.Id;

			// Sync mesh proxies
			if (mMeshProxies.TryGetValue(entityId, let meshHandle))
			{
				if (let proxy = mRenderWorld.GetMeshProxy(meshHandle))
				{
					proxy.Transform = worldMatrix;
					proxy.UpdateWorldBounds();
					proxy.Flags |= .Dirty;
				}
			}

			// Sync light proxies
			if (mLightProxies.TryGetValue(entityId, let lightHandle))
			{
				if (let proxy = mRenderWorld.GetLightProxy(lightHandle))
				{
					proxy.Position = entity.Transform.WorldPosition;
					// For directional/spot lights, update direction from forward vector
					if (proxy.Type == .Directional || proxy.Type == .Spot)
						proxy.Direction = entity.Transform.Forward;
				}
			}

			// Sync camera proxies
			if (mCameraProxies.TryGetValue(entityId, let cameraHandle))
			{
				if (let proxy = mRenderWorld.GetCameraProxy(cameraHandle))
				{
					// Use Transform properties directly
					// Note: Transform.Forward uses -Z convention but LookAt produces inverted result
					// so we negate to get the actual look direction
					proxy.Position = entity.Transform.WorldPosition;
					proxy.Forward = -entity.Transform.Forward;  // Negate to fix LookAt convention
					proxy.Up = entity.Transform.Up;
					proxy.Right = -entity.Transform.Right;  // Also negate to keep consistent handedness
					proxy.UpdateMatrices();
				}
			}
		}
	}
}
