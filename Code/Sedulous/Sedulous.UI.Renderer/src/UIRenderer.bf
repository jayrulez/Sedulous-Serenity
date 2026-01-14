namespace Sedulous.UI.Renderer;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Shaders;
using Sedulous.RHI.HLSLShaderCompiler;
using Sedulous.Drawing;
using Sedulous.Mathematics;

/// Uniform buffer data for UI projection matrix.
[CRepr]
struct UIUniforms
{
	public Matrix Projection;
}

/// Renders UI DrawBatch content using RHI.
/// Does NOT own the device or swapchain - caller manages those.
public class UIRenderer : IDisposable
{
	private IDevice mDevice;
	private int32 mFrameCount;
	private TextureFormat mTargetFormat;

	// Shaders
	private IShaderModule mVertShader;
	private IShaderModule mFragShader;

	// Pipeline
	private IBindGroupLayout mBindGroupLayout;
	private IPipelineLayout mPipelineLayout;
	private IRenderPipeline mPipeline;
	private IRenderPipeline mMsaaPipeline;
	private uint32 mMsaaSampleCount = 4;

	// Per-frame resources
	private IBuffer[] mVertexBuffers;
	private IBuffer[] mIndexBuffers;
	private IBuffer[] mUniformBuffers;
	private IBindGroup[] mBindGroups;

	// Current texture view (set before Prepare)
	private ITextureView mTextureView;
	private ISampler mSampler;

	// Batch data converted for GPU
	private List<UIRenderVertex> mVertices = new .() ~ delete _;
	private List<uint16> mIndices = new .() ~ delete _;
	private List<DrawCommand> mDrawCommands = new .() ~ delete _;

	// Buffer sizes
	private const int32 MAX_VERTICES = 65536;
	private const int32 MAX_INDICES = 65536 * 3;

	public bool IsInitialized { get; private set; }

	/// Initialize the renderer with the given device and target format.
	/// frameCount should match the swapchain's frame count.
	public Result<void> Initialize(
		IDevice device,
		TextureFormat targetFormat,
		int32 frameCount,
		IUIShaderProvider shaderProvider = null)
	{
		mDevice = device;
		mTargetFormat = targetFormat;
		mFrameCount = frameCount;

		// Use default shader provider if none specified
		IUIShaderProvider provider;
		DefaultUIShaderProvider defaultProvider = scope .();
		if (shaderProvider != null)
			provider = shaderProvider;
		else
			provider = defaultProvider;

		// Compile shaders
		if (CompileShaders(provider) case .Err)
			return .Err;

		// Create sampler
		if (CreateSampler() case .Err)
			return .Err;

		// Create bind group layout and pipeline layout
		if (CreateLayouts() case .Err)
			return .Err;

		// Create pipeline
		if (CreatePipeline() case .Err)
			return .Err;

		// Create per-frame resources
		if (CreatePerFrameResources() case .Err)
			return .Err;

		IsInitialized = true;
		return .Ok;
	}

	/// Set the texture to use for rendering.
	/// Must be called before Prepare() each frame.
	public void SetTexture(ITextureView textureView)
	{
		mTextureView = textureView;
	}

	/// Prepare batch data for rendering.
	/// Call this after BuildDrawCommands and before the render pass.
	public void Prepare(DrawBatch batch, int32 frameIndex)
	{
		// Convert vertices
		mVertices.Clear();
		for (let v in batch.Vertices)
			mVertices.Add(.(v));

		// Copy indices
		mIndices.Clear();
		for (let i in batch.Indices)
			mIndices.Add(i);

		// Copy draw commands
		mDrawCommands.Clear();
		for (let cmd in batch.Commands)
			mDrawCommands.Add(cmd);

		// Upload to GPU buffers
		if (mVertices.Count > 0)
		{
			let vertexData = Span<uint8>((uint8*)mVertices.Ptr, mVertices.Count * sizeof(UIRenderVertex));
			mDevice.Queue.WriteBuffer(mVertexBuffers[frameIndex], 0, vertexData);

			let indexData = Span<uint8>((uint8*)mIndices.Ptr, mIndices.Count * sizeof(uint16));
			mDevice.Queue.WriteBuffer(mIndexBuffers[frameIndex], 0, indexData);
		}

		// Update bind group with current texture
		UpdateBindGroup(frameIndex);
	}

	/// Update the projection matrix for the given viewport size.
	public void UpdateProjection(uint32 width, uint32 height, int32 frameIndex)
	{
		// Y-down orthographic projection for UI (origin at top-left)
		// Check if device requires flipped projection (Vulkan vs OpenGL/D3D)
		Matrix projection;
		if (mDevice.FlipProjectionRequired)
			projection = Matrix.CreateOrthographicOffCenter(0, (float)width, 0, (float)height, -1, 1);
		else
			projection = Matrix.CreateOrthographicOffCenter(0, (float)width, (float)height, 0, -1, 1);

		UIUniforms uniforms = .() { Projection = projection };
		let uniformData = Span<uint8>((uint8*)&uniforms, sizeof(UIUniforms));
		mDevice.Queue.WriteBuffer(mUniformBuffers[frameIndex], 0, uniformData);
	}

