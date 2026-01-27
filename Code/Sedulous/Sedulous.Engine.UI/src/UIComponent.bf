namespace Sedulous.Engine.UI;

using System;
using System.Collections;
using Sedulous.Engine.Core;
using Sedulous.Mathematics;
using Sedulous.Serialization;
using Sedulous.Drawing;
using Sedulous.UI;
using Sedulous.Drawing.Renderer;
using Sedulous.Shaders;

// Explicit RHI imports to avoid ambiguity with Drawing.ITexture
using Sedulous.RHI;
using Sedulous.Drawing.Fonts;
typealias RHITexture = Sedulous.RHI.ITexture;
typealias RHITextureView = Sedulous.RHI.ITextureView;

/// Determines how world-space UI is oriented.
enum WorldUIOrientation
{
	/// UI panel always faces the camera (billboard).
	Billboard,
	/// UI panel uses the entity's rotation.
	Fixed
}

/// Entity component that renders a UI panel in world space.
/// Each UIComponent owns its own UIContext for an isolated UI tree.
/// The UI is rendered to a texture which is displayed as a sprite/quad.
class UIComponent : IEntityComponent
{
	private Entity mEntity;
	private UISceneComponent mUIScene;

	// UI system (each entity has its own UI tree)
	private UIContext mUIContext ~ delete _;
	private DrawContext mDrawContext ~ delete _;

	// GPU rendering
	private DrawingRenderer mDrawingRenderer;  // Borrowed from UISceneComponent or created
	private bool mOwnsRenderer = false;

	// Render-to-texture resources
	private IDevice mDevice;
	private RHITexture mRenderTexture ~ delete _;
	private RHITextureView mRenderTextureView ~ delete _;
	private bool mTextureCreated = false;

	// Properties
	/// How the UI panel is oriented in 3D space.
	public WorldUIOrientation Orientation = .Billboard;

	/// Size of the UI panel in world units.
	public Vector2 WorldSize = .(1.0f, 1.0f);

	/// Resolution of the render texture in pixels.
	public Vector2 TextureSize = .(512, 512);

	/// Whether the UI is visible.
	public bool Visible = true;

	/// Whether the UI responds to raycasted input.
	public bool Interactive = true;

	// ==================== Properties ====================

	/// Gets the UI context for this component.
	public UIContext UIContext => mUIContext;

	/// Gets the root element of the UI tree.
	public UIElement RootElement
	{
		get => mUIContext?.RootElement;
		set
		{
			if (mUIContext != null)
				mUIContext.RootElement = value;
		}
	}

	/// Gets the render texture view for this UI.
	/// Use this to display the UI as a texture on a sprite/mesh.
	public RHITextureView RenderTextureView => mRenderTextureView;

	/// Gets the underlying render texture (for texture barriers).
	public RHITexture RenderTexture => mRenderTexture;

	/// Gets the entity this component is attached to.
	public Entity Entity => mEntity;

	/// Gets whether the render texture has been created.
	public bool IsRenderingInitialized => mTextureCreated;

	/// Sets the white pixel UV coordinates for solid color rendering.
	public void SetWhitePixelUV(Vector2 uv)
	{
		if (mDrawContext != null)
			mDrawContext.WhitePixelUV = uv;
	}

	// ==================== Constructor ====================

	public this()
	{
	}

	/// Creates a UIComponent with specified texture resolution.
	public this(int32 width, int32 height)
	{
		TextureSize = .((float)width, (float)height);
	}

	public ~this()
	{
		// Clean up DrawingRenderer if we own it (conditional ownership can't use ~ delete _)
		if (mOwnsRenderer && mDrawingRenderer != null)
		{
			mDrawingRenderer.Dispose();
			delete mDrawingRenderer;
			mDrawingRenderer = null;
		}
	}

	// ==================== IEntityComponent Implementation ====================

	public void OnAttach(Entity entity)
	{
		mEntity = entity;

		// Create UI context
		mUIContext = new UIContext();

		// DrawContext is created in InitializeRendering when font service is available

		// Get scene component for shared resources and register
		if (entity.Scene != null)
		{
			mUIScene = entity.Scene.GetSceneComponent<UISceneComponent>();
			mUIScene?.RegisterWorldUI(this);
		}
	}

	public void OnDetach()
	{
		CleanupRendering();

		// Unregister from scene component (if not already cleared by UISceneComponent.OnDetach)
		mUIScene?.UnregisterWorldUI(this);
		mUIScene = null;
		mEntity = null;
	}

	/// Called by UISceneComponent when it's being detached.
	/// Clears the reference to prevent accessing deleted memory.
	public void ClearUISceneReference()
	{
		mUIScene = null;
	}

	public void OnUpdate(float deltaTime)
	{
		if (!Visible || mUIContext == null)
			return;

		// Get total time from system if available
		double totalTime = 0;
		if (mUIContext.SystemServices != null)
			totalTime = mUIContext.SystemServices.CurrentTime;

		// Update UI context (layout, animations, etc.)
		mUIContext.Update(deltaTime, totalTime);
	}

