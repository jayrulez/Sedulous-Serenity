namespace DrawingSandbox;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.RHI;
using SampleFramework;
using Sedulous.Drawing;
using Sedulous.Drawing.Fonts;
using Sedulous.Drawing.Renderer;
using Sedulous.Fonts;
using Sedulous.Shaders;

/// Drawing sandbox sample demonstrating Sedulous.Drawing capabilities.
class DrawingSandboxSample : RHISampleApp
{
	// Font service
	private FontService mFontService;

	// Drawing context (created after font service)
	private DrawContext mDrawContext;

	// GPU renderer
	private DrawingRenderer mDrawingRenderer;

	// Shader system
	private NewShaderSystem mShaderSystem;

	// Font size used for labels
	private const float FONT_SIZE = 20;

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

		// Initialize shader system
		mShaderSystem = new NewShaderSystem();
		String shaderPath = scope .();
		GetAssetPath("Render/shaders", shaderPath);
		if (mShaderSystem.Initialize(Device, shaderPath) case .Err)
		{
			Console.WriteLine("Failed to initialize shader system");
			return false;
		}

		// Create draw context with font service (auto-sets WhitePixelUV)
		mDrawContext = new DrawContext(mFontService);

		// Create and initialize the drawing renderer
		mDrawingRenderer = new DrawingRenderer();
		if (mDrawingRenderer.Initialize(Device, SwapChain.Format, MAX_FRAMES_IN_FLIGHT, mShaderSystem) case .Err)
		{
			Console.WriteLine("Failed to initialize DrawingRenderer");
			return false;
		}
		mDrawingRenderer.SetTextureLookup(new (texture) => mFontService.GetTextureView(texture));

		Console.WriteLine("DrawingSandbox initialized with DrawingRenderer");
		return true;
	}

	private bool InitializeFont()
	{
		mFontService = new FontService(Device);

		String fontPath = scope .();
		GetAssetPath("framework/fonts/roboto/Roboto-Regular.ttf", fontPath);

		// Load font with extended Latin for diacritics (Å, Ô, é, etc.)
		FontLoadOptions options = .ExtendedLatin;
		options.PixelHeight = (int32)FONT_SIZE;

		if (mFontService.LoadFont("Roboto", fontPath, options) case .Err)
		{
			Console.WriteLine(scope $"Failed to load font: {fontPath}");
			return false;
		}

		Console.WriteLine("Font loaded successfully");
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
	}

	/// Called before render with the current frame index - safe to write per-frame buffers here
	protected override void OnPrepareFrame(int32 frameIndex)
	{
		// Build drawing commands
		BuildDrawCommands();

		// Prepare batch data for GPU
		let batch = mDrawContext.GetBatch();
		mDrawingRenderer.Prepare(batch, frameIndex);

		// Update projection matrix
		mDrawingRenderer.UpdateProjection(SwapChain.Width, SwapChain.Height, frameIndex);
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
	}

	/// Draw text at top-left position
	private void DrawLabel(StringView text, float x, float y, Color color)
	{
		mDrawContext.DrawText(text, FONT_SIZE, .(x, y), color);
	}

	/// Custom render frame - use this instead of OnRender to get proper frame synchronization
	protected override bool OnRenderFrame(ICommandEncoder encoder, int32 frameIndex)
	{
		// Create render pass targeting swap chain
		let swapTextureView = SwapChain.CurrentTextureView;
		RenderPassColorAttachment[1] colorAttachments = .(.(swapTextureView)
			{
				LoadOp = .Clear,
				StoreOp = .Store,
				ClearValue = .(0.1f, 0.1f, 0.15f, 1.0f)
			});
		RenderPassDescriptor passDesc = .(colorAttachments);

		let renderPass = encoder.BeginRenderPass(&passDesc);
		if (renderPass != null)
		{
			mDrawingRenderer.Render(renderPass, SwapChain.Width, SwapChain.Height, frameIndex);
			renderPass.End();
			delete renderPass;
		}

		return true; // Skip default render pass
	}

	protected override void OnRender(IRenderPassEncoder renderPass)
	{
		// Not used - we use OnRenderFrame for proper frame synchronization
	}

	protected override void OnCleanup()
	{
		// Dispose and clean up drawing renderer
		if (mDrawingRenderer != null)
		{
			mDrawingRenderer.Dispose();
			delete mDrawingRenderer;
		}

		// Clean up draw context
		if (mDrawContext != null) delete mDrawContext;

		// FontService handles font and atlas cleanup
		if (mFontService != null) delete mFontService;

		// Clean up shader system
		if (mShaderSystem != null)
		{
			mShaderSystem.Dispose();
			delete mShaderSystem;
		}
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
