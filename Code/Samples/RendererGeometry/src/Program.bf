namespace RendererGeometry;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.Geometry;
using Sedulous.Imaging;
using Sedulous.Framework.Renderer;
using RHI.SampleFramework;

/// Geometry sample demonstrating various geometry types:
/// - Static mesh rendering (cube)
/// - Particle system (fountain)
/// - Skybox (gradient)
class RendererGeometrySample : RHISampleApp
{
	// Renderer components
	private GPUResourceManager mResourceManager;
	private ParticleSystem mParticleSystem;
	private SkyboxRenderer mSkyboxRenderer;

	// Mesh resources
	private GPUMeshHandle mCubeMesh;
	private IBuffer mCameraUniformBuffer;
	private IBuffer mObjectUniformBuffer;
	private ISampler mSampler;

	// Mesh pipeline
	private IBindGroupLayout mMeshBindGroupLayout;
	private IBindGroup mMeshBindGroup;
	private IPipelineLayout mMeshPipelineLayout;
	private IRenderPipeline mMeshPipeline;

	// Particle pipeline
	private IBindGroupLayout mParticleBindGroupLayout;
	private IBindGroup mParticleBindGroup;
	private IPipelineLayout mParticlePipelineLayout;
	private IRenderPipeline mParticlePipeline;

	// Skybox pipeline
	private IBindGroupLayout mSkyboxBindGroupLayout;
	private IBindGroup mSkyboxBindGroup;
	private IPipelineLayout mSkyboxPipelineLayout;
	private IRenderPipeline mSkyboxPipeline;

	// Camera
	private Camera mCamera;

	// Animation state
	private float mCubeRotation = 0.0f;

	public this() : base(.(){ Title = "Renderer Geometry Sample", Width = 1024, Height = 768, ClearColor = .(0.0f, 0.0f, 0.0f, 1.0f), EnableDepth = true })
	{
	}

	protected override bool OnInitialize()
	{
		// Initialize renderer components
		mResourceManager = new GPUResourceManager(Device);

		// Setup camera
		mCamera = .();
		mCamera.Position = .(0, 2, 6);
		mCamera.Forward = Vector3.Normalize(.(0, -0.3f, -1));
		mCamera.UseReverseZ = false;
		mCamera.SetAspectRatio(SwapChain.Width, SwapChain.Height);

		if (!CreateBuffers())
			return false;

		if (!CreateMesh())
			return false;

		if (!CreateParticleSystem())
			return false;

		if (!CreateSkybox())
			return false;

		if (!CreateMeshPipeline())
			return false;

		if (!CreateParticlePipeline())
			return false;

		if (!CreateSkyboxPipeline())
			return false;

		Console.WriteLine("RendererGeometry sample initialized");
		Console.WriteLine("Demonstrating: Static Mesh, Particle System, Skybox");
		return true;
	}

	private bool CreateBuffers()
	{
		// Camera uniform buffer
		BufferDescriptor cameraDesc = .(256, .Uniform, .Upload);
		if (Device.CreateBuffer(&cameraDesc) case .Ok(let buf))
			mCameraUniformBuffer = buf;
		else
			return false;

		// Object uniform buffer
		BufferDescriptor objectDesc = .(128, .Uniform, .Upload);
		if (Device.CreateBuffer(&objectDesc) case .Ok(let objBuf))
			mObjectUniformBuffer = objBuf;
		else
			return false;

		// Sampler
		SamplerDescriptor samplerDesc = .();
		samplerDesc.MinFilter = .Linear;
		samplerDesc.MagFilter = .Linear;
		samplerDesc.MipmapFilter = .Linear;
		samplerDesc.AddressModeU = .ClampToEdge;
		samplerDesc.AddressModeV = .ClampToEdge;
		samplerDesc.AddressModeW = .ClampToEdge;
		if (Device.CreateSampler(&samplerDesc) case .Ok(let sampler))
			mSampler = sampler;
		else
			return false;

		return true;
	}

	private bool CreateMesh()
	{
		// Create a cube mesh
		let cpuMesh = Mesh.CreateCube(1.0f);
		defer delete cpuMesh;

		mCubeMesh = mResourceManager.CreateMesh(cpuMesh);
		if (!mCubeMesh.IsValid)
		{
			Console.WriteLine("Failed to create cube mesh");
			return false;
		}

		Console.WriteLine("Cube mesh created");
		return true;
	}

