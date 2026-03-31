namespace RG001_Triangle;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.RenderGraph;
using SampleFramework;

/// Renders a colored triangle using the render graph.
/// Demonstrates: importing swap chain backbuffer, declaring a render pass,
/// automatic barrier insertion, and pass execution callbacks.
class RGTriangleSample : SampleApp
{
	const String cShaderSource = """
		struct VSInput
		{
		    float3 Position : TEXCOORD0;
		    float3 Color    : TEXCOORD1;
		};
	
		struct PSInput
		{
		    float4 Position : SV_POSITION;
		    float3 Color    : TEXCOORD0;
		};
	
		PSInput VSMain(VSInput input)
		{
		    PSInput output;
		    output.Position = float4(input.Position, 1.0);
		    output.Color = input.Color;
		    return output;
		}
	
		float4 PSMain(PSInput input) : SV_TARGET
		{
		    return float4(input.Color, 1.0);
		}
		""";

	static float[18] sVertexData = .( // Top — red
		0.0f,  0.5f, 0.0f,    1.0f, 0.0f, 0.0f, // Bottom-right — green
		0.5f, -0.5f, 0.0f,    0.0f, 1.0f, 0.0f, // Bottom-left — blue
		-0.5f, -0.5f, 0.0f,    0.0f, 0.0f, 1.0f
		);

	// GPU resources (persistent across frames)
	private ShaderCompiler mShaderCompiler;
	private IBuffer mVertexBuffer;
	private IShaderModule mVertexShader;
	private IShaderModule mPixelShader;
	private IBindGroupLayout mBindGroupLayout;
	private IPipelineLayout mPipelineLayout;
	private IRenderPipeline mPipeline;
	private ICommandPool mCommandPool;
	private IFence mFrameFence;
	private uint64 mFrameFenceValue;

	// Render graph (reused each frame)
	private RenderGraph mGraph;

	protected override StringView Title => "RG001 — Render Graph Triangle";

