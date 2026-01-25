namespace GLTFViewer;

using System;
using System.IO;
using System.Collections;
using Sedulous.AppFramework;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.RHI.HLSLShaderCompiler;
using Sedulous.Models;
using Sedulous.Models.GLTF;
using Sedulous.UI;
using Sedulous.Drawing;

/// Uniform buffer for model rendering
[CRepr]
struct ModelUniforms
{
	public Matrix Model;
	public Matrix View;
	public Matrix Projection;
	public Matrix Normal; // Inverse transpose of model matrix for normals
	public Vector4 LightDirection;
	public Vector4 LightColor;
	public Vector4 AmbientColor;
	public Vector4 CameraPosition;
}

/// Per-material uniforms
[CRepr]
struct MaterialUniforms
{
	public Vector4 BaseColorFactor;
	public float MetallicFactor;
	public float RoughnessFactor;
	public float _padding0;
	public float _padding1;
}

/// Simple orbit camera
class OrbitCamera
{
	public Vector3 Target = .Zero;
	public float Distance = 5.0f;
	public float Yaw = 0.0f;
	public float Pitch = 0.3f;
	public float MinDistance = 0.5f;
	public float MaxDistance = 100.0f;
	public float MinPitch = -Math.PI_f / 2.0f + 0.1f;
	public float MaxPitch = Math.PI_f / 2.0f - 0.1f;

	public Vector3 Position
	{
		get
		{
			float x = Distance * Math.Cos(Pitch) * Math.Sin(Yaw);
			float y = Distance * Math.Sin(Pitch);
			float z = Distance * Math.Cos(Pitch) * Math.Cos(Yaw);
			return Target + Vector3(x, y, z);
		}
	}

	public Matrix ViewMatrix => Matrix.CreateLookAt(Position, Target, Vector3.Up);

	public void Rotate(float deltaYaw, float deltaPitch)
	{
		Yaw += deltaYaw;
		Pitch = Math.Clamp(Pitch + deltaPitch, MinPitch, MaxPitch);
	}

	public void Zoom(float delta)
	{
		Distance = Math.Clamp(Distance - delta, MinDistance, MaxDistance);
	}

	public void Pan(float deltaX, float deltaY)
	{
		// Calculate right and up vectors in world space
		let forward = Vector3.Normalize(Target - Position);
		let right = Vector3.Normalize(Vector3.Cross(forward, Vector3.Up));
		let up = Vector3.Cross(right, forward);

		Target += right * deltaX * Distance * 0.01f;
		Target += up * deltaY * Distance * 0.01f;
	}
}

/// GPU mesh data
class GPUMesh
{
	public IBuffer VertexBuffer;
	public IBuffer IndexBuffer;
	public int32 IndexCount;
	public bool Use32BitIndices;

	public ~this()
	{
		if (VertexBuffer != null) delete VertexBuffer;
		if (IndexBuffer != null) delete IndexBuffer;
	}
}

/// GLTF Viewer Application
class GLTFViewerApp : Application
{
	// Model data
	private Model mModel ~ delete _;
	private GltfLoader mLoader ~ delete _;
	private List<GPUMesh> mGPUMeshes = new .() ~ DeleteContainerAndItems!(_);

	// Camera
	private OrbitCamera mCamera = new .() ~ delete _;
	private bool mIsDragging = false;
	private bool mIsPanning = false;
	private float mLastMouseX;
	private float mLastMouseY;

	// Rendering resources
	private IShaderModule mVertShader;
	private IShaderModule mFragShader;
	private IBindGroupLayout mBindGroupLayout;
	private IPipelineLayout mPipelineLayout;
	private IRenderPipeline mPipeline;
	private IBuffer mUniformBuffer;
	private IBuffer mMaterialBuffer; // Track material buffer for cleanup
	private IBindGroup mBindGroup;
	private ISampler mDefaultSampler;
	private Sedulous.RHI.ITexture mWhiteTexture;
	private ITextureView mWhiteTextureView;

	// Depth buffer
	private Sedulous.RHI.ITexture mDepthTexture;
	private ITextureView mDepthTextureView;

	// Model path (can be set via command line or UI)
	private String mModelPath = new .() ~ delete _;

	public this() : base(.()
		{
			Title = "GLTF Viewer",
			Width = 1280,
			Height = 720,
			ClearColor = .(0.2f, 0.2f, 0.25f, 1.0f)
		})
	{
	}

