namespace DrawingSandbox;

using System;
using System.Collections;
using System.IO;
using Sedulous.Mathematics;
using Sedulous.RHI;
using SampleFramework;
using Sedulous.Drawing;
using Sedulous.Fonts;
using Sedulous.Fonts.TTF;

// Type aliases to resolve ambiguity between Sedulous.RHI.ITexture and Sedulous.Drawing.ITexture
typealias RHITexture = Sedulous.RHI.ITexture;
typealias DrawingTexture = Sedulous.Drawing.ITexture;

/// Vertex structure matching DrawVertex layout for GPU rendering.
[CRepr]
struct RenderVertex
{
	public float[2] Position;
	public float[2] TexCoord;
	public float[4] Color;

	public this(DrawVertex v)
	{
		Position = .(v.Position.X, v.Position.Y);
		TexCoord = .(v.TexCoord.X, v.TexCoord.Y);
		Color = .(v.Color.R / 255.0f, v.Color.G / 255.0f, v.Color.B / 255.0f, v.Color.A / 255.0f);
	}
}

/// Uniform buffer data for the projection matrix.
[CRepr]
struct Uniforms
{
	public Matrix Projection;
}

/// Drawing sandbox sample demonstrating Sedulous.Drawing capabilities.
class DrawingSandboxSample : RHISampleApp
{
	// Drawing context
	private DrawContext mDrawContext = new .() ~ delete _;

	// Font resources
	private IFont mFont;
	private IFontAtlas mFontAtlas;
	private TextureRef mFontTextureRef ~ delete _;

	// GPU resources - double buffered to avoid write-while-read flickering
	private IBuffer[2] mVertexBuffers;
	private IBuffer[2] mIndexBuffers;
	private IBuffer mUniformBuffer;
	private RHITexture mAtlasTexture;
	private ITextureView mAtlasTextureView;
	private ISampler mSampler;
	private IShaderModule mVertShader;
	private IShaderModule mFragShader;
	private IBindGroupLayout mBindGroupLayout;
	private IBindGroup mBindGroup;
	private IPipelineLayout mPipelineLayout;
	private IRenderPipeline mPipeline;

	// Double buffer index
	private int mBufferIndex = 0;

	// Dynamic vertex/index data
	private List<RenderVertex> mVertices = new .() ~ delete _;
	private List<uint16> mIndices = new .() ~ delete _;
	private int mMaxQuads = 4096;

	// Animation state
	private float mAnimationTime = 0;

	// FPS tracking
	private int mFrameCount = 0;
	private float mFpsTimer = 0;
	private int mCurrentFps = 0;

	public this() : base(.()
		{
			Title = "Drawing Sandbox",
			Width = 1280,
			Height = 720,
			ClearColor = .(0.1f, 0.1f, 0.15f, 1.0f)
		})
	{
	}

	protected override bool OnInitialize()
	{
		if (!InitializeFont())
			return false;

		if (!CreateAtlasTexture())
			return false;

		if (!CreateBuffers())
			return false;

		if (!CreateBindings())
			return false;

		if (!CreatePipeline())
			return false;

		// Set white pixel UV from the font atlas
		let (u, v) = mFontAtlas.WhitePixelUV;
		mDrawContext.WhitePixelUV = .(u, v);

		return true;
	}

	private bool InitializeFont()
	{
		// Use Roboto font from assets
		String fontPath = scope .();
		GetAssetPath("framework/fonts/roboto/Roboto-Regular.ttf", fontPath);

		if (!File.Exists(fontPath))
		{
			Console.WriteLine(scope $"Font not found: {fontPath}");
			return false;
		}

		Console.WriteLine(scope $"Loading font: {fontPath}");

		// Initialize TrueType font support
		TrueTypeFonts.Initialize();

		// Load font with size 20, extended Latin for diacritics (Å, Ô, é, etc.)
		FontLoadOptions options = .ExtendedLatin;
		options.PixelHeight = 20;

		if (FontLoaderFactory.LoadFont(fontPath, options) case .Ok(let font))
		{
			mFont = font;
		}
		else
		{
			Console.WriteLine("Failed to load font");
			return false;
		}

		// Create font atlas
		if (FontLoaderFactory.CreateAtlas(mFont, options) case .Ok(let atlas))
		{
			mFontAtlas = atlas;
			Console.WriteLine(scope $"Font atlas created: {mFontAtlas.Width}x{mFontAtlas.Height}");
		}
		else
		{
			Console.WriteLine("Failed to create font atlas");
			return false;
		}

		return true;
	}

