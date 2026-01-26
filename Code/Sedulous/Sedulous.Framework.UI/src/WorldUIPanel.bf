namespace Sedulous.Framework.UI;

using System;
using Sedulous.Framework.Scenes;
using Sedulous.UI;
using Sedulous.UI.Shell;
using Sedulous.Drawing.Fonts;
using Sedulous.Drawing.Renderer;
using Sedulous.Drawing;
using Sedulous.RHI;
using Sedulous.Render;
using Sedulous.Shaders;
using Sedulous.Mathematics;

/// A world-space UI panel rendered to a texture and displayed as a sprite in 3D.
/// Each panel owns its own UIContext, DrawingRenderer, and render texture.
public class WorldUIPanel
{
	// UI rendering
	private UIContext mUIContext ~ delete _;
	private DrawContext mDrawContext ~ delete _;
	private DrawingRenderer mDrawingRenderer;
	private ITheme mTheme ~ delete _;
	private FontService mFontService; // shared, not owned

	// GPU render texture
	private Sedulous.RHI.ITexture mTexture ~ delete _;
	private ITextureView mTextureView ~ delete _;

	// World display
	private SpriteProxyHandle mSpriteHandle = .Invalid;
	private EntityId mEntity;
	private Vector3 mWorldPosition;
	private Quaternion mWorldRotation = .Identity;
	private float mPanelWidth;
	private float mPanelHeight;
	private uint32 mPixelWidth;
	private uint32 mPixelHeight;

	// State
	private bool mIsDirty = true;
	private bool mIsInteractive = true;
	private String mResourceName ~ delete _;
	private String mPassName ~ delete _;

	private static int32 sNextPanelId = 0;

	/// The panel's UIContext for building UI element trees.
	public UIContext UIContext => mUIContext;

	/// Whether this panel needs re-rendering.
	public bool IsDirty
	{
		get => mIsDirty;
		set => mIsDirty = value;
	}

	/// Whether this panel receives raycasted mouse input.
	public bool IsInteractive
	{
		get => mIsInteractive;
		set => mIsInteractive = value;
	}

	/// The entity this panel is attached to.
	public EntityId Entity
	{
		get => mEntity;
		set => mEntity = value;
	}

	/// The sprite handle for this panel in the RenderWorld.
	public SpriteProxyHandle SpriteHandle
	{
		get => mSpriteHandle;
		set => mSpriteHandle = value;
	}

	/// World-space position of the panel center.
	public Vector3 WorldPosition => mWorldPosition;

	/// World-space rotation of the panel.
	public Quaternion WorldRotation => mWorldRotation;

	/// Width of the panel in world units.
	public float PanelWidth => mPanelWidth;

	/// Height of the panel in world units.
	public float PanelHeight => mPanelHeight;

	/// Width of the render texture in pixels.
	public uint32 PixelWidth => mPixelWidth;

	/// Height of the render texture in pixels.
	public uint32 PixelHeight => mPixelHeight;

	/// The render texture.
	public Sedulous.RHI.ITexture Texture => mTexture;

	/// The render texture view (for sprite display and render graph import).
	public ITextureView TextureView => mTextureView;

	/// The DrawingRenderer for this panel.
	public DrawingRenderer Renderer => mDrawingRenderer;

	/// The DrawContext for building geometry.
	public DrawContext PanelDrawContext => mDrawContext;

	/// Unique resource name for render graph import.
	public StringView ResourceName => mResourceName;

	/// Unique pass name for the render graph pass.
	public StringView PassName => mPassName;

	/// Creates a new world-space UI panel.
	/// - device: GPU device for resource creation
	/// - fontService: Shared font service (not owned)
	/// - pixelWidth/Height: Render texture resolution
	/// - panelWidth/Height: World-space size in units
	/// - frameCount: Number of in-flight frames for triple-buffering
	/// - shaderSystem: Shader system for loading drawing shaders
	public this(IDevice device, FontService fontService, uint32 pixelWidth, uint32 pixelHeight, float panelWidth, float panelHeight, int32 frameCount, NewShaderSystem shaderSystem)
	{
		mFontService = fontService;
		mPixelWidth = pixelWidth;
		mPixelHeight = pixelHeight;
		mPanelWidth = panelWidth;
		mPanelHeight = panelHeight;

		// Generate unique names
		let panelId = sNextPanelId++;
		mResourceName = new String();
		mResourceName.AppendF("WorldUI_{}", panelId);
		mPassName = new String();
		mPassName.AppendF("WorldUIPass_{}", panelId);

		// Create UI context
		mUIContext = new UIContext();
		mUIContext.SetViewportSize((float)pixelWidth, (float)pixelHeight);
		mUIContext.RegisterService<IFontService>(fontService);
		mTheme = new DefaultTheme();
		mUIContext.RegisterService<ITheme>(mTheme);

		// Create draw context
		mDrawContext = new DrawContext(fontService);

		// Create renderer
		mDrawingRenderer = new DrawingRenderer();
		mDrawingRenderer.Initialize(device, .RGBA8Unorm, frameCount, shaderSystem);
		mFontService = fontService;
		mDrawingRenderer.SetTextureLookup(new (texture) => mFontService.GetTextureView(texture));

		// Create render texture
		TextureDescriptor texDesc = TextureDescriptor.Texture2D(
			pixelWidth, pixelHeight, .RGBA8Unorm,
			.Sampled | .RenderTarget
		);
		if (device.CreateTexture(&texDesc) case .Ok(let tex))
			mTexture = tex;

		if (mTexture != null)
		{
			TextureViewDescriptor viewDesc = .() { Format = .RGBA8Unorm };
			if (device.CreateTextureView(mTexture, &viewDesc) case .Ok(let view))
				mTextureView = view;
		}
	}

	/// Mark the panel as needing re-rendering.
	public void MarkDirty()
	{
		mIsDirty = true;
	}

	/// Update the world-space transform from entity data.
	public void UpdateTransform(Vector3 position, Quaternion rotation)
	{
		mWorldPosition = position;
		mWorldRotation = rotation;
	}

	/// Dispose GPU resources owned by this panel.
	public void Dispose()
	{
		if (mDrawingRenderer != null)
		{
			mDrawingRenderer.Dispose();
			delete mDrawingRenderer;
			mDrawingRenderer = null;
		}
	}
}