	protected override bool OnInitialize()
	{
		mLoader = new GltfLoader();
		mModel = new Model();

		if (!CreateRenderResources())
			return false;

		if (!CreateDepthBuffer())
			return false;

		// Try to load a default model
		let modelPath = GetAssetPath("samples/models/Duck/glTF/Duck.gltf", .. scope .());
		Console.WriteLine(scope $"Looking for model at: {modelPath}");
		if (File.Exists(modelPath))
		{
			LoadModel(modelPath);
		}
		else
		{
			Console.WriteLine("Default model not found - scene will be empty");
		}

		return true;
	}

	private bool CreateRenderResources()
	{
		// Compile shaders
		if (!CompileShaders())
			return false;

		// Create bind group layout
		BindGroupLayoutEntry[4] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex | .Fragment), // Model uniforms
			BindGroupLayoutEntry.UniformBuffer(1, .Fragment),           // Material uniforms
			BindGroupLayoutEntry.SampledTexture(0, .Fragment),          // Base color texture
			BindGroupLayoutEntry.Sampler(0, .Fragment)                  // Sampler
		);
		BindGroupLayoutDescriptor bindGroupLayoutDesc = .(layoutEntries);
		if (Device.CreateBindGroupLayout(&bindGroupLayoutDesc) case .Ok(let layout))
			mBindGroupLayout = layout;
		else
			return false;

		// Create pipeline layout
		IBindGroupLayout[1] layouts = .(mBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (Device.CreatePipelineLayout(&pipelineLayoutDesc) case .Ok(let pipelineLayout))
			mPipelineLayout = pipelineLayout;
		else
			return false;

		// Create pipeline
		if (!CreatePipeline())
			return false;

		// Create uniform buffer
		BufferDescriptor uniformDesc = .()
		{
			Size = (uint64)sizeof(ModelUniforms),
			Usage = .Uniform | .CopyDst
		};
		if (Device.CreateBuffer(&uniformDesc) case .Ok(let buffer))
			mUniformBuffer = buffer;
		else
			return false;

		// Create default sampler
		SamplerDescriptor samplerDesc = .();
		if (Device.CreateSampler(&samplerDesc) case .Ok(let sampler))
			mDefaultSampler = sampler;
		else
			return false;

		// Create white texture for models without textures
		if (!CreateWhiteTexture())
			return false;

		// Create bind group
		if (!CreateBindGroup())
			return false;

		return true;
	}

	private bool CompileShaders()
	{
		let compiler = scope HLSLCompiler();
		if (!compiler.IsInitialized)
			return false;

		String vertSource = """
			cbuffer ModelUniforms : register(b0)
			{
				float4x4 Model;
				float4x4 View;
				float4x4 Projection;
				float4x4 Normal;
				float4 LightDirection;
				float4 LightColor;
				float4 AmbientColor;
				float4 CameraPosition;
			};

			struct VSInput
			{
				float3 Position : POSITION;
				float3 Normal : NORMAL;
				float2 TexCoord : TEXCOORD0;
				float4 Color : COLOR0;
				float3 Tangent : TANGENT;
			};

			struct VSOutput
			{
				float4 Position : SV_Position;
				float3 WorldPos : TEXCOORD0;
				float3 Normal : TEXCOORD1;
				float2 TexCoord : TEXCOORD2;
				float4 Color : TEXCOORD3;
			};

			VSOutput main(VSInput input)
			{
				VSOutput output;
				// Use column-major multiplication order (matrix * vector)
				// Since CPU sends row-major and SPIR-V expects column-major, this effectively transposes
				float4 worldPos = mul(Model, float4(input.Position, 1.0));
				output.WorldPos = worldPos.xyz;
				output.Position = mul(Projection, mul(View, worldPos));
				output.Normal = normalize(mul(Normal, float4(input.Normal, 0.0)).xyz);
				output.TexCoord = input.TexCoord;
				output.Color = input.Color;
				return output;
			}
			""";

		String fragSource = """
			cbuffer ModelUniforms : register(b0)
			{
				float4x4 Model;
				float4x4 View;
				float4x4 Projection;
				float4x4 Normal;
				float4 LightDirection;
				float4 LightColor;
				float4 AmbientColor;
				float4 CameraPosition;
			};

			cbuffer MaterialUniforms : register(b1)
			{
				float4 BaseColorFactor;
				float MetallicFactor;
				float RoughnessFactor;
				float2 _padding;
			};

			Texture2D BaseColorTexture : register(t0);
			SamplerState Sampler : register(s0);

			struct PSInput
			{
				float4 Position : SV_Position;
				float3 WorldPos : TEXCOORD0;
				float3 Normal : TEXCOORD1;
				float2 TexCoord : TEXCOORD2;
				float4 Color : TEXCOORD3;
			};

			float4 main(PSInput input) : SV_Target
			{
				// Sample base color
				float4 baseColor = BaseColorTexture.Sample(Sampler, input.TexCoord) * BaseColorFactor * input.Color;

				// Simple directional lighting
				float3 normal = normalize(input.Normal);
				float3 lightDir = normalize(-LightDirection.xyz);
				float NdotL = max(dot(normal, lightDir), 0.0);

				float3 diffuse = baseColor.rgb * LightColor.rgb * NdotL;
				float3 ambient = baseColor.rgb * AmbientColor.rgb;

				float3 finalColor = ambient + diffuse;
				return float4(finalColor, baseColor.a);
			}
			""";

		// Compile vertex shader
		ShaderCompileOptions vertOptions = .();
		vertOptions.EntryPoint = "main";
		vertOptions.Stage = .Vertex;
		vertOptions.Target = .SPIRV;
		vertOptions.ConstantBufferShift = VulkanBindingShifts.SHIFT_B;
		vertOptions.TextureShift = VulkanBindingShifts.SHIFT_T;
		vertOptions.SamplerShift = VulkanBindingShifts.SHIFT_S;

		let vertResult = compiler.Compile(vertSource, vertOptions);
		defer delete vertResult;
		if (!vertResult.Success)
		{
			Console.WriteLine(scope $"Vertex shader error: {vertResult.Errors}");
			return false;
		}

		ShaderModuleDescriptor vertDesc = .(vertResult.Bytecode);
		if (Device.CreateShaderModule(&vertDesc) case .Ok(let vs))
			mVertShader = vs;
		else
			return false;

		// Compile fragment shader
		ShaderCompileOptions fragOptions = .();
		fragOptions.EntryPoint = "main";
		fragOptions.Stage = .Fragment;
		fragOptions.Target = .SPIRV;
		fragOptions.ConstantBufferShift = VulkanBindingShifts.SHIFT_B;
		fragOptions.TextureShift = VulkanBindingShifts.SHIFT_T;
		fragOptions.SamplerShift = VulkanBindingShifts.SHIFT_S;

		let fragResult = compiler.Compile(fragSource, fragOptions);
		defer delete fragResult;
		if (!fragResult.Success)
		{
			Console.WriteLine(scope $"Fragment shader error: {fragResult.Errors}");
			return false;
		}

		ShaderModuleDescriptor fragDesc = .(fragResult.Bytecode);
		if (Device.CreateShaderModule(&fragDesc) case .Ok(let fs))
			mFragShader = fs;
		else
			return false;

		return true;
	}

	private bool CreatePipeline()
	{
		// Vertex layout matching ModelMesh format
		VertexAttribute[5] vertexAttributes = .(
			.(VertexFormat.Float3, 0, 0),   // Position
			.(VertexFormat.Float3, 12, 1),  // Normal
			.(VertexFormat.Float2, 24, 2),  // TexCoord
			.(VertexFormat.UByte4Normalized, 32, 3),  // Color (normalized)
			.(VertexFormat.Float3, 36, 4)   // Tangent
		);
		VertexBufferLayout[1] vertexBuffers = .(
			.(48, vertexAttributes) // Stride = 48 bytes
		);

		// No blending - just the format
		ColorTargetState[1] colorTargets = .(.(SwapChain.Format));

		DepthStencilState depthState = .()
		{
			Format = .Depth32Float,
			DepthWriteEnabled = true,
			DepthCompare = .Less
		};

		RenderPipelineDescriptor pipelineDesc = .()
		{
			Layout = mPipelineLayout,
			Vertex = .()
			{
				Shader = .(mVertShader, "main"),
				Buffers = vertexBuffers
			},
			Fragment = .()
			{
				Shader = .(mFragShader, "main"),
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
				Mask = uint32.MaxValue,
				AlphaToCoverageEnabled = false
			}
		};

		if (Device.CreateRenderPipeline(&pipelineDesc) case .Ok(let pipeline))
			mPipeline = pipeline;
		else
			return false;

		return true;
	}

	private bool CreateWhiteTexture()
	{
		TextureDescriptor texDesc = TextureDescriptor.Texture2D(1, 1, .RGBA8Unorm, .Sampled | .CopyDst);
		if (Device.CreateTexture(&texDesc) case .Ok(let tex))
			mWhiteTexture = tex;
		else
			return false;

		uint8[4] whitePixel = .(255, 255, 255, 255);
		TextureDataLayout dataLayout = .() { Offset = 0, BytesPerRow = 4, RowsPerImage = 1 };
		Extent3D writeSize = .(1, 1, 1);
		Device.Queue.WriteTexture(mWhiteTexture, Span<uint8>(&whitePixel, 4), &dataLayout, &writeSize);

		TextureViewDescriptor viewDesc = .() { Format = .RGBA8Unorm };
		if (Device.CreateTextureView(mWhiteTexture, &viewDesc) case .Ok(let view))
			mWhiteTextureView = view;
		else
			return false;

		return true;
	}

	private bool CreateBindGroup()
	{
		// Create a material uniform buffer
		BufferDescriptor matUniformDesc = .()
		{
			Size = (uint64)sizeof(MaterialUniforms),
			Usage = .Uniform | .CopyDst
		};
		if (Device.CreateBuffer(&matUniformDesc) case .Ok(let buffer))
			mMaterialBuffer = buffer;
		else
			return false;

		// Set default material values
		MaterialUniforms matUniforms = .()
		{
			BaseColorFactor = .(1, 1, 1, 1),
			MetallicFactor = 0.0f,
			RoughnessFactor = 0.5f
		};
		Device.Queue.WriteBuffer(mMaterialBuffer, 0, Span<uint8>((uint8*)&matUniforms, sizeof(MaterialUniforms)));

		BindGroupEntry[4] bindGroupEntries = .(
			BindGroupEntry.Buffer(0, mUniformBuffer),
			BindGroupEntry.Buffer(1, mMaterialBuffer),
			BindGroupEntry.Texture(0, mWhiteTextureView),
			BindGroupEntry.Sampler(0, mDefaultSampler)
		);
		BindGroupDescriptor bindGroupDesc = .(mBindGroupLayout, bindGroupEntries);
		if (Device.CreateBindGroup(&bindGroupDesc) case .Ok(let group))
			mBindGroup = group;
		else
			return false;

		return true;
	}

	private bool CreateDepthBuffer()
	{
		TextureDescriptor depthDesc = TextureDescriptor.Texture2D(
			SwapChain.Width, SwapChain.Height,
			.Depth32Float, .DepthStencil
		);
		if (Device.CreateTexture(&depthDesc) case .Ok(let tex))
			mDepthTexture = tex;
		else
			return false;

		TextureViewDescriptor viewDesc = .() { Format = .Depth32Float };
		if (Device.CreateTextureView(mDepthTexture, &viewDesc) case .Ok(let view))
			mDepthTextureView = view;
		else
			return false;

		return true;
	}

	private void RecreateDepthBuffer()
	{
		if (mDepthTextureView != null) delete mDepthTextureView;
		if (mDepthTexture != null) delete mDepthTexture;
		CreateDepthBuffer();
	}

	public void LoadModel(StringView path)
	{
		mModelPath.Set(path);

		// Clear existing GPU meshes
		DeleteContainerAndItems!(mGPUMeshes);
		mGPUMeshes = new List<GPUMesh>();

		// Clear and reload model
		delete mModel;
		mModel = new Model();

		let result = mLoader.Load(path, mModel);
		if (result != .Ok)
		{
			Console.WriteLine(scope $"Failed to load model: {path}");
			return;
		}

		Console.WriteLine(scope $"Loaded model: {path}");
		Console.WriteLine(scope $"  Meshes: {mModel.Meshes.Count}");
		Console.WriteLine(scope $"  Materials: {mModel.Materials.Count}");
		Console.WriteLine(scope $"  Bones: {mModel.Bones.Count}");
		Console.WriteLine(scope $"  Bounds: ({mModel.Bounds.Min.X}, {mModel.Bounds.Min.Y}, {mModel.Bounds.Min.Z}) - ({mModel.Bounds.Max.X}, {mModel.Bounds.Max.Y}, {mModel.Bounds.Max.Z})");

		// Upload meshes to GPU
		for (let mesh in mModel.Meshes)
		{
			let gpuMesh = new GPUMesh();

			// Create vertex buffer
			let vertexData = mesh.GetVertexData();
			let vertexSize = mesh.VertexCount * mesh.VertexStride;
			if (vertexSize > 0)
			{
				BufferDescriptor vbDesc = .()
				{
					Size = (uint64)vertexSize,
					Usage = .Vertex | .CopyDst
				};
				if (Device.CreateBuffer(&vbDesc) case .Ok(let vb))
				{
					gpuMesh.VertexBuffer = vb;
					Device.Queue.WriteBuffer(vb, 0, Span<uint8>(vertexData, vertexSize));
				}
			}

			// Create index buffer
			let indexData = mesh.GetIndexData();
			gpuMesh.IndexCount = mesh.IndexCount;
			gpuMesh.Use32BitIndices = mesh.Use32BitIndices;
			let indexSize = mesh.IndexCount * (mesh.Use32BitIndices ? 4 : 2);
			if (indexSize > 0)
			{
				BufferDescriptor ibDesc = .()
				{
					Size = (uint64)indexSize,
					Usage = .Index | .CopyDst
				};
				if (Device.CreateBuffer(&ibDesc) case .Ok(let ib))
				{
					gpuMesh.IndexBuffer = ib;
					Device.Queue.WriteBuffer(ib, 0, Span<uint8>(indexData, indexSize));
				}
			}

			mGPUMeshes.Add(gpuMesh);
		}

		// Center camera on model
		let bounds = mModel.Bounds;
		let center = (bounds.Min + bounds.Max) * 0.5f;
		let extents = (bounds.Max - bounds.Min) * 0.5f;
		mCamera.Target = center;
		mCamera.Distance = Math.Max(extents.Length() * 2.5f, 1.0f);
	}

	protected override void OnUpdate(float deltaTime)
	{
		// Camera controls are handled in input processing
	}

	protected override void OnResize(uint32 width, uint32 height)
	{
		RecreateDepthBuffer();
	}

	protected override bool OnRender(ICommandEncoder encoder, int32 frameIndex)
	{
		// Update uniforms
		let aspectRatio = (float)SwapChain.Width / (float)SwapChain.Height;
		var projection = Matrix.CreatePerspectiveFieldOfView(Math.PI_f / 4.0f, aspectRatio, 0.1f, 1000.0f);
		let view = mCamera.ViewMatrix;

		// Flip Y for Vulkan's coordinate system if needed
		if (Device.FlipProjectionRequired)
		{
			projection.M22 = -projection.M22;
		}

		ModelUniforms uniforms = .()
		{
			Model = .Identity,
			View = view,
			Projection = projection,
			Normal = .Identity,
			LightDirection = .(0.5f, -1.0f, 0.3f, 0.0f),
			LightColor = .(1.0f, 0.98f, 0.95f, 1.0f),
			AmbientColor = .(0.15f, 0.15f, 0.2f, 1.0f),
			CameraPosition = .(mCamera.Position.X, mCamera.Position.Y, mCamera.Position.Z, 1.0f)
		};

		Device.Queue.WriteBuffer(mUniformBuffer, 0, Span<uint8>((uint8*)&uniforms, sizeof(ModelUniforms)));

		// Begin render pass with depth attachment
		let swapTextureView = SwapChain.CurrentTextureView;
		RenderPassColorAttachment[1] colorAttachments = .(.(swapTextureView)
			{
				LoadOp = .Clear,
				StoreOp = .Store,
				ClearValue = mConfig.ClearColor
			});
		RenderPassDepthStencilAttachment depthAttachment = .()
		{
			View = mDepthTextureView,
			DepthLoadOp = .Clear,
			DepthStoreOp = .Store,
			DepthClearValue = 1.0f
		};
		RenderPassDescriptor passDesc = .(colorAttachments);
		passDesc.DepthStencilAttachment = depthAttachment;

		let renderPass = encoder.BeginRenderPass(&passDesc);
		if (renderPass != null)
		{
			renderPass.SetViewport(0, 0, SwapChain.Width, SwapChain.Height, 0, 1);
			renderPass.SetScissorRect(0, 0, SwapChain.Width, SwapChain.Height);
			renderPass.SetPipeline(mPipeline);
			renderPass.SetBindGroup(0, mBindGroup);

			// Draw all meshes
			for (let gpuMesh in mGPUMeshes)
			{
				if (gpuMesh.VertexBuffer == null || gpuMesh.IndexBuffer == null)
					continue;

				renderPass.SetVertexBuffer(0, gpuMesh.VertexBuffer, 0);
				renderPass.SetIndexBuffer(gpuMesh.IndexBuffer, gpuMesh.Use32BitIndices ? .UInt32 : .UInt16, 0);
				renderPass.DrawIndexed((uint32)gpuMesh.IndexCount, 1, 0, 0, 0);
			}

			renderPass.End();
			delete renderPass;
		}

		// Render UI in separate pass (no depth attachment - UI pipeline doesn't use depth)
		// Need a barrier to ensure proper layout tracking between render passes
		encoder.TextureBarrier(SwapChain.CurrentTexture, .ColorAttachment, .ColorAttachment);

		RenderPassColorAttachment[1] uiAttachments = .(.(swapTextureView)
			{
				LoadOp = .Load,  // Preserve 3D content
				StoreOp = .Store
			});
		RenderPassDescriptor uiPassDesc = .(uiAttachments);

		let uiPass = encoder.BeginRenderPass(&uiPassDesc);
		if (uiPass != null)
		{
			mDrawingRenderer.Render(uiPass, SwapChain.Width, SwapChain.Height, frameIndex);
			uiPass.End();
			delete uiPass;
		}

		return true;
	}

	protected override void OnUISetup(UIContext context)
	{
		// Create root layout - a simple StackPanel in the top-left corner
		let root = new StackPanel();
		root.Orientation = .Vertical;
		root.Spacing = 5;
		root.Margin = .(10, 10, 10, 10);
		root.HorizontalAlignment = .Left;
		root.VerticalAlignment = .Top;
		root.Background = Color(30, 30, 35, 200);
		root.Padding = .(10, 10, 10, 10);

		// Title label
		let titleLabel = new Label("GLTF Viewer");
		root.AddChild(titleLabel);

		// Help label
		let helpLabel = new Label("LMB: Rotate | RMB: Pan | Scroll: Zoom");
		helpLabel.FontSize = 12;
		root.AddChild(helpLabel);

		// Set as root element
		context.RootElement = root;
	}

	protected override void OnKeyDown(Sedulous.Shell.Input.KeyCode key)
	{
		// Reset camera on R
		if (key == .R)
		{
			let bounds = mModel.Bounds;
			let center = (bounds.Min + bounds.Max) * 0.5f;
			let extents = (bounds.Max - bounds.Min) * 0.5f;
			mCamera.Target = center;
			mCamera.Distance = Math.Max(extents.Length() * 2.5f, 1.0f);
			mCamera.Yaw = 0;
			mCamera.Pitch = 0.3f;
		}
	}

	protected override void OnCleanup()
	{
		DeleteContainerAndItems!(mGPUMeshes);
		mGPUMeshes = null;

		if (mBindGroup != null) delete mBindGroup;
		if (mMaterialBuffer != null) delete mMaterialBuffer;
		if (mUniformBuffer != null) delete mUniformBuffer;
		if (mWhiteTextureView != null) delete mWhiteTextureView;
		if (mWhiteTexture != null) delete mWhiteTexture;
		if (mDefaultSampler != null) delete mDefaultSampler;
		if (mPipeline != null) delete mPipeline;
		if (mPipelineLayout != null) delete mPipelineLayout;
		if (mBindGroupLayout != null) delete mBindGroupLayout;
		if (mFragShader != null) delete mFragShader;
		if (mVertShader != null) delete mVertShader;
		if (mDepthTextureView != null) delete mDepthTextureView;
		if (mDepthTexture != null) delete mDepthTexture;
	}
}

class Program
{
	public static int Main(String[] args)
	{
		let app = scope GLTFViewerApp();

		// Load model from command line if provided
		if (args.Count > 0)
		{
			// Will be loaded after initialization
		}

		return app.Run();
	}
}