	/// Render UI to the current render pass.
	/// The render pass should already be begun.
	public void Render(IRenderPassEncoder renderPass, uint32 width, uint32 height, int32 frameIndex, bool useMsaa = false)
	{
		if (mIndices.Count == 0 || mDrawCommands.Count == 0)
			return;

		renderPass.SetViewport(0, 0, width, height, 0, 1);
		renderPass.SetPipeline(useMsaa ? mMsaaPipeline : mPipeline);
		renderPass.SetBindGroup(0, mBindGroups[frameIndex]);
		renderPass.SetVertexBuffer(0, mVertexBuffers[frameIndex], 0);
		renderPass.SetIndexBuffer(mIndexBuffers[frameIndex], .UInt16, 0);

		// Process each draw command with its own scissor rect
		for (let cmd in mDrawCommands)
		{
			if (cmd.IndexCount == 0)
				continue;

			// Set scissor rect based on clip mode
			if (cmd.ClipMode == .Scissor && cmd.ClipRect.Width > 0 && cmd.ClipRect.Height > 0)
			{
				// Conservative scissor rect calculation
				let startX = (int32)Math.Ceiling(Math.Max(0f, cmd.ClipRect.X));
				let startY = (int32)Math.Ceiling(Math.Max(0f, cmd.ClipRect.Y));
				let endX = (int32)Math.Floor(Math.Min(cmd.ClipRect.X + cmd.ClipRect.Width, (float)width));
				let endY = (int32)Math.Floor(Math.Min(cmd.ClipRect.Y + cmd.ClipRect.Height, (float)height));
				let w = (uint32)Math.Max(0, endX - startX);
				let h = (uint32)Math.Max(0, endY - startY);
				renderPass.SetScissorRect(startX, startY, w, h);
			}
			else
			{
				renderPass.SetScissorRect(0, 0, width, height);
			}

			renderPass.DrawIndexed((uint32)cmd.IndexCount, 1, (uint32)cmd.StartIndex, 0, 0);
		}
	}

	private Result<void> CompileShaders(IUIShaderProvider provider)
	{
		let compiler = scope HLSLCompiler();
		if (!compiler.IsInitialized)
		{
			Console.WriteLine("Failed to initialize HLSL compiler");
			return .Err;
		}

		// Get shader sources
		let vertSource = scope String();
		let fragSource = scope String();
		provider.GetVertexShaderSource(vertSource);
		provider.GetFragmentShaderSource(fragSource);

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
			Console.WriteLine(scope $"Vertex shader compilation failed: {vertResult.Errors}");
			return .Err;
		}