	private bool CreateAtlasTexture()
	{
		// Convert R8 font atlas to RGBA8 for the shader
		// The font atlas stores alpha values in R channel
		let atlasWidth = mFontAtlas.Width;
		let atlasHeight = mFontAtlas.Height;
		let r8Data = mFontAtlas.PixelData;

		// Convert to RGBA8 (white color with alpha from R channel)
		uint8[] rgba8Data = new uint8[atlasWidth * atlasHeight * 4];
		defer delete rgba8Data;

		for (uint32 i = 0; i < atlasWidth * atlasHeight; i++)
		{
			let alpha = r8Data[i];
			rgba8Data[i * 4 + 0] = 255;    // R
			rgba8Data[i * 4 + 1] = 255;    // G
			rgba8Data[i * 4 + 2] = 255;    // B
			rgba8Data[i * 4 + 3] = alpha;  // A (from font atlas)
		}

		// Create texture from atlas data
		TextureDescriptor textureDesc = TextureDescriptor.Texture2D(
			atlasWidth,
			atlasHeight,
			.RGBA8Unorm,
			.Sampled | .CopyDst
		);

		if (Device.CreateTexture(&textureDesc) not case .Ok(let texture))
		{
			Console.WriteLine("Failed to create atlas texture");
			return false;
		}
		mAtlasTexture = texture;

		// Upload RGBA data
		TextureDataLayout dataLayout = .()
		{
			Offset = 0,
			BytesPerRow = atlasWidth * 4,
			RowsPerImage = atlasHeight
		};
		Extent3D writeSize = .(atlasWidth, atlasHeight, 1);
		Device.Queue.WriteTexture(mAtlasTexture, Span<uint8>(rgba8Data.Ptr, rgba8Data.Count), &dataLayout, &writeSize);

		// Create texture view
		TextureViewDescriptor viewDesc = .()
		{
			Format = .RGBA8Unorm
		};
		if (Device.CreateTextureView(mAtlasTexture, &viewDesc) not case .Ok(let view))
		{
			Console.WriteLine("Failed to create atlas texture view");
			return false;
		}
		mAtlasTextureView = view;

		// Create TextureRef for DrawContext
		mFontTextureRef = new TextureRef(mAtlasTexture, atlasWidth, atlasHeight);

		// Create sampler with linear filtering for smooth text
		SamplerDescriptor samplerDesc = .()
		{
			AddressModeU = .ClampToEdge,
			AddressModeV = .ClampToEdge,
			AddressModeW = .ClampToEdge,
			MagFilter = .Linear,
			MinFilter = .Linear,
			MipmapFilter = .Linear
		};
		if (Device.CreateSampler(&samplerDesc) not case .Ok(let sampler))
		{
			Console.WriteLine("Failed to create sampler");
			return false;
		}
		mSampler = sampler;

		Console.WriteLine(scope $"Atlas texture created: {atlasWidth}x{atlasHeight}");
		return true;
	}