	private bool CreateParticleSystem()
	{
		mParticleSystem = new ParticleSystem(Device, 1000);

		// Configure as fountain effect
		var config = ref mParticleSystem.Config;
		config.EmissionRate = 80;
		config.MinVelocity = .(-0.8f, 4.0f, -0.8f);
		config.MaxVelocity = .(0.8f, 6.0f, 0.8f);
		config.MinSize = 0.15f;
		config.MaxSize = 0.3f;
		config.MinLife = 1.5f;
		config.MaxLife = 2.5f;
		config.StartColor = .(255, 220, 80, 255);   // Bright yellow-orange
		config.EndColor = .(255, 80, 0, 180);       // Red-orange, semi-transparent
		config.Gravity = .(0, -5.0f, 0);
		config.SizeOverLife = 0.5f;

		// Position emitter to the left of the cube
		mParticleSystem.Position = .(-2.5f, 0.0f, 0.0f);

		Console.WriteLine("Particle system created");
		return true;
	}

	private bool CreateSkybox()
	{
		mSkyboxRenderer = new SkyboxRenderer(Device);

		// Create gradient sky (natural sky colors)
		let topColor = Color(70, 130, 200, 255);     // Deep sky blue
		let bottomColor = Color(180, 210, 240, 255); // Light horizon blue

		if (!mSkyboxRenderer.CreateGradientSky(topColor, bottomColor, 32))
		{
			Console.WriteLine("Failed to create skybox");
			return false;
		}

		Console.WriteLine("Skybox created");
		return true;
	}

