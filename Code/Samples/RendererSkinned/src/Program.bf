namespace RendererSkinned;

using System;
using System.IO;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.Geometry;
using Sedulous.Geometry.Tooling;
using Sedulous.Imaging;
using Sedulous.Models;
using Sedulous.Models.GLTF;
using Sedulous.Engine.Renderer;
using Sedulous.Shell.Input;
using SampleFramework;

/// Skinned mesh sample demonstrating:
/// - GLTF skeletal mesh loading (Fox)
/// - Bone/joint animation playback
/// - Animation cycling with keyboard
/// - Skybox background
/// - First-person camera controls
class RendererSkinnedSample : RHISampleApp
{
	// Renderer components
	private GPUResourceManager mResourceManager;
	private SkyboxRenderer mSkyboxRenderer;

	// Fox (skinned mesh) resources
	private Model mFoxModel;
	private SkinnedMeshResource mFoxResource ~ delete _;
	private GPUSkinnedMeshHandle mFoxGPUMesh;
	private ITexture mFoxTexture;
	private ITextureView mFoxTextureView;
	private AnimationPlayer mFoxAnimPlayer;
	private int32 mCurrentAnimIndex = 0;

	// Common resources
	private IBuffer mCameraUniformBuffer;
	private IBuffer mObjectUniformBuffer;
	private IBuffer mBoneBuffer;
	private ISampler mSampler;

