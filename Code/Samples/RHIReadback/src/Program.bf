namespace RHIReadback;

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

/// Sample demonstrating buffer and texture readback functionality.
/// Press R to read back the vertex buffer and verify data.
/// Press T to read back the test texture and verify pixel data.
class ReadbackSample : RHISampleApp
{
	private IBuffer mVertexBuffer;
	private IShaderModule mVertShader;
	private IShaderModule mFragShader;
	private IBindGroupLayout mBindGroupLayout;
	private IPipelineLayout mPipelineLayout;
	private IRenderPipeline mPipeline;

	// Test texture for readback
	private ITexture mTestTexture;
	private const uint32 TEST_TEXTURE_SIZE = 4;

	// Original vertex data for verification
	private Vertex[3] mOriginalVertices;

	// Original texture data for verification
	private uint8[TEST_TEXTURE_SIZE * TEST_TEXTURE_SIZE * 4] mOriginalTextureData;

	public this() : base(.()
		{
			Title = "RHI Readback",
			Width = 800,
			Height = 600,
			ClearColor = .(0.1f, 0.1f, 0.2f, 1.0f)
		})
	{
	}

	protected override bool OnInitialize()
	{
		if (!CreateBuffers())
			return false;

		if (!CreateTestTexture())
			return false;

		if (!CreatePipeline())
			return false;

		Console.WriteLine("=== RHI Readback Sample ===");
		Console.WriteLine("Press R to read back vertex buffer and verify data");
		Console.WriteLine("Press T to read back test texture and verify pixel data");
		Console.WriteLine("");

		return true;
	}

	private bool CreateBuffers()
	{
		// Define triangle vertices (position + color)
		mOriginalVertices = .(
			.(0.0f, -0.5f, 1.0f, 0.0f, 0.0f),   // Top - Red
			.(0.5f, 0.5f, 0.0f, 1.0f, 0.0f),    // Bottom right - Green
			.(-0.5f, 0.5f, 0.0f, 0.0f, 1.0f)    // Bottom left - Blue
		);

		// Create vertex buffer with CopySrc so we can read it back
		BufferDescriptor vertexDesc = .()
		{
			Size = (uint64)(sizeof(Vertex) * mOriginalVertices.Count),
			Usage = .Vertex | .CopySrc,
			MemoryAccess = .Upload
		};

		if (Device.CreateBuffer(&vertexDesc) not case .Ok(let vb))
			return false;
		mVertexBuffer = vb;

		Span<uint8> vertexData = .((uint8*)&mOriginalVertices, (int)vertexDesc.Size);
		Device.Queue.WriteBuffer(mVertexBuffer, 0, vertexData);

		Console.WriteLine("Vertex buffer created and initialized");
		return true;
	}

