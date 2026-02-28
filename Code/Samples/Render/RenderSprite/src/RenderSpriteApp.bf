namespace RenderSprite;

using System;
using System.Collections;
using Sedulous.Foundation.Mathematics;
using Sedulous.RHI;
using Sedulous.Shell;
using Sedulous.Engine.Runtime;
using Sedulous.Render;
using Sedulous.Geometry;

/// Sprite sample demonstrating billboard sprite rendering
/// with animated positions and colors via the Sedulous.Render pipeline.
class RenderSpriteApp : Application
{
	// Render system
	private RenderSystem mRenderSystem ~ delete _;
	private RenderWorld mWorld ~ delete _;
	private RenderView mView ~ delete _;

	// Render features
	private DepthPrepassFeature mDepthFeature;
	private ForwardOpaqueFeature mForwardFeature;
	private SpriteFeature mSpriteFeature;
	private SkyFeature mSkyFeature;
	private FinalOutputFeature mFinalOutputFeature;

	// Sprites
	private List<SpriteProxyHandle> mOuterSprites = new .() ~ delete _;
	private List<SpriteProxyHandle> mInnerSprites = new .() ~ delete _;
	private SpriteProxyHandle mCenterSprite;

	// Camera
	private Vector3 mCameraPosition = .(0, 2, 8);
	private float mYaw = Math.PI_f;
	private float mPitch = 0;
	private Vector3 mCameraForward;
	private bool mMouseCaptured = false;
	private const float MoveSpeed = 5.0f;
	private const float LookSpeed = 0.003f;

	public this(IShell shell, IDevice device, IBackend backend)
		: base(shell, device, backend)
	{
	}

	protected override void OnInitialize(Sedulous.Engine.Core.Context context)
	{
		mRenderSystem = new RenderSystem();
		if (mRenderSystem.Initialize(mDevice, scope StringView[](scope $"{AssetDirectory}/Render/Shaders"), null, .BGRA8UnormSrgb, .Depth24PlusStencil8) case .Err)
		{
			Console.WriteLine("ERROR: Failed to initialize RenderSystem");
			return;
		}

		mWorld = mRenderSystem.CreateWorld();
		mRenderSystem.SetActiveWorld(mWorld);

		mView = new RenderView();
		mView.Width = mSwapChain.Width;
		mView.Height = mSwapChain.Height;
		mView.FieldOfView = Math.PI_f / 4.0f;
		mView.NearPlane = 0.1f;
		mView.FarPlane = 100.0f;

		RegisterFeatures();
		CreateSprites();

		mWorld.AmbientColor = .(0.05f, 0.05f, 0.08f);
		mWorld.AmbientIntensity = 0.5f;
		mWorld.Exposure = 1.0f;

		Console.WriteLine("Render Sprite initialized");
		Console.WriteLine("  {} sprites total", mOuterSprites.Count + mInnerSprites.Count + 1);
		Console.WriteLine("  WASD/QE: move, Right-click: look, Tab: capture");
		Console.WriteLine("  ESC: exit");
	}

	private void RegisterFeatures()
	{
		mDepthFeature = new DepthPrepassFeature();
		if (mRenderSystem.RegisterFeature(mDepthFeature) case .Err)
			Console.WriteLine("Warning: Failed to register DepthPrepassFeature");

		mForwardFeature = new ForwardOpaqueFeature();
		if (mRenderSystem.RegisterFeature(mForwardFeature) case .Err)
			Console.WriteLine("Warning: Failed to register ForwardOpaqueFeature");

		mSpriteFeature = new SpriteFeature();
		if (mRenderSystem.RegisterFeature(mSpriteFeature) case .Err)
			Console.WriteLine("Warning: Failed to register SpriteFeature");

		mSkyFeature = new SkyFeature();
		if (mRenderSystem.RegisterFeature(mSkyFeature) case .Err)
			Console.WriteLine("Warning: Failed to register SkyFeature");

		mFinalOutputFeature = new FinalOutputFeature();
		if (mRenderSystem.RegisterFeature(mFinalOutputFeature) case .Err)
			Console.WriteLine("Warning: Failed to register FinalOutputFeature");
	}

	private void CreateSprites()
	{
		// 16 outer ring sprites
		for (int i = 0; i < 16; i++)
		{
			let handle = mWorld.CreateSprite();
			if (let sprite = mWorld.GetSprite(handle))
			{
				float angle = (float)i / 16.0f * Math.PI_f * 2.0f;
				sprite.Position = .(Math.Cos(angle) * 4.0f, 1.0f, Math.Sin(angle) * 4.0f);
				sprite.Size = .(0.5f, 0.5f);

				// Rainbow colors
				float hue = (float)i / 16.0f;
				sprite.Color = HueToColor(hue);
			}
			mOuterSprites.Add(handle);
		}

		// 8 inner ring sprites
		for (int i = 0; i < 8; i++)
		{
			let handle = mWorld.CreateSprite();
			if (let sprite = mWorld.GetSprite(handle))
			{
				float angle = (float)i / 8.0f * Math.PI_f * 2.0f;
				sprite.Position = .(Math.Cos(angle) * 2.0f, 1.5f, Math.Sin(angle) * 2.0f);
				sprite.Size = .(0.4f, 0.4f);
				sprite.Color = .(255, 255, 255, 200);
			}
			mInnerSprites.Add(handle);
		}

		// Center sprite
		mCenterSprite = mWorld.CreateSprite();
		if (let sprite = mWorld.GetSprite(mCenterSprite))
		{
			sprite.Position = .(0, 2, 0);
			sprite.Size = .(0.8f, 0.8f);
			sprite.Color = .(255, 255, 0, 255);
		}
	}