	private bool CreateMeshPipeline()
	{
		// Load shaders
		let shaderResult = ShaderUtils.LoadShaderPair(Device, "shaders/simple_mesh");
		if (shaderResult case .Err)
		{
			Console.WriteLine("Failed to load mesh shaders");
			return false;
		}

		let (vertShader, fragShader) = shaderResult.Get();
		defer { delete vertShader; delete fragShader; }

		// Bind group layout: b0=camera, b1=object
		BindGroupLayoutEntry[2] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex | .Fragment),
			BindGroupLayoutEntry.UniformBuffer(1, .Vertex | .Fragment)
		);
		BindGroupLayoutDescriptor bindLayoutDesc = .(layoutEntries);
		if (Device.CreateBindGroupLayout(&bindLayoutDesc) not case .Ok(let layout))
			return false;
		mMeshBindGroupLayout = layout;

		// Pipeline layout
		IBindGroupLayout[1] layouts = .(mMeshBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (Device.CreatePipelineLayout(&pipelineLayoutDesc) not case .Ok(let pipelineLayout))
			return false;
		mMeshPipelineLayout = pipelineLayout;

		// Bind group
		BindGroupEntry[2] entries = .(
			BindGroupEntry.Buffer(0, mCameraUniformBuffer),
			BindGroupEntry.Buffer(1, mObjectUniformBuffer)
		);
		BindGroupDescriptor bindGroupDesc = .(mMeshBindGroupLayout, entries);
		if (Device.CreateBindGroup(&bindGroupDesc) not case .Ok(let group))
			return false;
		mMeshBindGroup = group;

		// Vertex layout for common mesh format
		Sedulous.RHI.VertexAttribute[3] vertexAttrs = .(
			.(VertexFormat.Float3, 0, 0),   // Position
			.(VertexFormat.Float3, 12, 1),  // Normal
			.(VertexFormat.Float2, 24, 2)   // UV
		);
		VertexBufferLayout[1] vertexBuffers = .(.(48, vertexAttrs));

		ColorTargetState[1] colorTargets = .(.(SwapChain.Format));

		DepthStencilState depthState = .();
		depthState.DepthTestEnabled = true;
		depthState.DepthWriteEnabled = true;
		depthState.DepthCompare = .Less;
		depthState.Format = .Depth24PlusStencil8;

		RenderPipelineDescriptor pipelineDesc = .()
		{
			Layout = mMeshPipelineLayout,
			Vertex = .()
			{
				Shader = .(vertShader, "main"),
				Buffers = vertexBuffers
			},
			Fragment = .()
			{
				Shader = .(fragShader, "main"),
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

		if (Device.CreateRenderPipeline(&pipelineDesc) not case .Ok(let pipeline))
		{
			Console.WriteLine("Failed to create mesh pipeline");
			return false;
		}
		mMeshPipeline = pipeline;

		Console.WriteLine("Mesh pipeline created");
		return true;
	}

	private bool CreateParticlePipeline()
	{
		// Load particle shaders
		let shaderResult = ShaderUtils.LoadShaderPair(Device, "shaders/particle");
		if (shaderResult case .Err)
		{
			Console.WriteLine("Failed to load particle shaders");
			return false;
		}

		let (vertShader, fragShader) = shaderResult.Get();
		defer { delete vertShader; delete fragShader; }

		// Bind group layout: b0=camera
		BindGroupLayoutEntry[1] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex)
		);
		BindGroupLayoutDescriptor bindLayoutDesc = .(layoutEntries);
		if (Device.CreateBindGroupLayout(&bindLayoutDesc) not case .Ok(let layout))
			return false;
		mParticleBindGroupLayout = layout;

		// Pipeline layout
		IBindGroupLayout[1] layouts = .(mParticleBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (Device.CreatePipelineLayout(&pipelineLayoutDesc) not case .Ok(let pipelineLayout))
			return false;
		mParticlePipelineLayout = pipelineLayout;

		// Bind group
		BindGroupEntry[1] entries = .(
			BindGroupEntry.Buffer(0, mCameraUniformBuffer)
		);
		BindGroupDescriptor bindGroupDesc = .(mParticleBindGroupLayout, entries);
		if (Device.CreateBindGroup(&bindGroupDesc) not case .Ok(let group))
			return false;
		mParticleBindGroup = group;

		// Vertex layout for ParticleVertex: Position(12) + Size(8) + Color(4) + Rotation(4) = 28 bytes
		Sedulous.RHI.VertexAttribute[4] vertexAttrs = .(
			.(VertexFormat.Float3, 0, 0),   // Position
			.(VertexFormat.Float2, 12, 1),  // Size
			.(VertexFormat.UByte4Normalized, 16, 2), // Color (RGBA bytes)
			.(VertexFormat.Float, 20, 3)   // Rotation
		);
		// Step per instance for instanced rendering
		VertexBufferLayout[1] vertexBuffers = .(
			VertexBufferLayout(28, vertexAttrs, .Instance)
		);

		// Blending for particles (alpha blend)
		ColorTargetState[1] colorTargets = .(
			ColorTargetState(SwapChain.Format, .AlphaBlend)
		);

		// Depth test but no write (particles rendered after opaque)
		DepthStencilState depthState = .();
		depthState.DepthTestEnabled = true;
		depthState.DepthWriteEnabled = false;  // Don't write depth for transparent particles
		depthState.DepthCompare = .Less;
		depthState.Format = .Depth24PlusStencil8;

		RenderPipelineDescriptor pipelineDesc = .()
		{
			Layout = mParticlePipelineLayout,
			Vertex = .()
			{
				Shader = .(vertShader, "main"),
				Buffers = vertexBuffers
			},
			Fragment = .()
			{
				Shader = .(fragShader, "main"),
				Targets = colorTargets
			},
			Primitive = .()
			{
				Topology = .TriangleList,
				FrontFace = .CCW,
				CullMode = .None  // Particles are billboards, no culling
			},
			DepthStencil = depthState,
			Multisample = .()
			{
				Count = 1,
				Mask = uint32.MaxValue
			}
		};

		if (Device.CreateRenderPipeline(&pipelineDesc) not case .Ok(let pipeline))
		{
			Console.WriteLine("Failed to create particle pipeline");
			return false;
		}
		mParticlePipeline = pipeline;

		Console.WriteLine("Particle pipeline created");
		return true;
	}

	private bool CreateSkyboxPipeline()
	{
		// Load skybox shaders
		let shaderResult = ShaderUtils.LoadShaderPair(Device, "shaders/skybox");
		if (shaderResult case .Err)
		{
			Console.WriteLine("Failed to load skybox shaders");
			return false;
		}

		let (vertShader, fragShader) = shaderResult.Get();
		defer { delete vertShader; delete fragShader; }

		// Bind group layout: b0=camera, t0=cubemap, s0=sampler
		BindGroupLayoutEntry[3] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex),
			BindGroupLayoutEntry.SampledTexture(0, .Fragment, .TextureCube),
			BindGroupLayoutEntry.Sampler(0, .Fragment)
		);
		BindGroupLayoutDescriptor bindLayoutDesc = .(layoutEntries);
		if (Device.CreateBindGroupLayout(&bindLayoutDesc) not case .Ok(let layout))
			return false;
		mSkyboxBindGroupLayout = layout;

		// Pipeline layout
		IBindGroupLayout[1] layouts = .(mSkyboxBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (Device.CreatePipelineLayout(&pipelineLayoutDesc) not case .Ok(let pipelineLayout))
			return false;
		mSkyboxPipelineLayout = pipelineLayout;

		// Bind group
		BindGroupEntry[3] entries = .(
			BindGroupEntry.Buffer(0, mCameraUniformBuffer),
			BindGroupEntry.Texture(0, mSkyboxRenderer.CubemapView),
			BindGroupEntry.Sampler(0, mSkyboxRenderer.Sampler)
		);
		BindGroupDescriptor bindGroupDesc = .(mSkyboxBindGroupLayout, entries);
		if (Device.CreateBindGroup(&bindGroupDesc) not case .Ok(let group))
			return false;
		mSkyboxBindGroup = group;

		// No vertex buffers needed - fullscreen triangle uses SV_VertexID
		ColorTargetState[1] colorTargets = .(.(SwapChain.Format));

		// Depth test at far plane, no write
		DepthStencilState depthState = .();
		depthState.DepthTestEnabled = true;
		depthState.DepthWriteEnabled = false;
		depthState.DepthCompare = .LessEqual;  // Skybox at far plane
		depthState.Format = .Depth24PlusStencil8;

		RenderPipelineDescriptor pipelineDesc = .()
		{
			Layout = mSkyboxPipelineLayout,
			Vertex = .()
			{
				Shader = .(vertShader, "main"),
				Buffers = .()  // No vertex buffers
			},
			Fragment = .()
			{
				Shader = .(fragShader, "main"),
				Targets = colorTargets
			},
			Primitive = .()
			{
				Topology = .TriangleList,
				FrontFace = .CCW,
				CullMode = .None
			},
			DepthStencil = depthState,
			Multisample = .()
			{
				Count = 1,
				Mask = uint32.MaxValue
			}
		};

		if (Device.CreateRenderPipeline(&pipelineDesc) not case .Ok(let pipeline))
		{
			Console.WriteLine("Failed to create skybox pipeline");
			return false;
		}
		mSkyboxPipeline = pipeline;

		Console.WriteLine("Skybox pipeline created");
		return true;
	}

	protected override void OnUpdate(float deltaTime, float totalTime)
	{
		// Rotate the cube
		mCubeRotation += deltaTime * 0.5f;

		// Update particle system
		mParticleSystem.Update(deltaTime);
		mParticleSystem.Upload();

		// Update camera uniforms
		CameraUniforms cameraData = .();
		cameraData.ViewProjection = mCamera.ViewProjectionMatrix;
		cameraData.View = mCamera.ViewMatrix;
		cameraData.Projection = mCamera.ProjectionMatrix;
		cameraData.CameraPosition = mCamera.Position;

		Span<uint8> camData = .((uint8*)&cameraData, sizeof(CameraUniforms));
		Device.Queue.WriteBuffer(mCameraUniformBuffer, 0, camData);

		// Update object uniforms for cube
		let model = Matrix4x4.CreateRotationY(mCubeRotation) * Matrix4x4.CreateTranslation(0, 0.5f, 0);
		ObjectUniforms objectData = .();
		objectData.Model = model;
		objectData.ObjectColor = .(1f, 0f, 0f, 1.0f);  // Light blue color

		Span<uint8> objData = .((uint8*)&objectData, sizeof(ObjectUniforms));
		Device.Queue.WriteBuffer(mObjectUniformBuffer, 0, objData);
	}

	protected override void OnRender(IRenderPassEncoder renderPass)
	{
		renderPass.SetViewport(0, 0, SwapChain.Width, SwapChain.Height, 0, 1);
		renderPass.SetScissorRect(0, 0, SwapChain.Width, SwapChain.Height);

		// 1. Render skybox first (at far plane)
		RenderSkybox(renderPass);

		// 2. Render opaque geometry
		RenderMesh(renderPass);

		// 3. Render transparent particles last
		RenderParticles(renderPass);
	}

	private void RenderSkybox(IRenderPassEncoder renderPass)
	{
		if (mSkyboxPipeline == null || mSkyboxBindGroup == null || !mSkyboxRenderer.IsValid)
			return;

		renderPass.SetPipeline(mSkyboxPipeline);
		renderPass.SetBindGroup(0, mSkyboxBindGroup);
		renderPass.Draw(3, 1, 0, 0);  // Fullscreen triangle
	}

	private void RenderMesh(IRenderPassEncoder renderPass)
	{
		let mesh = mResourceManager.GetMesh(mCubeMesh);
		if (mesh == null)
			return;

		renderPass.SetPipeline(mMeshPipeline);
		renderPass.SetBindGroup(0, mMeshBindGroup);
		renderPass.SetVertexBuffer(0, mesh.VertexBuffer, 0);

		if (mesh.IndexBuffer != null)
		{
			renderPass.SetIndexBuffer(mesh.IndexBuffer, mesh.IndexFormat, 0);
			renderPass.DrawIndexed(mesh.IndexCount, 1, 0, 0, 0);
		}
		else
		{
			renderPass.Draw(mesh.VertexCount, 1, 0, 0);
		}
	}

	private void RenderParticles(IRenderPassEncoder renderPass)
	{
		if (mParticlePipeline == null || mParticleBindGroup == null)
			return;

		let particleCount = mParticleSystem.ParticleCount;
		if (particleCount == 0)
			return;

		renderPass.SetPipeline(mParticlePipeline);
		renderPass.SetBindGroup(0, mParticleBindGroup);
		renderPass.SetVertexBuffer(0, mParticleSystem.VertexBuffer, 0);
		renderPass.SetIndexBuffer(mParticleSystem.IndexBuffer, .UInt16, 0);

		// Draw 6 indices per particle (quad), particle count instances
		// Actually, with the current shader expecting instance buffer,
		// we draw 6 vertices per particle instance
		renderPass.DrawIndexed(6, (uint32)particleCount, 0, 0, 0);
	}

	protected override void OnCleanup()
	{
		// Skybox
		if (mSkyboxPipeline != null) delete mSkyboxPipeline;
		if (mSkyboxPipelineLayout != null) delete mSkyboxPipelineLayout;
		if (mSkyboxBindGroup != null) delete mSkyboxBindGroup;
		if (mSkyboxBindGroupLayout != null) delete mSkyboxBindGroupLayout;

		// Particle
		if (mParticlePipeline != null) delete mParticlePipeline;
		if (mParticlePipelineLayout != null) delete mParticlePipelineLayout;
		if (mParticleBindGroup != null) delete mParticleBindGroup;
		if (mParticleBindGroupLayout != null) delete mParticleBindGroupLayout;

		// Mesh
		if (mMeshPipeline != null) delete mMeshPipeline;
		if (mMeshPipelineLayout != null) delete mMeshPipelineLayout;
		if (mMeshBindGroup != null) delete mMeshBindGroup;
		if (mMeshBindGroupLayout != null) delete mMeshBindGroupLayout;

		// Buffers
		if (mSampler != null) delete mSampler;
		if (mObjectUniformBuffer != null) delete mObjectUniformBuffer;
		if (mCameraUniformBuffer != null) delete mCameraUniformBuffer;

		// Renderers
		if (mSkyboxRenderer != null) delete mSkyboxRenderer;
		if (mParticleSystem != null) delete mParticleSystem;

		// Resources
		if (mResourceManager != null)
		{
			mResourceManager.ReleaseMesh(mCubeMesh);
			delete mResourceManager;
		}
	}
}

// Uniform buffer structures
[CRepr]
struct CameraUniforms
{
	public Matrix4x4 ViewProjection;
	public Matrix4x4 View;
	public Matrix4x4 Projection;
	public Vector3 CameraPosition;
	public float _pad0;
}

[CRepr]
struct ObjectUniforms
{
	public Matrix4x4 Model;
	public Vector4 ObjectColor;
}

class Program
{
	public static int Main(String[] args)
	{
		let app = scope RendererGeometrySample();
		return app.Run();
	}
}