	protected override Result<void> OnInit()
	{
		// --- Shader compilation ---

		mShaderCompiler = new ShaderCompiler();
		if (mShaderCompiler.Init() case .Err)
		{
			Console.WriteLine("ERROR: ShaderCompiler.Init failed");
			return .Err;
		}

		let format = (mBackendType == .Vulkan) ? ShaderOutputFormat.SPIRV : ShaderOutputFormat.DXIL;
		let vsBytecode = scope List<uint8>();
		let psBytecode = scope List<uint8>();
		let errors = scope String();

		if (mShaderCompiler.CompileVertex(cShaderSource, "VSMain", format, vsBytecode, errors) case .Err)
		{
			Console.WriteLine("VS compile failed: {}", errors);
			return .Err;
		}

		errors.Clear();
		if (mShaderCompiler.CompilePixel(cShaderSource, "PSMain", format, psBytecode, errors) case .Err)
		{
			Console.WriteLine("PS compile failed: {}", errors);
			return .Err;
		}

		// --- GPU resources ---

		let vsResult = mDevice.CreateShaderModule(ShaderModuleDesc() { Code = Span<uint8>(vsBytecode.Ptr, vsBytecode.Count), Label = "TriangleVS" });
		if (vsResult case .Err) { Console.WriteLine("ERROR: CreateShaderModule (VS) failed"); return .Err; }
		mVertexShader = vsResult.Value;

		let psResult = mDevice.CreateShaderModule(ShaderModuleDesc() { Code = Span<uint8>(psBytecode.Ptr, psBytecode.Count), Label = "TrianglePS" });
		if (psResult case .Err) { Console.WriteLine("ERROR: CreateShaderModule (PS) failed"); return .Err; }
		mPixelShader = psResult.Value;

		// Vertex buffer: 3 vertices * 6 floats * 4 bytes = 72 bytes
		let bufResult = mDevice.CreateBuffer(BufferDesc()
			{
				Size = 72,
				Usage = .Vertex | .CopyDst,
				Memory = .GpuOnly,
				Label = "TriangleVB"
			});
		if (bufResult case .Err) { Console.WriteLine("ERROR: CreateBuffer (VB) failed"); return .Err; }
		mVertexBuffer = bufResult.Value;

		// Upload vertex data
		let batch = mGraphicsQueue.CreateTransferBatch();
		if (batch case .Err) { Console.WriteLine("ERROR: CreateTransferBatch failed"); return .Err; }
		var transfer = batch.Value;
		transfer.WriteBuffer(mVertexBuffer, 0, Span<uint8>((uint8*)&sVertexData[0], 72));
		transfer.Submit();
		mGraphicsQueue.DestroyTransferBatch(ref transfer);

		// Empty bind group layout + pipeline layout
		let bglResult = mDevice.CreateBindGroupLayout(BindGroupLayoutDesc() { Entries = default, Label = "EmptyBGL" });
		if (bglResult case .Err) { Console.WriteLine("ERROR: CreateBindGroupLayout failed"); return .Err; }
		mBindGroupLayout = bglResult.Value;

		let bglSpan = scope IBindGroupLayout[1];
		bglSpan[0] = mBindGroupLayout;
		let plResult = mDevice.CreatePipelineLayout(PipelineLayoutDesc()
			{
				BindGroupLayouts = Span<IBindGroupLayout>(bglSpan),
				Label = "TrianglePL"
			});
		if (plResult case .Err) { Console.WriteLine("ERROR: CreatePipelineLayout failed"); return .Err; }
		mPipelineLayout = plResult.Value;

		// Render pipeline
		let vertexAttribs = scope VertexAttribute[2];
		vertexAttribs[0] = VertexAttribute() { ShaderLocation = 0, Format = .Float32x3, Offset = 0 };
		vertexAttribs[1] = VertexAttribute() { ShaderLocation = 1, Format = .Float32x3, Offset = 12 };

		let vertexLayouts = scope VertexBufferLayout[1];
		vertexLayouts[0] = VertexBufferLayout()
			{
				Stride = 24,
				StepMode = .Vertex,
				Attributes = Span<VertexAttribute>(vertexAttribs)
			};

		let colorTargets = scope ColorTargetState[1];
		colorTargets[0] = ColorTargetState() { Format = mSwapChain.Format, WriteMask = .All };

		let rpDesc = RenderPipelineDesc()
			{
				Layout = mPipelineLayout,
				Vertex = .() { Shader = .(mVertexShader, "VSMain"), Buffers = vertexLayouts },
				Fragment = .() { Shader = .(mPixelShader, "PSMain"), Targets = colorTargets },
				Primitive = PrimitiveState() { Topology = .TriangleList },
				Label = "TrianglePipeline"
			};

		let pipResult = mDevice.CreateRenderPipeline(rpDesc);
		if (pipResult case .Err) { Console.WriteLine("ERROR: CreateRenderPipeline failed"); return .Err; }
		mPipeline = pipResult.Value;

		// Command pool & fence
		let poolResult = mDevice.CreateCommandPool(.Graphics);
		if (poolResult case .Err) { Console.WriteLine("ERROR: CreateCommandPool failed"); return .Err; }
		mCommandPool = poolResult.Value;

		let fenceResult = mDevice.CreateFence(0);
		if (fenceResult case .Err) { Console.WriteLine("ERROR: CreateFence failed"); return .Err; }
		mFrameFence = fenceResult.Value;
		mFrameFenceValue = 0;

		// --- Render graph ---

		mGraph = new RenderGraph();

		// Print graph info on first compile
		Console.WriteLine("RG001: Render graph triangle sample initialized");

		return .Ok;
	}

