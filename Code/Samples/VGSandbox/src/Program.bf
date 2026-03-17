namespace VGSandbox;

using System;
using Sedulous.Core.Mathematics;
using Sedulous.RHI;
using SampleFramework;
using Sedulous.VG;
using Sedulous.VG.Renderer;
using Sedulous.Shaders;

/// VG Sandbox sample demonstrating Sedulous.VG vector graphics capabilities.
class VGSandboxSample : RHISampleApp
{
	private VGContext mVGContext;
	private VGRenderer mVGRenderer;
	private ShaderSystem mShaderSystem;

	private float mAnimationTime = 0;
	private int mFrameCount = 0;
	private float mFpsTimer = 0;
	private int mCurrentFps = 0;

	public this() : base(.()
		{
			Title = "VG Sandbox",
			Width = 1280,
			Height = 720,
			ClearColor = .(0.08f, 0.08f, 0.12f, 1.0f)
		})
	{
	}

	protected override bool OnInitialize()
	{
		// Initialize shader system
		mShaderSystem = new ShaderSystem();
		String shaderPath = scope .();
		GetAssetPath("Render/shaders", shaderPath);
		if (mShaderSystem.Initialize(Device, scope StringView[](shaderPath)) case .Err)
		{
			Console.WriteLine("Failed to initialize shader system");
			return false;
		}

		// Create VG context
		mVGContext = new VGContext();

		// Create and initialize the VG renderer
		mVGRenderer = new VGRenderer();
		if (mVGRenderer.Initialize(Device, SwapChain.Format, MAX_FRAMES_IN_FLIGHT, mShaderSystem) case .Err)
		{
			Console.WriteLine("Failed to initialize VGRenderer");
			return false;
		}

		Console.WriteLine("VGSandbox initialized");
		return true;
	}

	protected override void OnUpdate(float deltaTime, float totalTime)
	{
		mAnimationTime = totalTime;

		mFrameCount++;
		mFpsTimer += deltaTime;
		if (mFpsTimer >= 1.0f)
		{
			mCurrentFps = mFrameCount;
			mFrameCount = 0;
			mFpsTimer -= 1.0f;
		}
	}

	protected override void OnPrepareFrame(int32 frameIndex)
	{
		BuildVGCommands();

		let batch = mVGContext.GetBatch();
		mVGRenderer.Prepare(batch, frameIndex);
		mVGRenderer.UpdateProjection(SwapChain.Width, SwapChain.Height, frameIndex);
	}

