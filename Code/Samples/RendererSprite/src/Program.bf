namespace RendererSprite;

using System;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.Framework.Renderer;
using Sedulous.Shell.Input;
using SampleFramework;

/// Sprite sample demonstrating:
/// - Billboard sprite rendering
/// - Instanced sprite batching
/// - Animated sprite positions and colors
/// - Skybox background
/// - First-person camera controls
class RendererSpriteSample : RHISampleApp
{
	// Renderer components
	private SpriteRenderer mSpriteRenderer;
	private SkyboxRenderer mSkyboxRenderer;

	// Common resources
	private IBuffer mCameraUniformBuffer;

	// Sprite pipeline
	private IBindGroupLayout mSpriteBindGroupLayout;
	private IBindGroup mSpriteBindGroup;
	private IPipelineLayout mSpritePipelineLayout;
	private IRenderPipeline mSpritePipeline;

	// Skybox pipeline
	private IBindGroupLayout mSkyboxBindGroupLayout;
	private IBindGroup mSkyboxBindGroup;
	private IPipelineLayout mSkyboxPipelineLayout;
	private IRenderPipeline mSkyboxPipeline;

	// Camera
	private Camera mCamera;
	private float mCameraYaw = 0.0f;
	private float mCameraPitch = 0.0f;
	private bool mMouseCaptured = false;
	private float mCameraMoveSpeed = 5.0f;
	private float mCameraLookSpeed = 0.003f;

	public this() : base(.()
	{
		Title = "Renderer Sprite - Billboard Sprites",
		Width = 1024,
		Height = 768,
		ClearColor = .(0.0f, 0.0f, 0.0f, 1.0f),
		EnableDepth = true
	})
	{
	}

	protected override bool OnInitialize()
	{
		// Setup camera
		mCamera = .();
		mCamera.Position = .(0, 2, 8);
		mCamera.UseReverseZ = false;
		mCamera.SetAspectRatio(SwapChain.Width, SwapChain.Height);

		mCameraYaw = Math.PI_f;
		mCameraPitch = -0.1f;
		UpdateCameraDirection();

		if (!CreateBuffers())
			return false;

		if (!CreateSkybox())
			return false;

		if (!CreateSprites())
			return false;

		if (!CreateSkyboxPipeline())
			return false;

		if (!CreateSpritePipeline())
			return false;

		Console.WriteLine("RendererSprite sample initialized");
		Console.WriteLine("Controls: WASD=Move, QE=Up/Down, Right-click+Drag=Look, Tab=Toggle mouse capture");
		return true;
	}

	private void UpdateCameraDirection()
	{
		float cosP = Math.Cos(mCameraPitch);
		mCamera.Forward = Vector3.Normalize(.(
			Math.Sin(mCameraYaw) * cosP,
			Math.Sin(mCameraPitch),
			Math.Cos(mCameraYaw) * cosP
		));
	}

	protected override void OnInput()
	{
		let keyboard = Shell.InputManager.Keyboard;
		let mouse = Shell.InputManager.Mouse;

		if (keyboard.IsKeyPressed(.Tab))
		{
			mMouseCaptured = !mMouseCaptured;
			mouse.RelativeMode = mMouseCaptured;
			mouse.Visible = !mMouseCaptured;
		}

		if (mMouseCaptured || mouse.IsButtonDown(.Right))
		{
			mCameraYaw -= mouse.DeltaX * mCameraLookSpeed;
			mCameraPitch -= mouse.DeltaY * mCameraLookSpeed;
			mCameraPitch = Math.Clamp(mCameraPitch, -Math.PI_f * 0.49f, Math.PI_f * 0.49f);
			UpdateCameraDirection();
		}

		let forward = mCamera.Forward;
		let right = mCamera.Right;
		let up = Vector3(0, 1, 0);
		float speed = mCameraMoveSpeed * DeltaTime;

		if (keyboard.IsKeyDown(.W)) mCamera.Position = mCamera.Position + forward * speed;
		if (keyboard.IsKeyDown(.S)) mCamera.Position = mCamera.Position - forward * speed;
		if (keyboard.IsKeyDown(.A)) mCamera.Position = mCamera.Position - right * speed;
		if (keyboard.IsKeyDown(.D)) mCamera.Position = mCamera.Position + right * speed;
		if (keyboard.IsKeyDown(.Q)) mCamera.Position = mCamera.Position - up * speed;
		if (keyboard.IsKeyDown(.E)) mCamera.Position = mCamera.Position + up * speed;

		if (keyboard.IsKeyDown(.LeftShift) || keyboard.IsKeyDown(.RightShift))
		{
			if (keyboard.IsKeyDown(.W)) mCamera.Position = mCamera.Position + forward * speed;
			if (keyboard.IsKeyDown(.S)) mCamera.Position = mCamera.Position - forward * speed;
			if (keyboard.IsKeyDown(.A)) mCamera.Position = mCamera.Position - right * speed;
			if (keyboard.IsKeyDown(.D)) mCamera.Position = mCamera.Position + right * speed;
			if (keyboard.IsKeyDown(.Q)) mCamera.Position = mCamera.Position - up * speed;
			if (keyboard.IsKeyDown(.E)) mCamera.Position = mCamera.Position + up * speed;
		}
	}