	private bool CreateBuffers()
	{
		// Create double-buffered vertex and index buffers to avoid flickering
		uint64 vertexBufferSize = (uint64)(sizeof(RenderVertex) * mMaxQuads * 4);
		uint64 indexBufferSize = (uint64)(sizeof(uint16) * mMaxQuads * 6);

		for (int i = 0; i < 2; i++)
		{
			// Vertex buffer (dynamic)
			BufferDescriptor vertexDesc = .()
			{
				Size = vertexBufferSize,
				Usage = .Vertex,
				MemoryAccess = .Upload
			};

			if (Device.CreateBuffer(&vertexDesc) not case .Ok(let vb))
			{
				Console.WriteLine("Failed to create vertex buffer");
				return false;
			}
			mVertexBuffers[i] = vb;

			// Index buffer (dynamic)
			BufferDescriptor indexDesc = .()
			{
				Size = indexBufferSize,
				Usage = .Index,
				MemoryAccess = .Upload
			};

			if (Device.CreateBuffer(&indexDesc) not case .Ok(let ib))
			{
				Console.WriteLine("Failed to create index buffer");
				return false;
			}
			mIndexBuffers[i] = ib;
		}

		// Uniform buffer
		BufferDescriptor uniformDesc = .()
		{
			Size = (uint64)sizeof(Uniforms),
			Usage = .Uniform,
			MemoryAccess = .Upload
		};

		if (Device.CreateBuffer(&uniformDesc) not case .Ok(let ub))
		{
			Console.WriteLine("Failed to create uniform buffer");
			return false;
		}
		mUniformBuffer = ub;

		Console.WriteLine("Buffers created (double-buffered)");
		return true;
	}