	// Skinned mesh pipeline
	private IBindGroupLayout mSkinnedBindGroupLayout;
	private IBindGroup mSkinnedBindGroup;
	private IPipelineLayout mSkinnedPipelineLayout;
	private IRenderPipeline mSkinnedPipeline;

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
		Title = "Renderer Skinned - Animated Fox",
		Width = 1024,
		Height = 768,
		ClearColor = .(0.0f, 0.0f, 0.0f, 1.0f),
		EnableDepth = true
	})
	{
	}

	protected override bool OnInitialize()
	{
		mResourceManager = new GPUResourceManager(Device);

		// Setup camera
		mCamera = .();
		mCamera.Position = .(0, 50, 150);
		mCamera.UseReverseZ = false;
		mCamera.SetAspectRatio(SwapChain.Width, SwapChain.Height);

		mCameraYaw = Math.PI_f;
		mCameraPitch = -0.1f;
		UpdateCameraDirection();

		if (!CreateBuffers())
			return false;

		if (!CreateSkybox())
			return false;

		if (!LoadFoxModel())
			return false;

		if (!CreateSkyboxPipeline())
			return false;

		if (!CreateSkinnedPipeline())
			return false;

		Console.WriteLine("RendererSkinned sample initialized");
		Console.WriteLine("Controls: WASD=Move, QE=Up/Down, Right-click+Drag=Look, Tab=Toggle mouse capture");
		Console.WriteLine("          Left/Right or ,/. = Cycle Fox animations");
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
		float speed = mCameraMoveSpeed * DeltaTime * 50;  // Scaled for model size

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

		// Cycle through Fox animations
		if (mFoxAnimPlayer != null && mFoxResource != null && mFoxResource.AnimationCount > 0)
		{
			if (keyboard.IsKeyPressed(.Right) || keyboard.IsKeyPressed(.Period))
			{
				mCurrentAnimIndex = (mCurrentAnimIndex + 1) % (int32)mFoxResource.AnimationCount;
				mFoxAnimPlayer.Play(mFoxResource.Animations[mCurrentAnimIndex]);
				Console.WriteLine(scope $"Playing animation: {mFoxResource.Animations[mCurrentAnimIndex].Name}");
			}
			if (keyboard.IsKeyPressed(.Left) || keyboard.IsKeyPressed(.Comma))
			{
				mCurrentAnimIndex = (mCurrentAnimIndex - 1 + (int32)mFoxResource.AnimationCount) % (int32)mFoxResource.AnimationCount;
				mFoxAnimPlayer.Play(mFoxResource.Animations[mCurrentAnimIndex]);
				Console.WriteLine(scope $"Playing animation: {mFoxResource.Animations[mCurrentAnimIndex].Name}");
			}
		}
	}

	private bool CreateBuffers()
	{
		BufferDescriptor cameraDesc = .(256, .Uniform, .Upload);
		if (Device.CreateBuffer(&cameraDesc) case .Ok(let buf))
			mCameraUniformBuffer = buf;
		else
			return false;

		BufferDescriptor objectDesc = .(128, .Uniform, .Upload);
		if (Device.CreateBuffer(&objectDesc) case .Ok(let objBuf))
			mObjectUniformBuffer = objBuf;
		else
			return false;

		// Bone buffer: 128 bones * 64 bytes per matrix = 8192 bytes
		BufferDescriptor boneDesc = .(128 * 64, .Uniform, .Upload);
		if (Device.CreateBuffer(&boneDesc) case .Ok(let boneBuf))
			mBoneBuffer = boneBuf;
		else
			return false;

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

	private bool CreateSkybox()
	{
		mSkyboxRenderer = new SkyboxRenderer(Device);

		let topColor = Color(70, 130, 200, 255);
		let bottomColor = Color(180, 210, 240, 255);

		if (!mSkyboxRenderer.CreateGradientSky(topColor, bottomColor, 32))
		{
			Console.WriteLine("Failed to create skybox");
			return false;
		}

		Console.WriteLine("Skybox created");
		return true;
	}

	private bool LoadFoxModel()
	{
		//let cachedPath = "models/Fox/Fox.skinnedmesh";
		//let outputDir = "models/Fox/imported";

		// Try to load from cached resource first
		/*if (File.Exists(cachedPath))
		{
			Console.WriteLine("Loading Fox from cached resource...");
			if (ResourceSerializer.LoadSkinnedMeshBundle(cachedPath) case .Ok(let resource))
			{
				mFoxResource = resource;
				Console.WriteLine(scope $"Fox resource loaded from cache: {mFoxResource.Mesh.VertexCount} vertices, {mFoxResource.Skeleton?.BoneCount ?? 0} bones, {mFoxResource.AnimationCount} animations");
				mFoxGPUMesh = mResourceManager.CreateSkinnedMesh(mFoxResource.Mesh);
			}
			else
			{
				Console.WriteLine("Failed to load cached Fox resource, falling back to GLTF import...");
			}
		}*/

		// If not loaded from cache, import from GLTF using ModelImporter
		if (mFoxResource == null)
		{
			mFoxModel = new Model();
			let loader = scope GltfLoader();

			let gltfPath = GetAssetPath("samples/models/Fox/glTF/Fox.gltf", .. scope .());
			let result = loader.Load(gltfPath, mFoxModel);
			if (result != .Ok)
			{
				Console.WriteLine(scope $"Failed to load Fox model: {result}");
				delete mFoxModel;
				mFoxModel = null;
				return false;
			}

			Console.WriteLine(scope $"Fox model loaded: {mFoxModel.Meshes.Count} meshes, {mFoxModel.Bones.Count} bones, {mFoxModel.Animations.Count} animations, {mFoxModel.Textures.Count} textures, {mFoxModel.Materials.Count} materials");

			// Use ModelImporter to convert all resources
			let importOptions = new ModelImportOptions();
			importOptions.Flags = .SkinnedMeshes | .Skeletons | .Animations | .Textures | .Materials;
			let gltfBasePath = GetAssetPath("samples/models/Fox/glTF", .. scope .());
			importOptions.BasePath.Set(gltfBasePath);

			let imageLoader = scope SDLImageLoader();
			let importer = scope ModelImporter(importOptions, imageLoader);
			let importResult = importer.Import(mFoxModel);
			defer delete importResult;

			if (!importResult.Success)
			{
				Console.WriteLine("Import errors:");
				for (let err in importResult.Errors)
					Console.WriteLine(scope $"  - {err}");
				return false;
			}

			for (let warn in importResult.Warnings)
				Console.WriteLine(scope $"Import warning: {warn}");

			Console.WriteLine(scope $"Import result: {importResult.SkinnedMeshes.Count} skinned meshes, {importResult.Skeletons.Count} skeletons, {importResult.Textures.Count} textures, {importResult.Materials.Count} materials");

			// Save all imported resources to the output directory
			/*Console.WriteLine(scope $"Saving import result to: {outputDir}");
			if (ResourceSerializer.SaveImportResult(importResult, outputDir) case .Ok)
			{
				Console.WriteLine("Import result saved successfully!");

				// List the saved files
				if (Directory.Exists(outputDir))
				{
					Console.WriteLine("Saved files:");
					for (let entry in Directory.EnumerateFiles(outputDir))
					{
						let fileName = scope String();
						entry.GetFileName(fileName);
						Console.WriteLine(scope $"  - {fileName}");
					}
				}
			}
			else
			{
				Console.WriteLine("Failed to save import result");
			}*/

			// Take ownership of the first skinned mesh for rendering
			if (importResult.SkinnedMeshes.Count > 0)
			{
				mFoxResource = importResult.TakeSkinnedMesh(0);
				Console.WriteLine(scope $"Fox resource: {mFoxResource.Mesh.VertexCount} vertices, {mFoxResource.Skeleton?.BoneCount ?? 0} bones, {mFoxResource.AnimationCount} animations");

				// Also save as bundle for faster loading next time
				//if (ResourceSerializer.SaveSkinnedMeshBundle(mFoxResource, cachedPath) case .Ok)
				//	Console.WriteLine(scope $"Fox bundle saved to: {cachedPath}");

				mFoxGPUMesh = mResourceManager.CreateSkinnedMesh(mFoxResource.Mesh);
			}
			else
			{
				Console.WriteLine("No skinned meshes in import result");
				return false;
			}
		}

		// Create AnimationPlayer and start playing
		if (mFoxResource?.Skeleton != null && mFoxResource.AnimationCount > 0)
		{
			mFoxAnimPlayer = mFoxResource.CreatePlayer();
			mFoxAnimPlayer.Play(mFoxResource.Animations[0]);
			Console.WriteLine(scope $"Fox animation player started: {mFoxResource.Animations[0].Name}");
		}

		// Load texture - try model's embedded data first (if loaded from GLTF)
		bool textureLoaded = false;
		if (mFoxModel != null && mFoxModel.Textures.Count > 0)
		{
			let tex = mFoxModel.Textures[0];
			if (tex.HasEmbeddedData && tex.Width > 0 && tex.Height > 0)
			{
				Console.WriteLine(scope $"Using embedded texture: {tex.Width}x{tex.Height}, format={tex.PixelFormat}");

				TextureFormat texFormat = .RGBA8Unorm;
				uint32 bytesPerPixel = 4;
				switch (tex.PixelFormat)
				{
				case .RGBA8: texFormat = .RGBA8Unorm; bytesPerPixel = 4;
				case .BGRA8: texFormat = .BGRA8Unorm; bytesPerPixel = 4;
				default: texFormat = .RGBA8Unorm; bytesPerPixel = 4;
				}

				TextureDescriptor texDesc = .Texture2D((uint32)tex.Width, (uint32)tex.Height, texFormat, .Sampled | .CopyDst);
				if (Device.CreateTexture(&texDesc) case .Ok(let texture))
				{
					mFoxTexture = texture;

					TextureDataLayout layout = .() { Offset = 0, BytesPerRow = (uint32)tex.Width * bytesPerPixel, RowsPerImage = (uint32)tex.Height };
					Extent3D size = .((uint32)tex.Width, (uint32)tex.Height, 1);
					Span<uint8> data = .(tex.GetData(), tex.GetDataSize());
					Device.Queue.WriteTexture(mFoxTexture, data, &layout, &size, 0, 0);

					TextureViewDescriptor viewDesc = .() { Format = texFormat, Dimension = .Texture2D, MipLevelCount = 1, ArrayLayerCount = 1 };
					if (Device.CreateTextureView(mFoxTexture, &viewDesc) case .Ok(let view))
					{
						mFoxTextureView = view;
						textureLoaded = true;
					}
				}
			}
		}

		// Fall back to loading from file if not loaded from model
		if (!textureLoaded)
		{
			let texPath = GetAssetPath("samples/models/Fox/glTF/Texture.png", .. scope .());
			let imageLoader = scope SDLImageLoader();
			if (imageLoader.LoadFromFile(texPath) case .Ok(var loadInfo))
			{
				defer loadInfo.Dispose();
				Console.WriteLine(scope $"Fox texture: {loadInfo.Width}x{loadInfo.Height}");

				TextureDescriptor texDesc = .Texture2D(loadInfo.Width, loadInfo.Height, .RGBA8Unorm, .Sampled | .CopyDst);
				if (Device.CreateTexture(&texDesc) case .Ok(let texture))
				{
					mFoxTexture = texture;

					TextureDataLayout layout = .() { Offset = 0, BytesPerRow = loadInfo.Width * 4, RowsPerImage = loadInfo.Height };
					Extent3D size = .(loadInfo.Width, loadInfo.Height, 1);
					Span<uint8> data = .(loadInfo.Data.Ptr, loadInfo.Data.Count);
					Device.Queue.WriteTexture(mFoxTexture, data, &layout, &size, 0, 0);

					TextureViewDescriptor viewDesc = .() { Format = .RGBA8Unorm, Dimension = .Texture2D, MipLevelCount = 1, ArrayLayerCount = 1 };
					if (Device.CreateTextureView(mFoxTexture, &viewDesc) case .Ok(let view))
						mFoxTextureView = view;
				}
			}
		}

		// Create fallback white texture if needed
		if (mFoxTextureView == null)
		{
			TextureDescriptor texDesc = .Texture2D(1, 1, .RGBA8Unorm, .Sampled | .CopyDst);
			if (Device.CreateTexture(&texDesc) case .Ok(let texture))
			{
				mFoxTexture = texture;
				uint8[4] white = .(255, 255, 255, 255);
				TextureDataLayout layout = .() { Offset = 0, BytesPerRow = 4, RowsPerImage = 1 };
				Extent3D size = .(1, 1, 1);
				Span<uint8> data = .(&white, 4);
				Device.Queue.WriteTexture(mFoxTexture, data, &layout, &size, 0, 0);

				TextureViewDescriptor viewDesc = .() { Format = .RGBA8Unorm, Dimension = .Texture2D, MipLevelCount = 1, ArrayLayerCount = 1 };
				if (Device.CreateTextureView(mFoxTexture, &viewDesc) case .Ok(let view))
					mFoxTextureView = view;
			}
		}

		return true;
	}

	private bool CreateSkyboxPipeline()
	{
		let shaderPath = GetAssetPath("framework/shaders/skybox", .. scope .());
		let shaderResult = ShaderUtils.LoadShaderPair(Device, shaderPath);
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

	private bool CreateSkinnedPipeline()
	{
		if (mFoxGPUMesh.Index == uint32.MaxValue)
			return false;

		let shaderPath = GetAssetPath("framework/shaders/skinned", .. scope .());
		let shaderResult = ShaderUtils.LoadShaderPair(Device, shaderPath);
		if (shaderResult case .Err)
		{
			Console.WriteLine("Failed to load skinned mesh shaders");
			return false;
		}

		let (vertShader, fragShader) = shaderResult.Get();
		defer { delete vertShader; delete fragShader; }

		// Bind group layout: b0=camera, b1=object, b2=bones, t0=texture, s0=sampler
		BindGroupLayoutEntry[5] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex | .Fragment),
			BindGroupLayoutEntry.UniformBuffer(1, .Vertex | .Fragment),
			BindGroupLayoutEntry.UniformBuffer(2, .Vertex),
			BindGroupLayoutEntry.SampledTexture(0, .Fragment, .Texture2D),
			BindGroupLayoutEntry.Sampler(0, .Fragment)
		);
		BindGroupLayoutDescriptor bindLayoutDesc = .(layoutEntries);
		if (Device.CreateBindGroupLayout(&bindLayoutDesc) not case .Ok(let layout))
			return false;
		mSkinnedBindGroupLayout = layout;

		IBindGroupLayout[1] layouts = .(mSkinnedBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (Device.CreatePipelineLayout(&pipelineLayoutDesc) not case .Ok(let pipelineLayout))
			return false;
		mSkinnedPipelineLayout = pipelineLayout;

		BindGroupEntry[5] entries = .(
			BindGroupEntry.Buffer(0, mCameraUniformBuffer),
			BindGroupEntry.Buffer(1, mObjectUniformBuffer),
			BindGroupEntry.Buffer(2, mBoneBuffer),
			BindGroupEntry.Texture(0, mFoxTextureView),
			BindGroupEntry.Sampler(0, mSampler)
		);
		BindGroupDescriptor bindGroupDesc = .(mSkinnedBindGroupLayout, entries);
		if (Device.CreateBindGroup(&bindGroupDesc) not case .Ok(let group))
			return false;
		mSkinnedBindGroup = group;

		// Vertex layout for SkinnedVertex (72 bytes)
		Sedulous.RHI.VertexAttribute[7] vertexAttrs = .(
			.(VertexFormat.Float3, 0, 0),             // Position
			.(VertexFormat.Float3, 12, 1),            // Normal
			.(VertexFormat.Float2, 24, 2),            // TexCoord
			.(VertexFormat.UByte4Normalized, 32, 3),  // Color
			.(VertexFormat.Float3, 36, 4),            // Tangent
			.(VertexFormat.UShort4, 48, 5),           // Joints
			.(VertexFormat.Float4, 56, 6)             // Weights
		);
		VertexBufferLayout[1] vertexBuffers = .(.(72, vertexAttrs));

		ColorTargetState[1] colorTargets = .(.(SwapChain.Format));

		DepthStencilState depthState = .();
		depthState.DepthTestEnabled = true;
		depthState.DepthWriteEnabled = true;
		depthState.DepthCompare = .Less;
		depthState.Format = .Depth24PlusStencil8;

		RenderPipelineDescriptor pipelineDesc = .()
		{
			Layout = mSkinnedPipelineLayout,
			Vertex = .() { Shader = .(vertShader, "main"), Buffers = vertexBuffers },
			Fragment = .() { Shader = .(fragShader, "main"), Targets = colorTargets },
			Primitive = .() { Topology = .TriangleList, FrontFace = .CCW, CullMode = .Back },
			DepthStencil = depthState,
			Multisample = .() { Count = 1, Mask = uint32.MaxValue }
		};

		if (Device.CreateRenderPipeline(&pipelineDesc) not case .Ok(let pipeline))
		{
			Console.WriteLine("Failed to create skinned mesh pipeline");
			return false;
		}
		mSkinnedPipeline = pipeline;

		Console.WriteLine("Skinned mesh pipeline created");
		return true;
	}

	protected override void OnUpdate(float deltaTime, float totalTime)
	{
		// Update Fox animation
		if (mFoxAnimPlayer != null)
		{
			mFoxAnimPlayer.Update(deltaTime);

			if (mBoneBuffer != null)
			{
				Span<uint8> boneData = .((uint8*)mFoxAnimPlayer.BoneMatrices.Ptr, 128 * sizeof(Matrix));
				Device.Queue.WriteBuffer(mBoneBuffer, 0, boneData);
			}
		}

		var projection = mCamera.ProjectionMatrix;
		let view = mCamera.ViewMatrix;

		if (Device.FlipProjectionRequired)
			projection.M22 = -projection.M22;

		CameraUniforms cameraData = .();
		cameraData.ViewProjection = view * projection;
		cameraData.View = view;
		cameraData.Projection = projection;
		cameraData.CameraPosition = mCamera.Position;

		Span<uint8> camData = .((uint8*)&cameraData, sizeof(CameraUniforms));
		Device.Queue.WriteBuffer(mCameraUniformBuffer, 0, camData);

		// Fox model transform (no extra scale needed - use native units)
		ObjectUniforms foxData = .();
		foxData.Model = Matrix.Identity;
		foxData.ObjectColor = .(1f, 1f, 1f, 1.0f);

		Span<uint8> objData = .((uint8*)&foxData, sizeof(ObjectUniforms));
		Device.Queue.WriteBuffer(mObjectUniformBuffer, 0, objData);
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

		// Render skinned Fox mesh
		if (mSkinnedPipeline != null && mSkinnedBindGroup != null)
		{
			let mesh = mResourceManager.GetSkinnedMesh(mFoxGPUMesh);
			if (mesh != null)
			{
				renderPass.SetPipeline(mSkinnedPipeline);
				renderPass.SetBindGroup(0, mSkinnedBindGroup);
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
		}
	}

	protected override void OnCleanup()
	{
		if (mSkinnedPipeline != null) delete mSkinnedPipeline;
		if (mSkinnedPipelineLayout != null) delete mSkinnedPipelineLayout;
		if (mSkinnedBindGroup != null) delete mSkinnedBindGroup;
		if (mSkinnedBindGroupLayout != null) delete mSkinnedBindGroupLayout;

		if (mSkyboxPipeline != null) delete mSkyboxPipeline;
		if (mSkyboxPipelineLayout != null) delete mSkyboxPipelineLayout;
		if (mSkyboxBindGroup != null) delete mSkyboxBindGroup;
		if (mSkyboxBindGroupLayout != null) delete mSkyboxBindGroupLayout;

		if (mFoxTextureView != null) delete mFoxTextureView;
		if (mFoxTexture != null) delete mFoxTexture;
		if (mFoxAnimPlayer != null) delete mFoxAnimPlayer;
		if (mFoxModel != null) delete mFoxModel;

		if (mBoneBuffer != null) delete mBoneBuffer;
		if (mSampler != null) delete mSampler;
		if (mObjectUniformBuffer != null) delete mObjectUniformBuffer;
		if (mCameraUniformBuffer != null) delete mCameraUniformBuffer;

		if (mSkyboxRenderer != null) delete mSkyboxRenderer;

		if (mResourceManager != null)
		{
			mResourceManager.ReleaseSkinnedMesh(mFoxGPUMesh);
			delete mResourceManager;
		}
	}
}

[CRepr]
struct CameraUniforms
{
	public Matrix ViewProjection;
	public Matrix View;
	public Matrix Projection;
	public Vector3 CameraPosition;
	public float _pad0;
}

[CRepr]
struct ObjectUniforms
{
	public Matrix Model;
	public Vector4 ObjectColor;
}

class Program
{
	public static int Main(String[] args)
	{
		let app = scope RendererSkinnedSample();
		return app.Run();
	}
}