	private bool CreateBuffers()
	{
		BufferDescriptor cameraDesc = .(256, .Uniform, .Upload);
		if (Device.CreateBuffer(&cameraDesc) case .Ok(let buf))
			mCameraUniformBuffer = buf;
		else
			return false;

		return true;
	}

	private bool CreateSkybox()
	{
		mSkyboxRenderer = new SkyboxRenderer(Device);

		let topColor = Color(40, 60, 100, 255);      // Dark blue
		let bottomColor = Color(20, 30, 50, 255);   // Very dark blue

		if (!mSkyboxRenderer.CreateGradientSky(topColor, bottomColor, 32))
		{
			Console.WriteLine("Failed to create skybox");
			return false;
		}

		Console.WriteLine("Skybox created");
		return true;
	}

	private bool CreateSprites()
	{
		mSpriteRenderer = new SpriteRenderer(Device, 1000);
		Console.WriteLine("Sprite renderer created");
		return true;
	}

	private bool CreateSkyboxPipeline()
	{
		let shaderResult = ShaderUtils.LoadShaderPair(Device, "../../Sedulous/Sedulous.Framework.Renderer/shaders/skybox");
		if (shaderResult case .Err)
		{
			Console.WriteLine("Failed to load skybox shaders");
			return false;
		}

		let (vertShader, fragShader) = shaderResult.Get();
		defer { delete vertShader; delete fragShader; }

		BindGroupLayoutEntry[3] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex),
			BindGroupLayoutEntry.SampledTexture(0, .Fragment, .TextureCube),
			BindGroupLayoutEntry.Sampler(0, .Fragment)
		);
		BindGroupLayoutDescriptor bindLayoutDesc = .(layoutEntries);
		if (Device.CreateBindGroupLayout(&bindLayoutDesc) not case .Ok(let layout))
			return false;
		mSkyboxBindGroupLayout = layout;

		IBindGroupLayout[1] layouts = .(mSkyboxBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (Device.CreatePipelineLayout(&pipelineLayoutDesc) not case .Ok(let pipelineLayout))
			return false;
		mSkyboxPipelineLayout = pipelineLayout;

		BindGroupEntry[3] entries = .(
			BindGroupEntry.Buffer(0, mCameraUniformBuffer),
			BindGroupEntry.Texture(0, mSkyboxRenderer.CubemapView),
			BindGroupEntry.Sampler(0, mSkyboxRenderer.Sampler)
		);
		BindGroupDescriptor bindGroupDesc = .(mSkyboxBindGroupLayout, entries);
		if (Device.CreateBindGroup(&bindGroupDesc) not case .Ok(let group))
			return false;
		mSkyboxBindGroup = group;

		ColorTargetState[1] colorTargets = .(.(SwapChain.Format));

		DepthStencilState depthState = .();
		depthState.DepthTestEnabled = true;
		depthState.DepthWriteEnabled = false;
		depthState.DepthCompare = .LessEqual;
		depthState.Format = .Depth24PlusStencil8;

		RenderPipelineDescriptor pipelineDesc = .()
		{
			Layout = mSkyboxPipelineLayout,
			Vertex = .() { Shader = .(vertShader, "main"), Buffers = .() },
			Fragment = .() { Shader = .(fragShader, "main"), Targets = colorTargets },
			Primitive = .() { Topology = .TriangleList, FrontFace = .CCW, CullMode = .None },
			DepthStencil = depthState,
			Multisample = .() { Count = 1, Mask = uint32.MaxValue }
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

	private bool CreateSpritePipeline()
	{
		let shaderResult = ShaderUtils.LoadShaderPair(Device, "shaders/sprite");
		if (shaderResult case .Err)
		{
			Console.WriteLine("Failed to load sprite shaders");
			return false;
		}

		let (vertShader, fragShader) = shaderResult.Get();
		defer { delete vertShader; delete fragShader; }

		BindGroupLayoutEntry[1] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex)
		);
		BindGroupLayoutDescriptor bindLayoutDesc = .(layoutEntries);
		if (Device.CreateBindGroupLayout(&bindLayoutDesc) not case .Ok(let layout))
			return false;
		mSpriteBindGroupLayout = layout;

		IBindGroupLayout[1] layouts = .(mSpriteBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (Device.CreatePipelineLayout(&pipelineLayoutDesc) not case .Ok(let pipelineLayout))
			return false;
		mSpritePipelineLayout = pipelineLayout;

		BindGroupEntry[1] entries = .(
			BindGroupEntry.Buffer(0, mCameraUniformBuffer)
		);
		BindGroupDescriptor bindGroupDesc = .(mSpriteBindGroupLayout, entries);
		if (Device.CreateBindGroup(&bindGroupDesc) not case .Ok(let group))
			return false;
		mSpriteBindGroup = group;

		// SpriteInstance layout: Position(12) + Size(8) + UVRect(16) + Color(4) = 40 bytes
		Sedulous.RHI.VertexAttribute[4] vertexAttrs = .(
			.(VertexFormat.Float3, 0, 0),
			.(VertexFormat.Float2, 12, 1),
			.(VertexFormat.Float4, 20, 2),
			.(VertexFormat.UByte4Normalized, 36, 3)
		);
		VertexBufferLayout[1] vertexBuffers = .(
			VertexBufferLayout(40, vertexAttrs, .Instance)
		);

		ColorTargetState[1] colorTargets = .(
			ColorTargetState(SwapChain.Format, .AlphaBlend)
		);

		DepthStencilState depthState = .();
		depthState.DepthTestEnabled = true;
		depthState.DepthWriteEnabled = false;
		depthState.DepthCompare = .Less;
		depthState.Format = .Depth24PlusStencil8;

		RenderPipelineDescriptor pipelineDesc = .()
		{
			Layout = mSpritePipelineLayout,
			Vertex = .() { Shader = .(vertShader, "main"), Buffers = vertexBuffers },
			Fragment = .() { Shader = .(fragShader, "main"), Targets = colorTargets },
			Primitive = .() { Topology = .TriangleList, FrontFace = .CCW, CullMode = .None },
			DepthStencil = depthState,
			Multisample = .() { Count = 1, Mask = uint32.MaxValue }
		};

		if (Device.CreateRenderPipeline(&pipelineDesc) not case .Ok(let pipeline))
		{
			Console.WriteLine("Failed to create sprite pipeline");
			return false;
		}
		mSpritePipeline = pipeline;

		Console.WriteLine("Sprite pipeline created");
		return true;
	}

	protected override void OnUpdate(float deltaTime, float totalTime)
	{
		var projection = mCamera.ProjectionMatrix;
		let view = mCamera.ViewMatrix;

		if (Device.FlipProjectionRequired)
			projection.M22 = -projection.M22;

		BillboardCameraUniforms cameraData = .();
		cameraData.ViewProjection = view * projection;
		cameraData.View = view;
		cameraData.Projection = projection;
		cameraData.CameraPosition = mCamera.Position;

		Span<uint8> camData = .((uint8*)&cameraData, sizeof(BillboardCameraUniforms));
		Device.Queue.WriteBuffer(mCameraUniformBuffer, 0, camData);

		// Update sprites - animated circle of floating sprites
		mSpriteRenderer.Begin();

		// Add 16 floating sprites in a circle
		for (int i = 0; i < 16; i++)
		{
			float angle = (float)i / 16.0f * Math.PI_f * 2.0f + totalTime * 0.5f;
			float radius = 4.0f;
			float x = Math.Cos(angle) * radius;
			float z = Math.Sin(angle) * radius;
			float y = 2.0f + Math.Sin(totalTime * 2.0f + (float)i * 0.4f) * 0.8f;

			// Cycle through colors
			uint8 r = (uint8)(128 + 127 * Math.Sin(totalTime + (float)i * 0.5f));
			uint8 g = (uint8)(128 + 127 * Math.Sin(totalTime * 1.3f + (float)i * 0.7f));
			uint8 b = (uint8)(128 + 127 * Math.Sin(totalTime * 0.7f + (float)i * 0.3f));

			// Pulsing size
			float size = 0.4f + 0.2f * Math.Sin(totalTime * 3.0f + (float)i * 0.5f);

			mSpriteRenderer.AddSprite(.(x, y, z), .(size, size), Color(r, g, b, 230));
		}

		// Add inner ring of smaller sprites
		for (int i = 0; i < 8; i++)
		{
			float angle = (float)i / 8.0f * Math.PI_f * 2.0f - totalTime * 0.8f;
			float radius = 2.0f;
			float x = Math.Cos(angle) * radius;
			float z = Math.Sin(angle) * radius;
			float y = 1.5f + Math.Sin(totalTime * 3.0f + (float)i * 0.5f) * 0.5f;

			mSpriteRenderer.AddSprite(.(x, y, z), .(0.3f, 0.3f), Color(255, 255, 200, 200));
		}

		// Center sprite
		float centerPulse = 0.8f + 0.3f * Math.Sin(totalTime * 2.0f);
		mSpriteRenderer.AddSprite(.(0, 2.0f, 0), .(centerPulse, centerPulse), Color(255, 255, 255, 255));

		mSpriteRenderer.End();
	}

	protected override void OnRender(IRenderPassEncoder renderPass)
	{
		renderPass.SetViewport(0, 0, SwapChain.Width, SwapChain.Height, 0, 1);
		renderPass.SetScissorRect(0, 0, SwapChain.Width, SwapChain.Height);

		// Render skybox first
		if (mSkyboxPipeline != null && mSkyboxBindGroup != null && mSkyboxRenderer.IsValid)
		{
			renderPass.SetPipeline(mSkyboxPipeline);
			renderPass.SetBindGroup(0, mSkyboxBindGroup);
			renderPass.Draw(3, 1, 0, 0);
		}

		// Render sprites
		if (mSpritePipeline != null && mSpriteBindGroup != null)
		{
			let spriteCount = mSpriteRenderer.SpriteCount;
			if (spriteCount > 0)
			{
				renderPass.SetPipeline(mSpritePipeline);
				renderPass.SetBindGroup(0, mSpriteBindGroup);
				renderPass.SetVertexBuffer(0, mSpriteRenderer.InstanceBuffer, 0);
				renderPass.Draw(6, (uint32)spriteCount, 0, 0);
			}
		}
	}

	protected override void OnCleanup()
	{
		if (mSpritePipeline != null) delete mSpritePipeline;
		if (mSpritePipelineLayout != null) delete mSpritePipelineLayout;
		if (mSpriteBindGroup != null) delete mSpriteBindGroup;
		if (mSpriteBindGroupLayout != null) delete mSpriteBindGroupLayout;

		if (mSkyboxPipeline != null) delete mSkyboxPipeline;
		if (mSkyboxPipelineLayout != null) delete mSkyboxPipelineLayout;
		if (mSkyboxBindGroup != null) delete mSkyboxBindGroup;
		if (mSkyboxBindGroupLayout != null) delete mSkyboxBindGroupLayout;

		if (mCameraUniformBuffer != null) delete mCameraUniformBuffer;

		if (mSpriteRenderer != null) delete mSpriteRenderer;
		if (mSkyboxRenderer != null) delete mSkyboxRenderer;
	}
}

class Program
{
	public static int Main(String[] args)
	{
		let app = scope RendererSpriteSample();
		return app.Run();
	}
}
