namespace Sedulous.AppFramework;

using System;
using Sedulous.Mathematics;
using Sedulous.Drawing;
using Sedulous.Drawing.Renderer;
using Sedulous.RHI;
using Sedulous.GUI;

/// Delegate for rendering 3D content to a viewport.
/// Called each frame when the viewport needs to render.
/// The encoder is ready - create your render pass targeting the provided views.
public delegate void ViewportRenderDelegate(ViewportControl viewport, ICommandEncoder encoder);

/// A reference to an externally-managed GPU texture for use in 2D drawing.
/// This allows render targets to be displayed as images in the GUI.
public class ViewportImageRef : IImageData
{
	private uint32 mWidth;
	private uint32 mHeight;

	public uint32 Width => mWidth;
	public uint32 Height => mHeight;
	public PixelFormat Format => .RGBA8;
	public Span<uint8> PixelData => .();  // No CPU data - GPU only

	public this(uint32 width, uint32 height)
	{
		mWidth = width;
		mHeight = height;
	}

	public void Resize(uint32 width, uint32 height)
	{
		mWidth = width;
		mHeight = height;
	}
}

/// A GUI control that displays 3D rendered content.
/// Provides a render target that can be drawn to and displays the result.
/// Use the OnRender event to draw 3D content to the viewport.
public class ViewportControl : Control
{
	private IDevice mDevice;
	private DrawingRenderer mDrawingRenderer;
	private ViewportImageRef mImageRef ~ delete _;

	// Render target resources
	private Sedulous.RHI.ITexture mColorTexture ~ delete _;
	private ITextureView mColorTextureView ~ delete _;
	private Sedulous.RHI.ITexture mDepthTexture ~ delete _;
	private ITextureView mDepthTextureView ~ delete _;

	// Current size
	private uint32 mTextureWidth = 0;
	private uint32 mTextureHeight = 0;

	// Rendering state
	private bool mNeedsRender = true;
	private bool mIsRegistered = false;
	private Color mClearColor = Color(51, 51, 64, 255);  // Dark blue-gray

	/// Event fired when the viewport needs to render 3D content.
	/// The ViewportControl and command encoder are provided.
	/// Use ColorTargetView and DepthTargetView to create your render pass.
	public Event<ViewportRenderDelegate> OnRender ~ _.Dispose();

	/// The clear color for the viewport background.
	public Color ClearColor
	{
		get => mClearColor;
		set => mClearColor = value;
	}

	/// The render target color texture view. Use this in your render pass.
	public ITextureView ColorTargetView => mColorTextureView;

	/// The render target color texture. Use for texture barriers.
	public Sedulous.RHI.ITexture ColorTexture => mColorTexture;

	/// The depth texture. Use for render graph imports.
	public Sedulous.RHI.ITexture DepthTexture => mDepthTexture;

	/// The depth texture view. Use this in your render pass.
	public ITextureView DepthTargetView => mDepthTextureView;

	/// Current render target width in pixels.
	public uint32 RenderWidth => mTextureWidth;

	/// Current render target height in pixels.
	public uint32 RenderHeight => mTextureHeight;

	/// Whether the viewport has valid render targets.
	public bool IsReady => mColorTextureView != null && mDepthTextureView != null;

	/// Creates a new ViewportControl.
	/// Must call Initialize() with device and renderer before use.
	public this()
	{
		IsFocusable = true;
		IsTabStop = true;
		mImageRef = new ViewportImageRef(1, 1);
	}

	/// Initialize the viewport with a rendering device and DrawingRenderer.
	/// The DrawingRenderer is needed to register the external texture for display.
	public Result<void> Initialize(IDevice device, DrawingRenderer drawingRenderer)
	{
		if (device == null || drawingRenderer == null)
			return .Err;

		mDevice = device;
		mDrawingRenderer = drawingRenderer;
		return .Ok;
	}

	/// Mark the viewport as needing a render update.
	public void Invalidate()
	{
		mNeedsRender = true;
	}

	/// Render the viewport content. Call this from your render loop.
	/// This fires the OnRender event to draw 3D content.
	public void RenderContent(ICommandEncoder encoder)
	{
		if (mDevice == null || mColorTextureView == null || !mIsRegistered)
			return;

		// Fire render event for 3D content
		OnRender(this, encoder);
		mNeedsRender = false;
	}