	private bool CreateBindings()
	{
		// Load shaders
		let shaderResult = ShaderUtils.LoadShaderPair(Device, GetAssetPath("samples/DrawingSandbox/shaders/draw", .. scope .()));
		if (shaderResult case .Err)
		{
			Console.WriteLine("Failed to load shaders");
			return false;
		}

		(mVertShader, mFragShader) = shaderResult.Get();
		Console.WriteLine("Shaders compiled");

		// Create bind group layout (uniform buffer + texture + sampler)
		BindGroupLayoutEntry[3] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex),
			BindGroupLayoutEntry.SampledTexture(0, .Fragment),
			BindGroupLayoutEntry.Sampler(0, .Fragment)
		);
		BindGroupLayoutDescriptor bindGroupLayoutDesc = .(layoutEntries);
		if (Device.CreateBindGroupLayout(&bindGroupLayoutDesc) not case .Ok(let layout))
		{
			Console.WriteLine("Failed to create bind group layout");
			return false;
		}
		mBindGroupLayout = layout;

		// Create bind group
		BindGroupEntry[3] bindGroupEntries = .(
			BindGroupEntry.Buffer(0, mUniformBuffer),
			BindGroupEntry.Texture(0, mAtlasTextureView),
			BindGroupEntry.Sampler(0, mSampler)
		);
		BindGroupDescriptor bindGroupDesc = .(mBindGroupLayout, bindGroupEntries);
		if (Device.CreateBindGroup(&bindGroupDesc) not case .Ok(let group))
		{
			Console.WriteLine("Failed to create bind group");
			return false;
		}
		mBindGroup = group;

		// Create pipeline layout
		IBindGroupLayout[1] layouts = .(mBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (Device.CreatePipelineLayout(&pipelineLayoutDesc) not case .Ok(let pipelineLayout))
		{
			Console.WriteLine("Failed to create pipeline layout");
			return false;
		}
		mPipelineLayout = pipelineLayout;

		Console.WriteLine("Bindings created");
		return true;
	}

	private bool CreatePipeline()
	{
		// Vertex attributes matching RenderVertex
		VertexAttribute[3] vertexAttributes = .(
			.(VertexFormat.Float2, 0, 0),   // Position at location 0
			.(VertexFormat.Float2, 8, 1),   // TexCoord at location 1
			.(VertexFormat.Float4, 16, 2)   // Color at location 2
		);
		VertexBufferLayout[1] vertexBuffers = .(
			.((uint64)sizeof(RenderVertex), vertexAttributes)
		);

		// Color target with alpha blending
		ColorTargetState[1] colorTargets = .(.(SwapChain.Format, .AlphaBlend));

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
		{
			Console.WriteLine("Failed to create pipeline");
			return false;
		}
		mPipeline = pipeline;

		Console.WriteLine("Pipeline created");
		return true;
	}

	protected override void OnUpdate(float deltaTime, float totalTime)
	{
		mAnimationTime = totalTime;

		// FPS calculation
		mFrameCount++;
		mFpsTimer += deltaTime;
		if (mFpsTimer >= 1.0f)
		{
			mCurrentFps = mFrameCount;
			mFrameCount = 0;
			mFpsTimer -= 1.0f;
		}

		// Update projection
		UpdateProjection();

		// Build drawing commands
		BuildDrawCommands();
	}

	private void UpdateProjection()
	{
		float width = (float)SwapChain.Width;
		float height = (float)SwapChain.Height;

		Matrix projection;
		if (Device.FlipProjectionRequired)
			projection = Matrix.CreateOrthographicOffCenter(0, width, 0, height, -1, 1);
		else
			projection = Matrix.CreateOrthographicOffCenter(0, width, height, 0, -1, 1);

		Uniforms uniforms = .()
		{
			Projection = projection
		};

		Span<uint8> uniformData = .((uint8*)&uniforms, sizeof(Uniforms));
		Device.Queue.WriteBuffer(mUniformBuffer, 0, uniformData);
	}

	private void BuildDrawCommands()
	{
		mDrawContext.Clear();

		float screenWidth = (float)SwapChain.Width;
		float screenHeight = (float)SwapChain.Height;
		float margin = 20;
		float columnWidth = (screenWidth - margin * 4) / 3;

		// === COLUMN 1: Basic Shapes ===
		float col1X = margin;
		float y = margin;

		// Title
		DrawLabel("BASIC SHAPES", col1X, y, Color.Yellow);
		y += 30;

		// Rectangle
		DrawLabel("Rectangle", col1X, y, Color.White);
		y += 20;
		mDrawContext.FillRect(.(col1X, y, 100, 60), Color.Red);
		y += 80;

		// Rounded Rectangle
		DrawLabel("Rounded Rect", col1X, y, Color.White);
		y += 20;
		mDrawContext.FillRoundedRect(.(col1X, y, 100, 60), 15, Color.Green);
		y += 80;

		// Circle
		DrawLabel("Circle", col1X, y, Color.White);
		y += 20;
		mDrawContext.FillCircle(.(col1X + 50, y + 40), 40, Color.Blue);
		y += 100;

		// Ellipse
		DrawLabel("Ellipse", col1X, y, Color.White);
		y += 20;
		mDrawContext.FillEllipse(.(col1X + 60, y + 30), 60, 30, Color.Purple);
		y += 80;

		// Arc (animated)
		DrawLabel("Arc (animated)", col1X, y, Color.White);
		y += 20;
		float arcSweep = (Math.Sin(mAnimationTime * 2) * 0.5f + 0.5f) * Math.PI_f * 1.8f + 0.2f;
		mDrawContext.FillArc(.(col1X + 50, y + 50), 45, -Math.PI_f / 2, arcSweep, Color.Orange);
		y += 120;

		// === COLUMN 2: Strokes & Lines ===
		float col2X = margin * 2 + columnWidth;
		y = margin;

		DrawLabel("STROKES & LINES", col2X, y, Color.Yellow);
		y += 30;

		// Stroked Rectangle
		DrawLabel("Stroked Rect", col2X, y, Color.White);
		y += 20;
		mDrawContext.DrawRect(.(col2X, y, 100, 60), Color.Cyan, 3.0f);
		y += 80;

		// Stroked Circle
		DrawLabel("Stroked Circle", col2X, y, Color.White);
		y += 20;
		mDrawContext.DrawCircle(.(col2X + 50, y + 40), 40, Color.Magenta, 3.0f);
		y += 100;

		// Lines
		DrawLabel("Lines", col2X, y, Color.White);
		y += 20;
		mDrawContext.DrawLine(.(col2X, y), .(col2X + 100, y + 50), Color.Red, 2.0f);
		mDrawContext.DrawLine(.(col2X + 100, y), .(col2X, y + 50), Color.Green, 2.0f);
		y += 70;

		// Polyline
		DrawLabel("Polyline", col2X, y, Color.White);
		y += 20;
		Vector2[] polylinePoints = scope .(
			.(col2X, y + 40),
			.(col2X + 30, y),
			.(col2X + 60, y + 40),
			.(col2X + 90, y),
			.(col2X + 120, y + 40)
		);
		mDrawContext.DrawPolyline(polylinePoints, Color.Yellow, 3.0f);
		y += 60;

		// Polygon outline
		DrawLabel("Polygon Outline", col2X, y, Color.White);
		y += 20;
		Vector2[] pentagonPoints = scope .(
			.(col2X + 50, y),
			.(col2X + 100, y + 35),
			.(col2X + 80, y + 90),
			.(col2X + 20, y + 90),
			.(col2X, y + 35)
		);
		mDrawContext.DrawPolygon(pentagonPoints, Color.Lime, 2.0f);
		y += 110;

		// === COLUMN 3: Advanced Features ===
		float col3X = margin * 3 + columnWidth * 2;
		y = margin;

		DrawLabel("ADVANCED FEATURES", col3X, y, Color.Yellow);
		y += 30;

		// Filled Polygon
		DrawLabel("Filled Polygon", col3X, y, Color.White);
		y += 20;
		Vector2[] trianglePoints = scope .(
			.(col3X + 50, y),
			.(col3X + 100, y + 70),
			.(col3X, y + 70)
		);
		mDrawContext.FillPolygon(trianglePoints, Color.Coral);
		y += 90;

		// Linear Gradient
		DrawLabel("Linear Gradient", col3X, y, Color.White);
		y += 20;
		let linearBrush = scope LinearGradientBrush(.(col3X, y), .(col3X + 120, y + 60), Color.Red, Color.Blue);
		mDrawContext.FillRect(.(col3X, y, 120, 60), linearBrush);
		y += 80;

		// Radial Gradient
		DrawLabel("Radial Gradient", col3X, y, Color.White);
		y += 25;
		let radialBrush = scope RadialGradientBrush(.(col3X + 50, y + 50), 50, Color.White, Color.DarkBlue);
		mDrawContext.FillCircle(.(col3X + 50, y + 50), 50, radialBrush);
		y += 115;

		// Transform demo (rotating squares)
		DrawLabel("Transforms (rotating)", col3X, y, Color.White);
		y += 20;
		float centerX = col3X + 60;
		float centerY = y + 60;

		mDrawContext.PushState();
		mDrawContext.Translate(centerX, centerY);
		mDrawContext.Rotate(mAnimationTime);
		mDrawContext.FillRect(.(-30, -30, 60, 60), Color(255, 100, 100, 200));
		mDrawContext.PopState();

		mDrawContext.PushState();
		mDrawContext.Translate(centerX, centerY);
		mDrawContext.Rotate(-mAnimationTime * 0.7f);
		mDrawContext.FillRect(.(-25, -25, 50, 50), Color(100, 255, 100, 200));
		mDrawContext.PopState();

		mDrawContext.PushState();
		mDrawContext.Translate(centerX, centerY);
		mDrawContext.Rotate(mAnimationTime * 1.3f);
		mDrawContext.FillRect(.(-20, -20, 40, 40), Color(100, 100, 255, 200));
		mDrawContext.PopState();
		y += 140;

		// Scale demo
		DrawLabel("Scale Animation", col3X, y, Color.White);
		y += 20;
		float scale = 0.5f + Math.Sin(mAnimationTime * 3) * 0.3f;
		mDrawContext.PushState();
		mDrawContext.Translate(col3X + 50, y + 30);
		mDrawContext.Scale(scale, scale);
		mDrawContext.FillCircle(.(0, 0), 30, Color.Gold);
		mDrawContext.PopState();
		y += 80;

		// Transformed Text demo
		DrawLabel("Transformed Text", col3X, y, Color.White);
		y += 25;

		// Rotating text
		mDrawContext.PushState();
		mDrawContext.Translate(col3X + 60, y + 20);
		mDrawContext.Rotate(mAnimationTime * 0.5f);
		DrawLabel("Spinning!", -30, -10, Color.Cyan);
		mDrawContext.PopState();

		// Scaled text
		mDrawContext.PushState();
		mDrawContext.Translate(col3X + 160, y + 20);
		let textScale = 0.8f + Math.Sin(mAnimationTime * 2) * 0.4f;
		mDrawContext.Scale(textScale, textScale);
		DrawLabel("Pulsing", -25, -10, Color.Magenta);
		mDrawContext.PopState();

		// === Corner test - text at 0,0 to check clipping ===
		// Using characters that reach full ascent height
		DrawLabel("Ålign Ôrigin", 0, 0, Color.Red);

		// === FPS Counter (moved down from window chrome) ===
		DrawLabel(scope $"FPS: {mCurrentFps}", screenWidth - 100, 30, Color.Lime);

		// === Instructions ===
		DrawLabel("Press Escape to exit", screenWidth / 2 - 80, screenHeight - 30, Color.Gray);

		// Convert DrawBatch to render vertices
		ConvertBatchToRenderData();
	}

	/// Draw text using Sedulous.Fonts
	/// Position is top-left of text (y is offset by ascent internally)
	private void DrawLabel(StringView text, float x, float y, Color color)
	{
		// Offset Y by ascent so that y=0 means top of text, not baseline
		let adjustedY = y + mFont.Metrics.Ascent;
		mDrawContext.DrawText(text, mFontAtlas, mFontTextureRef, .(x, adjustedY), color);
	}

	private void ConvertBatchToRenderData()
	{
		let batch = mDrawContext.GetBatch();

		mVertices.Clear();
		mIndices.Clear();

		// Convert DrawVertex to RenderVertex
		for (let v in batch.Vertices)
		{
			mVertices.Add(.(v));
		}

		// Copy indices
		for (let i in batch.Indices)
		{
			mIndices.Add(i);
		}

		// Swap to next buffer set (write to buffer not currently being rendered)
		mBufferIndex = (mBufferIndex + 1) % 2;

		// Upload to GPU using the current buffer set
		if (mVertices.Count > 0)
		{
			let vertexData = Span<uint8>((uint8*)mVertices.Ptr, mVertices.Count * sizeof(RenderVertex));
			Device.Queue.WriteBuffer(mVertexBuffers[mBufferIndex], 0, vertexData);

			let indexData = Span<uint8>((uint8*)mIndices.Ptr, mIndices.Count * sizeof(uint16));
			Device.Queue.WriteBuffer(mIndexBuffers[mBufferIndex], 0, indexData);
		}
	}

	protected override void OnRender(IRenderPassEncoder renderPass)
	{
		if (mIndices.Count == 0)
			return;

		renderPass.SetPipeline(mPipeline);
		renderPass.SetBindGroup(0, mBindGroup);
		renderPass.SetVertexBuffer(0, mVertexBuffers[mBufferIndex], 0);
		renderPass.SetIndexBuffer(mIndexBuffers[mBufferIndex], .UInt16, 0);
		renderPass.DrawIndexed((uint32)mIndices.Count, 1, 0, 0, 0);
	}

	protected override void OnCleanup()
	{
		if (mPipeline != null) delete mPipeline;
		if (mPipelineLayout != null) delete mPipelineLayout;
		if (mBindGroup != null) delete mBindGroup;
		if (mBindGroupLayout != null) delete mBindGroupLayout;
		if (mFragShader != null) delete mFragShader;
		if (mVertShader != null) delete mVertShader;
		if (mSampler != null) delete mSampler;
		if (mAtlasTextureView != null) delete mAtlasTextureView;
		if (mAtlasTexture != null) delete mAtlasTexture;
		if (mUniformBuffer != null) delete mUniformBuffer;
		// Delete double-buffered resources
		for (int i = 0; i < 2; i++)
		{
			if (mIndexBuffers[i] != null) delete mIndexBuffers[i];
			if (mVertexBuffers[i] != null) delete mVertexBuffers[i];
		}

		// Clean up font resources
		if (mFontAtlas != null) delete (Object)mFontAtlas;
		if (mFont != null) delete (Object)mFont;

		TrueTypeFonts.Shutdown();
	}
}

class Program
{
	public static int Main(String[] args)
	{
		let app = scope DrawingSandboxSample();
		return app.Run();
	}
}