	// ==================== ISerializable Implementation ====================

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer serializer)
	{
		var version = SerializationVersion;
		var result = serializer.Version(ref version);
		if (result != .Ok)
			return result;

		// Orientation
		int32 orientationVal = (int32)Orientation;
		result = serializer.Int32("orientation", ref orientationVal);
		if (result != .Ok)
			return result;
		if (serializer.IsReading)
			Orientation = (WorldUIOrientation)orientationVal;

		// World size
		float[2] worldSizeArr = .(WorldSize.X, WorldSize.Y);
		result = serializer.FixedFloatArray("worldSize", &worldSizeArr, 2);
		if (result != .Ok)
			return result;
		if (serializer.IsReading)
			WorldSize = .(worldSizeArr[0], worldSizeArr[1]);

		// Texture size
		float[2] texSizeArr = .(TextureSize.X, TextureSize.Y);
		result = serializer.FixedFloatArray("textureSize", &texSizeArr, 2);
		if (result != .Ok)
			return result;
		if (serializer.IsReading)
			TextureSize = .(texSizeArr[0], texSizeArr[1]);

		// Flags
		int32 flags = 0;
		if (Visible) flags |= 1;
		if (Interactive) flags |= 2;
		result = serializer.Int32("flags", ref flags);
		if (result != .Ok)
			return result;
		if (serializer.IsReading)
		{
			Visible = (flags & 1) != 0;
			Interactive = (flags & 2) != 0;
		}

		return .Ok;
	}

	// ==================== Rendering Initialization ====================

	/// Initializes render-to-texture resources.
	/// Call this after the device is available.
	public Result<void> InitializeRendering(IDevice device, TextureFormat format, int32 frameCount, NewShaderSystem shaderSystem)
	{
		if (mTextureCreated)
			return .Ok;

		mDevice = device;

		// Create render target texture
		let width = (uint32)TextureSize.X;
		let height = (uint32)TextureSize.Y;

		TextureDescriptor texDesc = .()
		{
			Dimension = .Texture2D,
			Width = width,
			Height = height,
			Depth = 1,
			ArrayLayerCount = 1,
			MipLevelCount = 1,
			SampleCount = 1,
			Format = format,
			Usage = .RenderTarget | .Sampled,
			Label = "UIComponent_RenderTexture"
		};

		if (device.CreateTexture(&texDesc) case .Ok(let tex))
			mRenderTexture = tex;
		else
			return .Err;

		// Create texture view
		TextureViewDescriptor viewDesc = .()
		{
			Dimension = .Texture2D,
			Format = format,
			BaseMipLevel = 0,
			MipLevelCount = 1,
			BaseArrayLayer = 0,
			ArrayLayerCount = 1
		};

		if (device.CreateTextureView(mRenderTexture, &viewDesc) case .Ok(let view))
			mRenderTextureView = view;
		else
		{
			delete mRenderTexture;
			mRenderTexture = null;
			return .Err;
		}

		// Create our own DrawingRenderer for off-screen rendering
		mDrawingRenderer = new DrawingRenderer();
		mOwnsRenderer = true;
		if (mDrawingRenderer.Initialize(device, format, frameCount, shaderSystem) case .Err)
		{
			delete mDrawingRenderer;
			mDrawingRenderer = null;
			delete mRenderTextureView;
			mRenderTextureView = null;
			delete mRenderTexture;
			mRenderTexture = null;
			return .Err;
		}

		// Get font service for texture lookup and DrawContext creation
		let fontService = mEntity.Scene.Context.GetService<UIService>().FontService;
		if (fontService == null)
		{
			delete mDrawingRenderer;
			mDrawingRenderer = null;
			delete mRenderTextureView;
			mRenderTextureView = null;
			delete mRenderTexture;
			mRenderTexture = null;
			return .Err;
		}

		// Create draw context with font service (sets WhitePixelUV automatically)
		mDrawContext = new DrawContext(fontService);

		// Set up texture lookup for rendering
		mDrawingRenderer.SetTextureLookup(new [=](texture) => ((FontService)fontService).GetTextureView(texture));

		// Set viewport size on UI context
		mUIContext?.SetViewportSize(TextureSize.X, TextureSize.Y);

		mTextureCreated = true;
		return .Ok;
	}

	private void CleanupRendering()
	{
		if (mOwnsRenderer && mDrawingRenderer != null)
		{
			mDrawingRenderer.Dispose();
			delete mDrawingRenderer;
		}
		mDrawingRenderer = null;
		mOwnsRenderer = false;

		if (mRenderTextureView != null)
		{
			delete mRenderTextureView;
			mRenderTextureView = null;
		}

		if (mRenderTexture != null)
		{
			delete mRenderTexture;
			mRenderTexture = null;
		}

		mTextureCreated = false;
	}

	// ==================== Frame Rendering ====================

	/// Prepares UI geometry for GPU rendering.
	/// Call this during the PrepareGPU phase.
	public void PrepareGPU(int32 frameIndex)
	{
		if (!mTextureCreated || !Visible || mUIContext == null || mDrawingRenderer == null)
			return;

		// Clear the draw context
		mDrawContext.Clear();

		// Render UI to draw context
		mUIContext.Render(mDrawContext);

		// Get the batch and prepare for GPU
		let batch = mDrawContext.GetBatch();

		// Upload to GPU buffers
		mDrawingRenderer.Prepare(batch, frameIndex);

		// Update projection matrix
		mDrawingRenderer.UpdateProjection((uint32)TextureSize.X, (uint32)TextureSize.Y, frameIndex);
	}

	/// Renders the UI to its render texture.
	/// Call this before the main render pass to render off-screen.
	/// Note: When using RenderGraph, use RenderWithinPass instead.
	public void RenderToTexture(ICommandEncoder encoder, int32 frameIndex)
	{
		if (!mTextureCreated || !Visible || mDrawingRenderer == null || mRenderTextureView == null)
			return;

		// Create a render pass targeting our texture
		RenderPassColorAttachment colorAttachment = .()
		{
			View = mRenderTextureView,
			LoadOp = .Clear,
			StoreOp = .Store,
			ClearValue = .(0, 0, 0, 0)  // Transparent background
		};

		RenderPassColorAttachment[1] colorAttachments = .(colorAttachment);

		RenderPassDescriptor passDesc = .()
		{
			ColorAttachments = colorAttachments,
			DepthStencilAttachment = null
		};

		let renderPass = encoder.BeginRenderPass(&passDesc);
		if (renderPass == null)
			return;

		defer { renderPass.End(); delete renderPass; }

		let width = (uint32)TextureSize.X;
		let height = (uint32)TextureSize.Y;

		mDrawingRenderer.Render(renderPass, width, height, frameIndex);
	}

	/// Renders the UI within an existing render pass.
	/// Use this when integrating with RenderGraph - the graph handles the render pass.
	public void RenderWithinPass(IRenderPassEncoder renderPass, int32 frameIndex)
	{
		if (!mTextureCreated || !Visible || mDrawingRenderer == null)
			return;

		let width = (uint32)TextureSize.X;
		let height = (uint32)TextureSize.Y;

		mDrawingRenderer.Render(renderPass, width, height, frameIndex);
	}

	// ==================== Raycast Input ====================

	/// Performs a ray-plane intersection to check if the given ray hits this UI panel.
	/// Returns true if hit, and outputs the local UI coordinates.
	public bool Raycast(Ray ray, out Vector2 localHit)
	{
		localHit = .Zero;

		if (!Interactive || !Visible || mEntity == null)
			return false;

		// Get the entity's world transform
		let worldPos = mEntity.Transform.WorldPosition;

		// For billboard mode, we need to compute the plane facing the camera
		// For fixed mode, use the entity's forward direction
		Vector3 planeNormal;
		Vector3 planeRight;
		Vector3 planeUp;

		if (Orientation == .Billboard)
		{
			// Billboard: plane faces the ray position (camera)
			planeNormal = Vector3.Normalize(ray.Position - worldPos);
			planeRight = Vector3.Normalize(Vector3.Cross(Vector3.UnitY, planeNormal));
			planeUp = Vector3.Cross(planeNormal, planeRight);
		}
		else
		{
			// Fixed: use entity's orientation
			planeNormal = mEntity.Transform.Forward;
			planeRight = mEntity.Transform.Right;
			planeUp = mEntity.Transform.Up;
		}

		// Ray-plane intersection
		let denom = Vector3.Dot(planeNormal, ray.Direction);
		if (Math.Abs(denom) < 0.0001f)
			return false;  // Ray parallel to plane

		let t = Vector3.Dot(worldPos - ray.Position, planeNormal) / denom;
		if (t < 0)
			return false;  // Intersection behind ray position

		let hitPoint = ray.Position + ray.Direction * t;

		// Convert hit point to local coordinates on the plane
		let localOffset = hitPoint - worldPos;
		let localX = Vector3.Dot(localOffset, planeRight);
		let localY = Vector3.Dot(localOffset, planeUp);

		// Check if within bounds
		let halfWidth = WorldSize.X * 0.5f;
		let halfHeight = WorldSize.Y * 0.5f;

		if (localX < -halfWidth || localX > halfWidth ||
			localY < -halfHeight || localY > halfHeight)
			return false;

		// Convert to UI coordinates (0,0 at top-left, increasing down-right)
		localHit.X = (localX + halfWidth) / WorldSize.X * TextureSize.X;
		localHit.Y = (halfHeight - localY) / WorldSize.Y * TextureSize.Y;  // Flip Y

		return true;
	}

	/// Handles a raycast hit with optional mouse button.
	/// Call this when Raycast returns true.
	public void OnRaycastHit(Vector2 localPos, MouseButton? button = null, bool pressed = false)
	{
		if (mUIContext == null)
			return;

		// Route as mouse move
		mUIContext.InputManager?.ProcessMouseMove(localPos.X, localPos.Y);

		// If button specified, route as click
		if (button.HasValue)
		{
			if (pressed)
				mUIContext.InputManager?.ProcessMouseDown(button.Value, localPos.X, localPos.Y);
			else
				mUIContext.InputManager?.ProcessMouseUp(button.Value, localPos.X, localPos.Y);
		}
	}
}