	private bool CreateTestTexture()
	{
		// Create a small RGBA test texture with a known pattern
		// Pattern: Red, Green, Blue, White in 2x2 blocks
		for (uint32 y = 0; y < TEST_TEXTURE_SIZE; y++)
		{
			for (uint32 x = 0; x < TEST_TEXTURE_SIZE; x++)
			{
				int idx = (int)((y * TEST_TEXTURE_SIZE + x) * 4);

				// Quadrant-based colors
				if (x < TEST_TEXTURE_SIZE / 2 && y < TEST_TEXTURE_SIZE / 2)
				{
					// Top-left: Red
					mOriginalTextureData[idx + 0] = 255;
					mOriginalTextureData[idx + 1] = 0;
					mOriginalTextureData[idx + 2] = 0;
					mOriginalTextureData[idx + 3] = 255;
				}
				else if (x >= TEST_TEXTURE_SIZE / 2 && y < TEST_TEXTURE_SIZE / 2)
				{
					// Top-right: Green
					mOriginalTextureData[idx + 0] = 0;
					mOriginalTextureData[idx + 1] = 255;
					mOriginalTextureData[idx + 2] = 0;
					mOriginalTextureData[idx + 3] = 255;
				}
				else if (x < TEST_TEXTURE_SIZE / 2 && y >= TEST_TEXTURE_SIZE / 2)
				{
					// Bottom-left: Blue
					mOriginalTextureData[idx + 0] = 0;
					mOriginalTextureData[idx + 1] = 0;
					mOriginalTextureData[idx + 2] = 255;
					mOriginalTextureData[idx + 3] = 255;
				}
				else
				{
					// Bottom-right: White
					mOriginalTextureData[idx + 0] = 255;
					mOriginalTextureData[idx + 1] = 255;
					mOriginalTextureData[idx + 2] = 255;
					mOriginalTextureData[idx + 3] = 255;
				}
			}
		}

		// Create texture with CopySrc for readback and CopyDst for initial upload
		TextureDescriptor texDesc = .()
		{
			Dimension = .Texture2D,
			Width = TEST_TEXTURE_SIZE,
			Height = TEST_TEXTURE_SIZE,
			Depth = 1,
			ArrayLayerCount = 1,
			MipLevelCount = 1,
			Format = .RGBA8Unorm,
			Usage = .Sampled | .CopySrc | .CopyDst
		};

		if (Device.CreateTexture(&texDesc) not case .Ok(let tex))
			return false;
		mTestTexture = tex;

		// Upload texture data
		TextureDataLayout layout = .()
		{
			Offset = 0,
			BytesPerRow = TEST_TEXTURE_SIZE * 4,
			RowsPerImage = TEST_TEXTURE_SIZE
		};
		Extent3D size = .(TEST_TEXTURE_SIZE, TEST_TEXTURE_SIZE, 1);
		Span<uint8> texData = .(&mOriginalTextureData, mOriginalTextureData.Count);
		Device.Queue.WriteTexture(mTestTexture, texData, &layout, &size);

		Console.WriteLine("Test texture created ({0}x{0} RGBA)", TEST_TEXTURE_SIZE);
		return true;
	}