	protected override StringView ControlTypeName => "Viewport";

	protected override DesiredSize MeasureOverride(SizeConstraints constraints)
	{
		// Viewport takes all available space by default
		float width = constraints.MaxWidth != SizeConstraints.Infinity ? constraints.MaxWidth : 256;
		float height = constraints.MaxHeight != SizeConstraints.Infinity ? constraints.MaxHeight : 256;
		return .(width, height);
	}

	protected override void ArrangeOverride(RectangleF finalRect)
	{
		base.ArrangeOverride(finalRect);

		// Resize render target if needed
		let newWidth = (uint32)Math.Max(1, finalRect.Width);
		let newHeight = (uint32)Math.Max(1, finalRect.Height);

		if (newWidth != mTextureWidth || newHeight != mTextureHeight)
		{
			ResizeRenderTarget(newWidth, newHeight);
		}
	}

	private void ResizeRenderTarget(uint32 width, uint32 height)
	{
		if (mDevice == null)
			return;

		// Wait for GPU to finish using old resources before destroying them
		if (mColorTexture != null || mDepthTexture != null)
			mDevice.WaitIdle();

		// Unregister old texture first
		if (mIsRegistered && mDrawingRenderer != null)
		{
			mDrawingRenderer.UnregisterExternalTexture(mImageRef);
			mIsRegistered = false;
		}

		// Clean up existing resources
		if (mDepthTextureView != null) { delete mDepthTextureView; mDepthTextureView = null; }
		if (mDepthTexture != null) { delete mDepthTexture; mDepthTexture = null; }
		if (mColorTextureView != null) { delete mColorTextureView; mColorTextureView = null; }
		if (mColorTexture != null) { delete mColorTexture; mColorTexture = null; }

		mTextureWidth = width;
		mTextureHeight = height;
		mImageRef.Resize(width, height);

		// Create color render target
		TextureDescriptor colorDesc = TextureDescriptor.Texture2D(
			width, height, .RGBA8Unorm, .RenderTarget | .Sampled
		);
		if (mDevice.CreateTexture(&colorDesc) case .Ok(let colorTex))
			mColorTexture = colorTex;
		else
			return;

		TextureViewDescriptor colorViewDesc = .() { Format = .RGBA8Unorm };
		if (mDevice.CreateTextureView(mColorTexture, &colorViewDesc) case .Ok(let colorView))
			mColorTextureView = colorView;
		else
			return;

		// Create depth buffer - use Depth24PlusStencil8 to match RenderSystem defaults
		TextureDescriptor depthDesc = TextureDescriptor.Texture2D(
			width, height, .Depth24PlusStencil8, .DepthStencil
		);
		if (mDevice.CreateTexture(&depthDesc) case .Ok(let depthTex))
			mDepthTexture = depthTex;
		else
			return;

		TextureViewDescriptor depthViewDesc = .() { Format = .Depth24PlusStencil8 };
		if (mDevice.CreateTextureView(mDepthTexture, &depthViewDesc) case .Ok(let depthView))
			mDepthTextureView = depthView;

		// Register with DrawingRenderer for display
		if (mDrawingRenderer != null && mColorTextureView != null)
		{
			mDrawingRenderer.RegisterExternalTexture(mImageRef, mColorTextureView);
			mIsRegistered = true;
		}

		mNeedsRender = true;
	}

	protected override void RenderOverride(DrawContext ctx)
	{
		let bounds = ArrangedBounds;

		// Draw background/border
		RenderBackground(ctx);

		// Draw the render target as an image
		if (mImageRef != null && mTextureWidth > 0 && mTextureHeight > 0 && mIsRegistered)
		{
			// The actual image comes from the registered external texture
			ctx.DrawImage(mImageRef, bounds, .(0, 0, mTextureWidth, mTextureHeight), .White);
		}
	}

	// Input handling - derived classes or event handlers can use these for camera control

	protected override void OnMouseDown(MouseButtonEventArgs e)
	{
		base.OnMouseDown(e);
		// Capture focus for keyboard input
		if (IsFocusable)
			Context?.FocusManager?.SetFocus(this);
	}
}
