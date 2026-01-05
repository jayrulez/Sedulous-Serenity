namespace RHIQueries;

using System;
using Sedulous.Mathematics;
using Sedulous.RHI;
using RHI.SampleFramework;
using Sedulous.Shell.Input;

/// Vertex structure with position and color
[CRepr]
struct Vertex
{
	public float[2] Position;
	public float[3] Color;

	public this(float x, float y, float r, float g, float b)
	{
		Position = .(x, y);
		Color = .(r, g, b);
	}
}

/// Sample demonstrating GPU query functionality.
/// - Timestamp queries measure GPU execution time
/// - Occlusion queries count visible fragments
///
/// Press T to toggle timestamp query display
/// Press O to toggle occlusion query display
/// Press Space to toggle visibility of the occluded quad
class QueriesSample : RHISampleApp
{
	private IBuffer mVertexBuffer;
	private IBuffer mOccludedVertexBuffer;
	private IShaderModule mVertShader;
	private IShaderModule mFragShader;
	private IBindGroupLayout mBindGroupLayout;
	private IPipelineLayout mPipelineLayout;
	private IRenderPipeline mPipeline;

	// Query sets
	private IQuerySet mTimestampQuerySet;
	private IQuerySet mOcclusionQuerySet;

	// Query results buffer (for timestamp resolve)
	private IBuffer mQueryResultBuffer;

	// Display options
	private bool mShowTimestamps = true;
	private bool mShowOcclusion = true;
	private bool mShowOccludedQuad = true;

	// Timing stats
	private float mLastGpuTimeMs = 0.0f;
	private uint64 mLastOccludedSamples = 0;
	private float mTimestampPeriod = 1.0f;

	// Track if queries have been written (can't read before first frame)
	private bool mQueriesReady = false;

	public this() : base(.()
		{
			Title = "RHI Queries",
			Width = 800,
			Height = 600,
			ClearColor = .(0.1f, 0.1f, 0.15f, 1.0f)
		})
	{
	}

	protected override bool OnInitialize()
	{
		if (!CreateBuffers())
			return false;

		if (!CreateQuerySets())
			return false;

		if (!CreatePipeline())
			return false;

		// Get timestamp period for conversion
		mTimestampPeriod = Device.Queue.GetTimestampPeriod();

		Console.WriteLine("=== RHI Queries Sample ===");
		Console.WriteLine("Press T to toggle timestamp display");
		Console.WriteLine("Press O to toggle occlusion display");
		Console.WriteLine("Press Space to toggle occluded quad visibility");
		Console.WriteLine("");
		Console.WriteLine("Timestamp period: {0:.4} ns/tick", mTimestampPeriod);
		Console.WriteLine("");

		return true;
	}

	private bool CreateBuffers()
	{
		// Main triangle (large, in front)
		Vertex[3] triangleVertices = .(
			.(0.0f, -0.6f, 1.0f, 0.3f, 0.3f),   // Top - Red
			.(0.6f, 0.6f, 0.3f, 1.0f, 0.3f),    // Bottom right - Green
			.(-0.6f, 0.6f, 0.3f, 0.3f, 1.0f)    // Bottom left - Blue
		);

		BufferDescriptor vertexDesc = .()
		{
			Size = (uint64)(sizeof(Vertex) * triangleVertices.Count),
			Usage = .Vertex,
			MemoryAccess = .Upload
		};

		if (Device.CreateBuffer(&vertexDesc) not case .Ok(let vb))
			return false;
		mVertexBuffer = vb;

		Span<uint8> vertexData = .((uint8*)&triangleVertices, (int)vertexDesc.Size);
		Device.Queue.WriteBuffer(mVertexBuffer, 0, vertexData);

		// Occluded quad (partially behind the triangle)
		Vertex[6] quadVertices = .(
			// First triangle
			.(-0.3f, -0.3f, 1.0f, 1.0f, 0.0f),  // Yellow
			.(0.3f, -0.3f, 1.0f, 1.0f, 0.0f),
			.(0.3f, 0.3f, 1.0f, 1.0f, 0.0f),
			// Second triangle
			.(-0.3f, -0.3f, 1.0f, 1.0f, 0.0f),
			.(0.3f, 0.3f, 1.0f, 1.0f, 0.0f),
			.(-0.3f, 0.3f, 1.0f, 1.0f, 0.0f)
		);

		BufferDescriptor occludedDesc = .()
		{
			Size = (uint64)(sizeof(Vertex) * quadVertices.Count),
			Usage = .Vertex,
			MemoryAccess = .Upload
		};

		if (Device.CreateBuffer(&occludedDesc) not case .Ok(let ovb))
			return false;
		mOccludedVertexBuffer = ovb;

		Span<uint8> occludedData = .((uint8*)&quadVertices, (int)occludedDesc.Size);
		Device.Queue.WriteBuffer(mOccludedVertexBuffer, 0, occludedData);

		// Query results buffer for timestamp resolve
		BufferDescriptor queryBufferDesc = .()
		{
			Size = (uint64)(sizeof(uint64) * 4),  // Space for 4 timestamps
			Usage = .CopyDst,
			MemoryAccess = .Readback
		};

		if (Device.CreateBuffer(&queryBufferDesc) not case .Ok(let qb))
			return false;
		mQueryResultBuffer = qb;

		Console.WriteLine("Buffers created");
		return true;
	}