	private bool CreatePipeline()
	{
		// Load shaders
		let shaderResult = ShaderUtils.LoadShaderPair(Device, "shaders/simple");
		if (shaderResult case .Err)
			return false;

		(mVertShader, mFragShader) = shaderResult.Get();

		// Create empty bind group layout (no uniforms needed)
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
			.(VertexFormat.Float2, 0, 0),   // Position at location 0
			.(VertexFormat.Float3, 8, 1)    // Color at location 1
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
		case .R:
			ReadBackVertexBuffer();
		case .T:
			ReadBackTexture();
		default:
		}
	}

	private void ReadBackVertexBuffer()
	{
		Console.WriteLine("\n--- Reading back vertex buffer ---");

		// Allocate buffer for readback
		uint64 bufferSize = (uint64)(sizeof(Vertex) * 3);
		Vertex[3] readbackVertices = .();
		Span<uint8> readbackData = .((uint8*)&readbackVertices, (int)bufferSize);

		// Read buffer
		Device.Queue.ReadBuffer(mVertexBuffer, 0, readbackData);

		// Verify data
		bool allMatch = true;
		for (int i = 0; i < 3; i++)
		{
			let orig = mOriginalVertices[i];
			let read = readbackVertices[i];

			bool posMatch = (orig.Position[0] == read.Position[0]) && (orig.Position[1] == read.Position[1]);
			bool colMatch = (orig.Color[0] == read.Color[0]) && (orig.Color[1] == read.Color[1]) && (orig.Color[2] == read.Color[2]);

			if (posMatch && colMatch)
			{
				Console.WriteLine("  Vertex {0}: MATCH - pos({1:.2}, {2:.2}) color({3:.2}, {4:.2}, {5:.2})",
					i, read.Position[0], read.Position[1], read.Color[0], read.Color[1], read.Color[2]);
			}
			else
			{
				Console.WriteLine("  Vertex {0}: MISMATCH!", i);
				Console.WriteLine("    Original: pos({0:.2}, {1:.2}) color({2:.2}, {3:.2}, {4:.2})",
					orig.Position[0], orig.Position[1], orig.Color[0], orig.Color[1], orig.Color[2]);
				Console.WriteLine("    Readback: pos({0:.2}, {1:.2}) color({2:.2}, {3:.2}, {4:.2})",
					read.Position[0], read.Position[1], read.Color[0], read.Color[1], read.Color[2]);
				allMatch = false;
			}
		}

		if (allMatch)
			Console.WriteLine("Buffer readback VERIFIED - all data matches!");
		else
			Console.WriteLine("Buffer readback FAILED - data mismatch detected!");
	}

	private void ReadBackTexture()
	{
		Console.WriteLine("\n--- Reading back texture ---");

		// Allocate buffer for readback
		uint8[TEST_TEXTURE_SIZE * TEST_TEXTURE_SIZE * 4] readbackData = .();
		Span<uint8> readbackSpan = .(&readbackData, readbackData.Count);

		TextureDataLayout layout = .()
		{
			Offset = 0,
			BytesPerRow = TEST_TEXTURE_SIZE * 4,
			RowsPerImage = TEST_TEXTURE_SIZE
		};
		Extent3D size = .(TEST_TEXTURE_SIZE, TEST_TEXTURE_SIZE, 1);

		// Read texture
		Device.Queue.ReadTexture(mTestTexture, readbackSpan, &layout, &size);

		// Verify data
		int mismatches = 0;
		for (uint32 y = 0; y < TEST_TEXTURE_SIZE; y++)
		{
			for (uint32 x = 0; x < TEST_TEXTURE_SIZE; x++)
			{
				int idx = (int)((y * TEST_TEXTURE_SIZE + x) * 4);

				bool match =
					mOriginalTextureData[idx + 0] == readbackData[idx + 0] &&
					mOriginalTextureData[idx + 1] == readbackData[idx + 1] &&
					mOriginalTextureData[idx + 2] == readbackData[idx + 2] &&
					mOriginalTextureData[idx + 3] == readbackData[idx + 3];

				if (!match)
				{
					mismatches++;
					Console.WriteLine("  Pixel ({0},{1}): MISMATCH - expected ({2},{3},{4},{5}), got ({6},{7},{8},{9})",
						x, y,
						mOriginalTextureData[idx + 0], mOriginalTextureData[idx + 1],
						mOriginalTextureData[idx + 2], mOriginalTextureData[idx + 3],
						readbackData[idx + 0], readbackData[idx + 1],
						readbackData[idx + 2], readbackData[idx + 3]);
				}
			}
		}

		if (mismatches == 0)
		{
			Console.WriteLine("Texture readback VERIFIED - all {0} pixels match!", TEST_TEXTURE_SIZE * TEST_TEXTURE_SIZE);
			Console.WriteLine("  Quadrant colors verified: Red, Green, Blue, White");
		}
		else
		{
			Console.WriteLine("Texture readback FAILED - {0} pixel mismatches detected!", mismatches);
		}
	}

	protected override void OnRender(IRenderPassEncoder renderPass)
	{
		renderPass.SetPipeline(mPipeline);
		renderPass.SetVertexBuffer(0, mVertexBuffer, 0);
		renderPass.Draw(3, 1, 0, 0);
	}

	protected override void OnCleanup()
	{
		if (mPipeline != null) delete mPipeline;
		if (mPipelineLayout != null) delete mPipelineLayout;
		if (mBindGroupLayout != null) delete mBindGroupLayout;
		if (mFragShader != null) delete mFragShader;
		if (mVertShader != null) delete mVertShader;
		if (mTestTexture != null) delete mTestTexture;
		if (mVertexBuffer != null) delete mVertexBuffer;
	}
}

class Program
{
	public static int Main(String[] args)
	{
		let app = scope ReadbackSample();
		return app.Run();
	}
}