	protected override void OnRender()
	{
		// Wait for previous frame
		if (mFrameFenceValue > 0)
			mFrameFence.Wait(mFrameFenceValue);

		// Acquire backbuffer
		if (mSwapChain.AcquireNextImage() case .Err) return;

		// ============================================================
		// Build the render graph for this frame
		// ============================================================

		// Import the swap chain backbuffer into the graph.
		// It starts in Present state and must end in Present state.
		let backbuffer = mGraph.ImportTexture(
			"Backbuffer",
			mSwapChain.CurrentTexture,
			mSwapChain.CurrentTextureView,
			.Present
			);

		// Declare a render pass that draws the triangle into the backbuffer.
		// The graph will automatically insert a Present → RenderTarget barrier before this pass.
		mGraph.AddPass("DrawTriangle", .Graphics, scope [&] (builder) =>
			{
				builder.WriteRenderTarget(backbuffer, 0, .Clear, .Store, ClearColor(0.1f, 0.1f, 0.15f, 1.0f));
				builder.HasSideEffects();

				builder.SetExecute(new (encoder, registry) =>
					{
						// Build the render pass descriptor from graph declarations
						let pass = mGraph.GetScheduledPass(0);
						let rpDesc = registry.GetRenderPassDesc(pass);
						let rp = encoder.BeginRenderPass(rpDesc);

						rp.SetPipeline(mPipeline);
						rp.SetViewport(0, 0, (float)mWidth, (float)mHeight, 0.0f, 1.0f);
						rp.SetScissor(0, 0, mWidth, mHeight);
						rp.SetVertexBuffer(0, mVertexBuffer, 0);
						rp.Draw(3);
						rp.End();
					});
			});

		// Compile: topological sort, cull unused passes, solve barriers
		mGraph.Compile();

		// ============================================================
		// Execute the graph
		// ============================================================

		// Reset command pool and create encoder
		mCommandPool.Reset();
		let encoderResult = mCommandPool.CreateEncoder();
		if (encoderResult case .Err) { mGraph.Reset(); return; }
		var encoder = encoderResult.Value;

		// Create resource registry for pass execution
		let registry = scope ResourceRegistry(mGraph);

		// Execute all scheduled passes (barriers are emitted automatically)
		for (int i = 0; i < mGraph.ScheduledPassCount; i++)
		{
			let pass = mGraph.GetScheduledPass(i);

			// Emit barriers the graph computed for this pass
			let barriers = mGraph.GetBarriersForPass(i);
			if (barriers.HasValue)
				EmitBarriers(encoder, barriers.Value);

			// Run the pass callback
			if (pass.ExecuteCallback != null)
				pass.ExecuteCallback(encoder, registry);
		}

		// After all passes, transition backbuffer back to Present.
		// The graph tracked state as RenderTarget after the draw pass.
		let texBarriers = scope TextureBarrier[1];
		texBarriers[0] = TextureBarrier()
			{
				Texture = mSwapChain.CurrentTexture,
				OldState = .RenderTarget,
				NewState = .Present
			};
		encoder.Barrier(BarrierGroup()
			{
				TextureBarriers = Span<TextureBarrier>(texBarriers)
			});

		// Submit
		var cmdBuf = encoder.Finish();
		mFrameFenceValue++;
		mGraphicsQueue.Submit(Span<ICommandBuffer>(&cmdBuf, 1), mFrameFence, mFrameFenceValue);

		mSwapChain.Present(mGraphicsQueue);
		mCommandPool.DestroyEncoder(ref encoder);

		// Reset graph for next frame
		mGraph.Reset();
	}

	/// Emit barriers from the graph's solved barrier data into the command encoder.
	private void EmitBarriers(ICommandEncoder encoder, BarrierSolver.PassBarriers pb)
	{
		let texCount = pb.TextureBarriers != null ? pb.TextureBarriers.Count : 0;
		let bufCount = pb.BufferBarriers != null ? pb.BufferBarriers.Count : 0;
		let memCount = pb.MemoryBarriers != null ? pb.MemoryBarriers.Count : 0;

		if (texCount == 0 && bufCount == 0 && memCount == 0)
			return;

		BarrierGroup group = .();

		if (texCount > 0)
		{
			let barriers = scope:: TextureBarrier[texCount];
			barriers.SetAll(.());
			for (int i = 0; i < texCount; i++)
				barriers[i] = pb.TextureBarriers[i];
			group.TextureBarriers = barriers;
		}

		if (bufCount > 0)
		{
			let barriers = scope:: BufferBarrier[bufCount];
			barriers.SetAll(.());
			for (int i = 0; i < bufCount; i++)
				barriers[i] = pb.BufferBarriers[i];
			group.BufferBarriers = barriers;
		}

		if (memCount > 0)
		{
			let barriers = scope:: MemoryBarrier[memCount];
			barriers.SetAll(.());
			for (int i = 0; i < memCount; i++)
				barriers[i] = pb.MemoryBarriers[i];
			group.MemoryBarriers = barriers;
		}

		encoder.Barrier(group);
	}

	protected override void OnShutdown()
	{
		mDevice?.WaitIdle();

		delete mGraph;

		if (mFrameFence != null)
			mDevice?.DestroyFence(ref mFrameFence);
		if (mCommandPool != null)
			mDevice?.DestroyCommandPool(ref mCommandPool);
		if (mPipeline != null)
			mDevice?.DestroyRenderPipeline(ref mPipeline);
		if (mPipelineLayout != null)
			mDevice?.DestroyPipelineLayout(ref mPipelineLayout);
		if (mBindGroupLayout != null)
			mDevice?.DestroyBindGroupLayout(ref mBindGroupLayout);
		if (mPixelShader != null)
			mDevice?.DestroyShaderModule(ref mPixelShader);
		if (mVertexShader != null)
			mDevice?.DestroyShaderModule(ref mVertexShader);
		if (mVertexBuffer != null)
			mDevice?.DestroyBuffer(ref mVertexBuffer);
		if (mShaderCompiler != null)
		{
			mShaderCompiler.Destroy();
			delete mShaderCompiler;
		}
	}
}

class Program
{
	public static int Main(String[] args)
	{
		let app = scope RGTriangleSample();
		return app.Run();
	}
}