		ShaderModuleDescriptor vertDesc = .(vertResult.Bytecode);
		if (mDevice.CreateShaderModule(&vertDesc) case .Ok(let vs))
			mVertShader = vs;
		else
			return .Err;

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
			Console.WriteLine(scope $"Fragment shader compilation failed: {fragResult.Errors}");
			return .Err;
		}

		ShaderModuleDescriptor fragDesc = .(fragResult.Bytecode);
		if (mDevice.CreateShaderModule(&fragDesc) case .Ok(let fs))
			mFragShader = fs;
		else
			return .Err;

		return .Ok;
	}

	private Result<void> CreateSampler()
	{
		SamplerDescriptor samplerDesc = .();
		// Default values are already ClampToEdge and Linear, so just create it

		if (mDevice.CreateSampler(&samplerDesc) case .Ok(let sampler))
		{
			mSampler = sampler;
			return .Ok;
		}
		return .Err;
	}

	private Result<void> CreateLayouts()
	{
		// Bind group layout: uniform buffer (b0), texture (t0), sampler (s0)
		BindGroupLayoutEntry[3] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex),
			BindGroupLayoutEntry.SampledTexture(0, .Fragment),
			BindGroupLayoutEntry.Sampler(0, .Fragment)
		);
		BindGroupLayoutDescriptor bindGroupLayoutDesc = .(layoutEntries);
		if (mDevice.CreateBindGroupLayout(&bindGroupLayoutDesc) case .Ok(let layout))
			mBindGroupLayout = layout;
		else
			return .Err;

		// Pipeline layout
		IBindGroupLayout[1] layouts = .(mBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (mDevice.CreatePipelineLayout(&pipelineLayoutDesc) case .Ok(let pipelineLayout))
			mPipelineLayout = pipelineLayout;
		else
			return .Err;

		return .Ok;
	}

	private Result<void> CreatePipeline()
	{
		// Vertex layout: position (float2), texcoord (float2), color (float4)
		VertexAttribute[3] vertexAttributes = .(
			.(VertexFormat.Float2, 0, 0),   // Position
			.(VertexFormat.Float2, 8, 1),   // TexCoord
			.(VertexFormat.Float4, 16, 2)   // Color
		);
		VertexBufferLayout[1] vertexBuffers = .(
			.((uint64)sizeof(UIRenderVertex), vertexAttributes)
		);

		ColorTargetState[1] colorTargets = .(.(mTargetFormat, .AlphaBlend));

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
				CullMode = .None
			},
			DepthStencil = null,
			Multisample = .()
			{
				Count = 1,
				Mask = uint32.MaxValue,
				AlphaToCoverageEnabled = false
			}
		};

		// Create standard pipeline
		if (mDevice.CreateRenderPipeline(&pipelineDesc) case .Ok(let pipeline))
			mPipeline = pipeline;
		else
			return .Err;

		// Create MSAA pipeline variant
		pipelineDesc.Multisample.Count = mMsaaSampleCount;
		if (mDevice.CreateRenderPipeline(&pipelineDesc) case .Ok(let msaaPipeline))
			mMsaaPipeline = msaaPipeline;
		else
			return .Err;

		return .Ok;
	}

	private Result<void> CreatePerFrameResources()
	{
		mVertexBuffers = new IBuffer[mFrameCount];
		mIndexBuffers = new IBuffer[mFrameCount];
		mUniformBuffers = new IBuffer[mFrameCount];
		mBindGroups = new IBindGroup[mFrameCount];

		for (int32 i = 0; i < mFrameCount; i++)
		{
			// Vertex buffer
			BufferDescriptor vertexDesc = .()
			{
				Size = (uint64)(MAX_VERTICES * sizeof(UIRenderVertex)),
				Usage = .Vertex | .CopyDst
			};
			if (mDevice.CreateBuffer(&vertexDesc) case .Ok(let vb))
				mVertexBuffers[i] = vb;
			else
				return .Err;

			// Index buffer
			BufferDescriptor indexDesc = .()
			{
				Size = (uint64)(MAX_INDICES * sizeof(uint16)),
				Usage = .Index | .CopyDst
			};
			if (mDevice.CreateBuffer(&indexDesc) case .Ok(let ib))
				mIndexBuffers[i] = ib;
			else
				return .Err;

			// Uniform buffer
			BufferDescriptor uniformDesc = .()
			{
				Size = (uint64)sizeof(UIUniforms),
				Usage = .Uniform | .CopyDst
			};
			if (mDevice.CreateBuffer(&uniformDesc) case .Ok(let ub))
				mUniformBuffers[i] = ub;
			else
				return .Err;
		}

		return .Ok;
	}

	private void UpdateBindGroup(int32 frameIndex)
	{
		// Delete old bind group if exists
		if (mBindGroups[frameIndex] != null)
		{
			delete mBindGroups[frameIndex];
			mBindGroups[frameIndex] = null;
		}

		if (mTextureView == null)
			return;

		BindGroupEntry[3] bindGroupEntries = .(
			BindGroupEntry.Buffer(0, mUniformBuffers[frameIndex]),
			BindGroupEntry.Texture(0, mTextureView),
			BindGroupEntry.Sampler(0, mSampler)
		);
		BindGroupDescriptor bindGroupDesc = .(mBindGroupLayout, bindGroupEntries);
		if (mDevice.CreateBindGroup(&bindGroupDesc) case .Ok(let group))
			mBindGroups[frameIndex] = group;
	}

	public void Dispose()
	{
		// Per-frame resources
		if (mBindGroups != null)
		{
			for (let bg in mBindGroups)
				if (bg != null) delete bg;
			delete mBindGroups;
			mBindGroups = null;
		}

		if (mUniformBuffers != null)
		{
			for (let ub in mUniformBuffers)
				if (ub != null) delete ub;
			delete mUniformBuffers;
			mUniformBuffers = null;
		}

		if (mIndexBuffers != null)
		{
			for (let ib in mIndexBuffers)
				if (ib != null) delete ib;
			delete mIndexBuffers;
			mIndexBuffers = null;
		}

		if (mVertexBuffers != null)
		{
			for (let vb in mVertexBuffers)
				if (vb != null) delete vb;
			delete mVertexBuffers;
			mVertexBuffers = null;
		}

		// Pipeline resources
		if (mMsaaPipeline != null) { delete mMsaaPipeline; mMsaaPipeline = null; }
		if (mPipeline != null) { delete mPipeline; mPipeline = null; }
		if (mPipelineLayout != null) { delete mPipelineLayout; mPipelineLayout = null; }
		if (mBindGroupLayout != null) { delete mBindGroupLayout; mBindGroupLayout = null; }

		// Sampler
		if (mSampler != null) { delete mSampler; mSampler = null; }

		// Shaders
		Console.WriteLine("  Disposing shaders");
		if (mFragShader != null) { delete mFragShader; mFragShader = null; }
		if (mVertShader != null) { delete mVertShader; mVertShader = null; }

		IsInitialized = false;
	}
}