	private bool CreateQuerySets()
	{
		// Create timestamp query set (2 queries: start and end)
		QuerySetDescriptor timestampDesc = .(.Timestamp, 2, "Timestamp Queries");
		if (Device.CreateQuerySet(&timestampDesc) not case .Ok(let ts))
		{
			Console.WriteLine("Failed to create timestamp query set");
			return false;
		}
		mTimestampQuerySet = ts;

		// Create occlusion query set (1 query for the occluded object)
		QuerySetDescriptor occlusionDesc = .(.Occlusion, 1, "Occlusion Query");
		if (Device.CreateQuerySet(&occlusionDesc) not case .Ok(let os))
		{
			Console.WriteLine("Failed to create occlusion query set");
			return false;
		}
		mOcclusionQuerySet = os;

		Console.WriteLine("Query sets created");
		return true;
	}

	private bool CreatePipeline()
	{
		// Load shaders
		let shaderResult = ShaderUtils.LoadShaderPair(Device, "shaders/simple");
		if (shaderResult case .Err)
			return false;

		(mVertShader, mFragShader) = shaderResult.Get();

		// Create empty bind group layout
		BindGroupLayoutEntry[0] layoutEntries = .();
		BindGroupLayoutDescriptor bindGroupLayoutDesc = .(layoutEntries);
		if (Device.CreateBindGroupLayout(&bindGroupLayoutDesc) not case .Ok(let layout))
			return false;
		mBindGroupLayout = layout;

		// Create pipeline layout
		IBindGroupLayout[1] layouts = .(mBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (Device.CreatePipelineLayout(&pipelineLayoutDesc) not case .Ok(let pipelineLayout))
			return false;
		mPipelineLayout = pipelineLayout;

		// Vertex attributes
		VertexAttribute[2] vertexAttributes = .(
			.(VertexFormat.Float2, 0, 0),
			.(VertexFormat.Float3, 8, 1)
		);
		VertexBufferLayout[1] vertexBuffers = .(
			.((uint64)sizeof(Vertex), vertexAttributes)
		);

		// Color target
		ColorTargetState[1] colorTargets = .(.(SwapChain.Format));

		// Pipeline descriptor
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

		if (Device.CreateRenderPipeline(&pipelineDesc) not case .Ok(let pipeline))
			return false;
		mPipeline = pipeline;

		Console.WriteLine("Pipeline created");
		return true;
	}

	protected override void OnKeyDown(KeyCode key)
	{
		switch (key)
		{
		case .T:
			mShowTimestamps = !mShowTimestamps;
			Console.WriteLine("Timestamp display: {0}", mShowTimestamps ? "ON" : "OFF");
		case .O:
			mShowOcclusion = !mShowOcclusion;
			Console.WriteLine("Occlusion display: {0}", mShowOcclusion ? "ON" : "OFF");
		case .Space:
			mShowOccludedQuad = !mShowOccludedQuad;
			Console.WriteLine("Occluded quad: {0}", mShowOccludedQuad ? "VISIBLE" : "HIDDEN");
		default:
		}
	}

	protected override void OnUpdate(float deltaTime, float totalTime)
	{
		// Only read query results after they've been written
		if (!mQueriesReady)
			return;

		// Display query results periodically
		if (mShowTimestamps || mShowOcclusion)
		{
			// Get timestamp results
			if (mShowTimestamps)
			{
				uint64[2] timestamps = .();
				Span<uint8> tsData = .((uint8*)&timestamps, sizeof(uint64) * 2);
				if (mTimestampQuerySet.GetResults(0, 2, tsData, false))
				{
					if (timestamps[1] > timestamps[0])
					{
						uint64 elapsedTicks = timestamps[1] - timestamps[0];
						float elapsedNs = (float)elapsedTicks * mTimestampPeriod;
						mLastGpuTimeMs = elapsedNs / 1000000.0f;
					}
				}
			}

			// Get occlusion results
			if (mShowOcclusion && mShowOccludedQuad)
			{
				uint64[1] samples = .();
				Span<uint8> occData = .((uint8*)&samples, sizeof(uint64));
				if (mOcclusionQuerySet.GetResults(0, 1, occData, false))
				{
					mLastOccludedSamples = samples[0];
				}
			}
		}
	}

	protected override bool OnRenderFrame(ICommandEncoder encoder, int32 frameIndex)
	{
		// Reset queries before recording
		encoder.ResetQuerySet(mTimestampQuerySet, 0, 2);
		encoder.ResetQuerySet(mOcclusionQuerySet, 0, 1);

		// Write start timestamp
		encoder.WriteTimestamp(mTimestampQuerySet, 0);

		// Begin render pass
		RenderPassColorAttachment[1] colorAttachments = .(
			.()
			{
				View = SwapChain.CurrentTextureView,
				LoadOp = .Clear,
				StoreOp = .Store,
				ClearValue = mConfig.ClearColor
			}
		);

		RenderPassDescriptor renderPassDesc = .(colorAttachments);
		let renderPass = encoder.BeginRenderPass(&renderPassDesc);
		if (renderPass != null)
		{
			renderPass.SetPipeline(mPipeline);

			// Set viewport and scissor
			renderPass.SetViewport(0, 0, SwapChain.Width, SwapChain.Height, 0, 1);
			renderPass.SetScissorRect(0, 0, SwapChain.Width, SwapChain.Height);

			// Draw main triangle first (will occlude the quad)
			renderPass.SetVertexBuffer(0, mVertexBuffer, 0);
			renderPass.Draw(3, 1, 0, 0);

			// Draw occluded quad with occlusion query
			if (mShowOccludedQuad)
			{
				encoder.BeginQuery(mOcclusionQuerySet, 0);
				renderPass.SetVertexBuffer(0, mOccludedVertexBuffer, 0);
				renderPass.Draw(6, 1, 0, 0);
				encoder.EndQuery(mOcclusionQuerySet, 0);
			}

			renderPass.End();
			delete renderPass;
		}

		// Write end timestamp
		encoder.WriteTimestamp(mTimestampQuerySet, 1);

		// Queries are now ready to be read (next frame)
		mQueriesReady = true;

		return true;  // We handled rendering
	}

	protected override void OnRender(IRenderPassEncoder renderPass)
	{
		// Not used - we use OnRenderCustom for query control
	}

	protected override void OnFrameEnd()
	{
		// Print stats periodically (every ~60 frames)
		static int frameCount = 0;
		frameCount++;
		if (frameCount % 60 == 0)
		{
			if (mShowTimestamps)
				Console.WriteLine("GPU Time: {0:.3} ms", mLastGpuTimeMs);
			if (mShowOcclusion && mShowOccludedQuad)
				Console.WriteLine("Visible samples: {0}", mLastOccludedSamples);
		}
	}

	protected override void OnCleanup()
	{
		if (mPipeline != null) delete mPipeline;
		if (mPipelineLayout != null) delete mPipelineLayout;
		if (mBindGroupLayout != null) delete mBindGroupLayout;
		if (mFragShader != null) delete mFragShader;
		if (mVertShader != null) delete mVertShader;
		if (mQueryResultBuffer != null) delete mQueryResultBuffer;
		if (mOcclusionQuerySet != null) delete mOcclusionQuerySet;
		if (mTimestampQuerySet != null) delete mTimestampQuerySet;
		if (mOccludedVertexBuffer != null) delete mOccludedVertexBuffer;
		if (mVertexBuffer != null) delete mVertexBuffer;
	}
}

class Program
{
	public static int Main(String[] args)
	{
		let app = scope QueriesSample();
		return app.Run();
	}
}