	private static Color HueToColor(float hue)
	{
		float r = Math.Max(0, Math.Cos(hue * Math.PI_f * 2.0f));
		float g = Math.Max(0, Math.Cos((hue - 0.333f) * Math.PI_f * 2.0f));
		float b = Math.Max(0, Math.Cos((hue - 0.666f) * Math.PI_f * 2.0f));
		return .((uint8)(r * 255), (uint8)(g * 255), (uint8)(b * 255), 255);
	}

	protected override void OnInput()
	{
		let keyboard = mShell.InputManager.Keyboard;
		let mouse = mShell.InputManager.Mouse;

		if (keyboard.IsKeyPressed(.Escape))
			Exit();

		if (keyboard.IsKeyPressed(.Tab))
		{
			mMouseCaptured = !mMouseCaptured;
			mouse.RelativeMode = mMouseCaptured;
			mouse.Visible = !mMouseCaptured;
		}

		if (mMouseCaptured || mouse.IsButtonDown(.Right))
		{
			mYaw += mouse.DeltaX * LookSpeed;
			mPitch -= mouse.DeltaY * LookSpeed;
			mPitch = Math.Clamp(mPitch, -Math.PI_f * 0.49f, Math.PI_f * 0.49f);
		}
	}

	protected override void OnUpdate(FrameContext frame)
	{
		float dt = (float)frame.DeltaTime;
		float t = (float)frame.TotalTime;

		// Animate outer ring
		for (int i = 0; i < mOuterSprites.Count; i++)
		{
			if (let sprite = mWorld.GetSprite(mOuterSprites[i]))
			{
				float baseAngle = (float)i / 16.0f * Math.PI_f * 2.0f;
				float angle = baseAngle + t * 0.5f;
				float pulse = 1.0f + Math.Sin(t * 2.0f + baseAngle) * 0.3f;
				sprite.Position = .(Math.Cos(angle) * 4.0f, 1.0f + Math.Sin(t + baseAngle) * 0.5f, Math.Sin(angle) * 4.0f);
				sprite.Size = .(0.5f * pulse, 0.5f * pulse);
			}
		}

		// Animate inner ring (opposite direction)
		for (int i = 0; i < mInnerSprites.Count; i++)
		{
			if (let sprite = mWorld.GetSprite(mInnerSprites[i]))
			{
				float baseAngle = (float)i / 8.0f * Math.PI_f * 2.0f;
				float angle = baseAngle - t * 0.8f;
				sprite.Position = .(Math.Cos(angle) * 2.0f, 1.5f, Math.Sin(angle) * 2.0f);
			}
		}

		// Animate center sprite
		if (let sprite = mWorld.GetSprite(mCenterSprite))
		{
			float pulse = 0.6f + Math.Sin(t * 3.0f) * 0.3f;
			sprite.Size = .(pulse, pulse);
		}

		// Camera
		let keyboard = mShell.InputManager.Keyboard;
		float speed = keyboard.IsKeyDown(.LeftShift) ? MoveSpeed * 2 : MoveSpeed;

		float cosP = Math.Cos(mPitch);
		Vector3 forward = .(cosP * Math.Sin(mYaw), Math.Sin(mPitch), cosP * Math.Cos(mYaw));
		Vector3 right = Vector3.Normalize(Vector3.Cross(forward, .(0, 1, 0)));

		Vector3 move = .Zero;
		if (keyboard.IsKeyDown(.W)) move += forward;
		if (keyboard.IsKeyDown(.S)) move -= forward;
		if (keyboard.IsKeyDown(.D)) move += right;
		if (keyboard.IsKeyDown(.A)) move -= right;
		if (keyboard.IsKeyDown(.E)) move += .(0, 1, 0);
		if (keyboard.IsKeyDown(.Q)) move -= .(0, 1, 0);

		if (move.LengthSquared() > 0)
			mCameraPosition += Vector3.Normalize(move) * speed * dt;

		mCameraForward = Vector3.Normalize(.(cosP * Math.Sin(mYaw), Math.Sin(mPitch), cosP * Math.Cos(mYaw)));

		mView.CameraPosition = mCameraPosition;
		mView.CameraForward = mCameraForward;
		mView.CameraUp = .(0, 1, 0);
		mView.Width = mSwapChain.Width;
		mView.Height = mSwapChain.Height;
		mView.UpdateMatrices(mDevice.FlipProjectionRequired);
	}

	protected override bool OnRenderFrame(RenderContext render)
	{
		mRenderSystem.BeginFrame((float)render.Frame.TotalTime, (float)render.Frame.DeltaTime);

		if (mFinalOutputFeature != null)
			mFinalOutputFeature.SetSwapChain(render.SwapChain);

		mRenderSystem.SetCamera(
			mCameraPosition, mCameraForward, .(0, 1, 0),
			mView.FieldOfView, mView.AspectRatio,
			mView.NearPlane, mView.FarPlane,
			mView.Width, mView.Height
		);

		if (mRenderSystem.BuildRenderGraph(mView) case .Ok)
			mRenderSystem.Execute(render.Encoder);

		mRenderSystem.EndFrame();
		return true;
	}

	protected override void OnShutdown()
	{
		if (mRenderSystem != null)
			mRenderSystem.Shutdown();

		Console.WriteLine("Render Sprite shutting down");
	}
}