	private void BuildVGCommands()
	{
		mVGContext.Clear();

		float screenWidth = (float)SwapChain.Width;
		float margin = 20;
		float columnWidth = (screenWidth - margin * 4) / 3;

		// === COLUMN 1: Filled Shapes ===
		float col1X = margin;
		float y = margin;

		// Rectangle
		y += 10;
		mVGContext.FillRect(.(col1X, y, 120, 70), Color.Red);
		y += 90;

		// Rounded Rectangle
		mVGContext.FillRoundedRect(.(col1X, y, 120, 70), 15, Color.Green);
		y += 90;

		// Circle
		mVGContext.FillCircle(.(col1X + 60, y + 40), 40, Color.Blue);
		y += 100;

		// Ellipse
		mVGContext.FillEllipse(.(col1X + 60, y + 35), 60, 35, Color.Purple);
		y += 90;

		// Regular Polygon (hexagon)
		mVGContext.FillRegularPolygon(.(col1X + 60, y + 45), 40, 6, Color.Teal);
		y += 110;

		// Star
		mVGContext.FillStar(.(col1X + 60, y + 50), 45, 20, 5, Color.Gold);
		y += 120;

		// === COLUMN 2: Stroked Shapes ===
		float col2X = margin * 2 + columnWidth;
		y = margin + 10;

		// Stroked Rectangle
		mVGContext.StrokeRect(.(col2X, y, 120, 70), Color.Cyan, 3.0f);
		y += 90;

		// Stroked Rounded Rect
		mVGContext.StrokeRoundedRect(.(col2X, y, 120, 70), 15, Color.Magenta, 3.0f);
		y += 90;

		// Stroked Circle
		mVGContext.StrokeCircle(.(col2X + 60, y + 40), 40, Color.Yellow, 3.0f);
		y += 100;

		// Custom path — a triangle
		{
			let builder = scope PathBuilder();
			builder.MoveTo(col2X + 60, y);
			builder.LineTo(col2X + 120, y + 70);
			builder.LineTo(col2X, y + 70);
			builder.Close();
			let path = builder.ToPath();
			defer delete path;

			let style = StrokeStyle() { Width = 3.0f, Join = .Round };
			mVGContext.StrokePath(path, Color.Orange, style);
		}
		y += 90;

		// Dashed circle
		{
			let builder = scope PathBuilder();
			let cx = col2X + 60;
			let cy = y + 45;
			float r = 40;
			ShapeBuilder.BuildCircle(.(cx, cy), r, builder);
			let path = builder.ToPath();
			defer delete path;

			let style = StrokeStyle() { Width = 2.5f, Cap = .Round, DashOffset = mAnimationTime * 50 };
			float[4] dashPattern = .(15, 10, 5, 10);
			mVGContext.StrokePath(path, Color.Lime, style, dashPattern);
		}
		y += 110;

		// Cubic bezier curve
		{
			let builder = scope PathBuilder();
			builder.MoveTo(col2X, y + 60);
			builder.CubicTo(
				col2X + 40, y - 20,
				col2X + 80, y + 100,
				col2X + 120, y + 20
			);
			let path = builder.ToPath();
			defer delete path;

			let style = StrokeStyle() { Width = 3.0f, Cap = .Round };
			mVGContext.StrokePath(path, Color.Coral, style);
		}
		y += 90;

		// === COLUMN 3: Gradients & Transforms ===
		float col3X = margin * 3 + columnWidth * 2;
		y = margin + 10;

		// Linear Gradient
		{
			let builder = scope PathBuilder();
			builder.MoveTo(col3X, y);
			builder.LineTo(col3X + 120, y);
			builder.LineTo(col3X + 120, y + 70);
			builder.LineTo(col3X, y + 70);
			builder.Close();
			let path = builder.ToPath();
			defer delete path;

			let fill = scope VGLinearGradientFill(.(col3X, y), .(col3X + 120, y + 70));
			fill.AddStop(0.0f, Color.Red);
			fill.AddStop(0.5f, Color.Yellow);
			fill.AddStop(1.0f, Color.Blue);
			mVGContext.FillPath(path, fill);
		}
		y += 90;

		// Radial Gradient
		{
			let builder = scope PathBuilder();
			ShapeBuilder.BuildCircle(.(col3X + 60, y + 45), 50, builder);
			let path = builder.ToPath();
			defer delete path;

			let fill = scope VGRadialGradientFill(.(col3X + 60, y + 45), 50);
			fill.AddStop(0.0f, Color.White);
			fill.AddStop(0.5f, Color.Cyan);
			fill.AddStop(1.0f, Color.DarkBlue);
			mVGContext.FillPath(path, fill);
		}
		y += 115;

		// Conic Gradient
		{
			let builder = scope PathBuilder();
			ShapeBuilder.BuildCircle(.(col3X + 60, y + 45), 45, builder);
			let path = builder.ToPath();
			defer delete path;

			let fill = scope VGConicGradientFill(.(col3X + 60, y + 45));
			fill.AddStop(0.0f, Color.Red);
			fill.AddStop(0.167f, Color.Yellow);
			fill.AddStop(0.333f, Color.Green);
			fill.AddStop(0.5f, Color.Cyan);
			fill.AddStop(0.667f, Color.Blue);
			fill.AddStop(0.833f, Color.Magenta);
			fill.AddStop(1.0f, Color.Red);
			mVGContext.FillPath(path, fill);
		}
		y += 115;

		// Transform — rotating squares
		float centerX = col3X + 60;
		float centerY = y + 60;

		mVGContext.PushState();
		mVGContext.Translate(centerX, centerY);
		mVGContext.Rotate(mAnimationTime);
		mVGContext.FillRect(.(-35, -35, 70, 70), Color(255, 100, 100, 180));
		mVGContext.PopState();

		mVGContext.PushState();
		mVGContext.Translate(centerX, centerY);
		mVGContext.Rotate(-mAnimationTime * 0.7f);
		mVGContext.FillRect(.(-28, -28, 56, 56), Color(100, 255, 100, 180));
		mVGContext.PopState();

		mVGContext.PushState();
		mVGContext.Translate(centerX, centerY);
		mVGContext.Rotate(mAnimationTime * 1.3f);
		mVGContext.FillRect(.(-22, -22, 44, 44), Color(100, 100, 255, 180));
		mVGContext.PopState();
		y += 140;

		// Scale animation
		float scale = 0.5f + Math.Sin(mAnimationTime * 3) * 0.3f;
		mVGContext.PushState();
		mVGContext.Translate(col3X + 60, y + 40);
		mVGContext.Scale(scale, scale);
		mVGContext.FillStar(.(0, 0), 40, 18, 6, Color.Gold);
		mVGContext.PopState();
	}

	protected override bool OnRenderFrame(ICommandEncoder encoder, int32 frameIndex)
	{
		let swapTextureView = SwapChain.CurrentTextureView;
		RenderPassColorAttachment[1] colorAttachments = .(.(swapTextureView)
			{
				LoadOp = .Clear,
				StoreOp = .Store,
				ClearValue = .(0.08f, 0.08f, 0.12f, 1.0f)
			});
		RenderPassDescriptor passDesc = .(colorAttachments);

		let renderPass = encoder.BeginRenderPass(&passDesc);
		if (renderPass != null)
		{
			mVGRenderer.Render(renderPass, SwapChain.Width, SwapChain.Height, frameIndex);
			renderPass.End();
			delete renderPass;
		}

		return true;
	}

	protected override void OnRender(IRenderPassEncoder renderPass)
	{
		// Not used — we use OnRenderFrame
	}

	protected override void OnCleanup()
	{
		if (mVGRenderer != null)
		{
			mVGRenderer.Dispose();
			delete mVGRenderer;
		}

		if (mVGContext != null) delete mVGContext;

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
		let app = scope VGSandboxSample();
		return app.Run();
	}
}
