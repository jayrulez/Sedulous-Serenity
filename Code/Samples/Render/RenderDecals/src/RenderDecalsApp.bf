namespace RenderDecals;

using System;
using System.Collections;
using Sedulous.Foundation.Mathematics;
using Sedulous.RHI;
using Sedulous.Shell;
using Sedulous.Framework.Runtime;
using Sedulous.Render;
using Sedulous.Geometry;
using Sedulous.Materials;

/// Demonstrates screen-space projected decal rendering.
/// Creates a floor with cubes and projects decals onto them.
class RenderDecalsApp : Application
{
	// Render system
	private RenderSystem mRenderSystem ~ delete _;
	private RenderWorld mWorld ~ delete _;
	private RenderView mView ~ delete _;

	// Render features
	private DepthPrepassFeature mDepthFeature;
	private ForwardOpaqueFeature mForwardFeature;
	private DecalFeature mDecalFeature;
	private SkyFeature mSkyFeature;
	private FinalOutputFeature mFinalOutputFeature;

	// Meshes
	private GPUMeshHandle mCubeMeshHandle;
	private GPUMeshHandle mPlaneMeshHandle;

	// Materials
	private MaterialInstance mFloorMaterial ~ _?.ReleaseRef();
	private MaterialInstance mCubeMaterial ~ _?.ReleaseRef();

	// Decals
	private DecalProxyHandle mFloorDecal = .Invalid;
	private DecalProxyHandle mWallDecal = .Invalid;
	private DecalProxyHandle mGlowDecal = .Invalid;
	private DecalProxyHandle mLargeDecal = .Invalid;

	// Decal textures
	private ITexture mCircleTexture ~ delete _;
	private ITextureView mCircleTextureView ~ delete _;
	private ITexture mCrosshairTexture ~ delete _;
	private ITextureView mCrosshairTextureView ~ delete _;
	private ITexture mStarTexture ~ delete _;
	private ITextureView mStarTextureView ~ delete _;

	// Light
	private LightProxyHandle mSunLight = .Invalid;

	// Camera
	private Vector3 mCameraPosition = .(0, 8, 12);
	private float mYaw = Math.PI_f;
	private float mPitch = -0.4f;
	private Vector3 mCameraForward;
	private bool mMouseCaptured = false;
	private const float MoveSpeed = 10.0f;
	private const float FastMoveSpeed = 25.0f;
	private const float LookSpeed = 0.003f;

	public this(IShell shell, IDevice device, IBackend backend)
		: base(shell, device, backend)
	{
	}

	protected override void OnInitialize(Sedulous.Framework.Core.Context context)
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
		mView.FarPlane = 200.0f;

		RegisterFeatures();
		CreateMeshes();
		CreateMaterials();
		CreateScene();
		CreateDecalTextures();
		CreateDecals();
		CreateLights();

		mWorld.AmbientColor = .(0.03f, 0.03f, 0.03f);
		mWorld.AmbientIntensity = 0.5f;
		mWorld.Exposure = 1.0f;

		Console.WriteLine("Render Decals initialized");
		Console.WriteLine("  WASD/QE: move, Right-click: look, Tab: capture, Shift: fast");
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

		mDecalFeature = new DecalFeature();
		if (mRenderSystem.RegisterFeature(mDecalFeature) case .Err)
			Console.WriteLine("Warning: Failed to register DecalFeature");

		mSkyFeature = new SkyFeature();
		if (mRenderSystem.RegisterFeature(mSkyFeature) case .Err)
			Console.WriteLine("Warning: Failed to register SkyFeature");

		mFinalOutputFeature = new FinalOutputFeature();
		if (mRenderSystem.RegisterFeature(mFinalOutputFeature) case .Err)
			Console.WriteLine("Warning: Failed to register FinalOutputFeature");
	}

	private void CreateMeshes()
	{
		// Unit cube
		let cubeMesh = StaticMesh.CreateCube(1.0f);
		if (mRenderSystem.ResourceManager.UploadMesh(cubeMesh) case .Ok(let handle))
			mCubeMeshHandle = handle;
		delete cubeMesh;

		// Floor plane (20x20)
		let planeMesh = StaticMesh.CreatePlane(20.0f, 20.0f);
		if (mRenderSystem.ResourceManager.UploadMesh(planeMesh) case .Ok(let planeHandle))
			mPlaneMeshHandle = planeHandle;
		delete planeMesh;
	}

	private void CreateMaterials()
	{
		if (let baseMat = mRenderSystem.MaterialSystem?.DefaultMaterial)
		{
			// Gray floor
			mFloorMaterial = new MaterialInstance(baseMat);
			mFloorMaterial.SetColor("BaseColor", .(0.4f, 0.4f, 0.4f, 1.0f));
			mFloorMaterial.SetFloat("Roughness", 0.8f);

			// Blue-gray cubes
			mCubeMaterial = new MaterialInstance(baseMat);
			mCubeMaterial.SetColor("BaseColor", .(0.5f, 0.5f, 0.6f, 1.0f));
			mCubeMaterial.SetFloat("Roughness", 0.5f);
		}
	}

	private void CreateScene()
	{
		let defaultMaterial = mRenderSystem.MaterialSystem?.DefaultMaterialInstance;

		// Floor
		{
			let floor = mWorld.CreateMesh();
			if (let proxy = mWorld.GetMesh(floor))
			{
				proxy.MeshHandle = mPlaneMeshHandle;
				proxy.Materials[0] = mFloorMaterial ?? defaultMaterial;
				proxy.MaterialCount = 1;
				proxy.SetLocalBounds(BoundingBox(Vector3(-10, -0.01f, -10), Vector3(10, 0.01f, 10)));
				proxy.SetTransformImmediate(Matrix.Identity);
				proxy.Flags = .DefaultOpaque;
			}
		}

		// Cubes placed on the floor
		Vector3[4] cubePositions = .(
			.(-3, 0.5f, -2),
			.(2, 0.5f, -1),
			.(0, 0.5f, 3),
			.(4, 0.5f, 2)
		);

		for (let pos in cubePositions)
		{
			let cube = mWorld.CreateMesh();
			if (let proxy = mWorld.GetMesh(cube))
			{
				proxy.MeshHandle = mCubeMeshHandle;
				proxy.Materials[0] = mCubeMaterial ?? defaultMaterial;
				proxy.MaterialCount = 1;
				proxy.SetLocalBounds(BoundingBox(Vector3(-0.5f), Vector3(0.5f)));
				proxy.SetTransformImmediate(Matrix.CreateTranslation(pos));
				proxy.Flags = .DefaultOpaque;
			}
		}

		// A taller cube for wall decal testing
		{
			let tallCube = mWorld.CreateMesh();
			if (let proxy = mWorld.GetMesh(tallCube))
			{
				proxy.MeshHandle = mCubeMeshHandle;
				proxy.Materials[0] = mCubeMaterial ?? defaultMaterial;
				proxy.MaterialCount = 1;
				proxy.SetLocalBounds(BoundingBox(Vector3(-0.5f), Vector3(0.5f)));
				proxy.SetTransformImmediate(Matrix.CreateScale(1.0f, 2.0f, 1.0f) * Matrix.CreateTranslation(-1, 1, 0));
				proxy.Flags = .DefaultOpaque;
			}
		}
	}

	private void CreateDecalTextures()
	{
		// Circle texture: soft white circle with alpha falloff
		CreateCircleTexture();
		// Crosshair texture: cross pattern
		CreateCrosshairTexture();
		// Star texture: radial burst pattern
		CreateStarTexture();
	}

	private void CreateCircleTexture()
	{
		const int32 Size = 64;
		const int32 Bytes = Size * Size * 4;

		TextureDescriptor texDesc = .()
		{
			Label = "Circle Decal Texture",
			Width = Size, Height = Size, Depth = 1,
			Format = .RGBA8Unorm, MipLevelCount = 1, ArrayLayerCount = 1,
			SampleCount = 1, Dimension = .Texture2D,
			Usage = .Sampled | .CopyDst
		};

		switch (mDevice.CreateTexture(&texDesc))
		{
		case .Ok(let tex): mCircleTexture = tex;
		case .Err: return;
		}

		uint8[Bytes] pixels = default;
		float center = (Size - 1) * 0.5f;

		for (int32 y = 0; y < Size; y++)
		{
			for (int32 x = 0; x < Size; x++)
			{
				float dx = ((float)x - center) / center;
				float dy = ((float)y - center) / center;
				float dist = Math.Sqrt(dx * dx + dy * dy);

				float alpha = 0.0f;
				if (dist < 0.8f)
					alpha = 1.0f;
				else if (dist < 1.0f)
					alpha = 1.0f - (dist - 0.8f) / 0.2f;

				int32 idx = (y * Size + x) * 4;
				pixels[idx] = 255;
				pixels[idx + 1] = 255;
				pixels[idx + 2] = 255;
				pixels[idx + 3] = (uint8)(alpha * 255.0f);
			}
		}

		var layout = TextureDataLayout() { BytesPerRow = Size * 4, RowsPerImage = Size };
		var writeSize = Extent3D(Size, Size, 1);
		mDevice.Queue.WriteTexture(mCircleTexture, Span<uint8>(&pixels[0], Bytes), &layout, &writeSize);

		TextureViewDescriptor viewDesc = .() { Label = "Circle Decal View", Dimension = .Texture2D };
		switch (mDevice.CreateTextureView(mCircleTexture, &viewDesc))
		{
		case .Ok(let view): mCircleTextureView = view;
		case .Err:
		}
	}

	private void CreateCrosshairTexture()
	{
		const int32 Size = 64;
		const int32 Bytes = Size * Size * 4;

		TextureDescriptor texDesc = .()
		{
			Label = "Crosshair Decal Texture",
			Width = Size, Height = Size, Depth = 1,
			Format = .RGBA8Unorm, MipLevelCount = 1, ArrayLayerCount = 1,
			SampleCount = 1, Dimension = .Texture2D,
			Usage = .Sampled | .CopyDst
		};

		switch (mDevice.CreateTexture(&texDesc))
		{
		case .Ok(let tex): mCrosshairTexture = tex;
		case .Err: return;
		}

		uint8[Bytes] pixels = default;
		float center = (Size - 1) * 0.5f;
		float lineWidth = 2.0f;

		for (int32 y = 0; y < Size; y++)
		{
			for (int32 x = 0; x < Size; x++)
			{
				float dx = Math.Abs((float)x - center);
				float dy = Math.Abs((float)y - center);
				float dist = Math.Sqrt(dx * dx + dy * dy) / center;

				// Cross pattern
				bool onCross = (dx < lineWidth || dy < lineWidth) && dist < 0.9f;
				// Ring
				bool onRing = Math.Abs(dist - 0.7f) < 0.05f;

				float alpha = 0.0f;
				if (onCross || onRing)
					alpha = 1.0f;

				// Fade at edges
				if (dist > 0.85f && dist < 1.0f)
					alpha *= 1.0f - (dist - 0.85f) / 0.15f;

				int32 idx = (y * Size + x) * 4;
				pixels[idx] = 255;
				pixels[idx + 1] = 255;
				pixels[idx + 2] = 255;
				pixels[idx + 3] = (uint8)(alpha * 255.0f);
			}
		}

		var layout = TextureDataLayout() { BytesPerRow = Size * 4, RowsPerImage = Size };
		var writeSize = Extent3D(Size, Size, 1);
		mDevice.Queue.WriteTexture(mCrosshairTexture, Span<uint8>(&pixels[0], Bytes), &layout, &writeSize);

		TextureViewDescriptor viewDesc = .() { Label = "Crosshair Decal View", Dimension = .Texture2D };
		switch (mDevice.CreateTextureView(mCrosshairTexture, &viewDesc))
		{
		case .Ok(let view): mCrosshairTextureView = view;
		case .Err:
		}
	}

	private void CreateStarTexture()
	{
		const int32 Size = 64;
		const int32 Bytes = Size * Size * 4;

		TextureDescriptor texDesc = .()
		{
			Label = "Star Decal Texture",
			Width = Size, Height = Size, Depth = 1,
			Format = .RGBA8Unorm, MipLevelCount = 1, ArrayLayerCount = 1,
			SampleCount = 1, Dimension = .Texture2D,
			Usage = .Sampled | .CopyDst
		};

		switch (mDevice.CreateTexture(&texDesc))
		{
		case .Ok(let tex): mStarTexture = tex;
		case .Err: return;
		}

		uint8[Bytes] pixels = default;
		float center = (Size - 1) * 0.5f;

		for (int32 y = 0; y < Size; y++)
		{
			for (int32 x = 0; x < Size; x++)
			{
				float dx = ((float)x - center) / center;
				float dy = ((float)y - center) / center;
				float dist = Math.Sqrt(dx * dx + dy * dy);
				float angle = Math.Atan2(dy, dx);

				// 6-pointed star pattern
				float starRadius = 0.4f + 0.3f * Math.Abs(Math.Cos(angle * 3.0f));

				float alpha = 0.0f;
				if (dist < starRadius)
				{
					alpha = 1.0f - dist / starRadius;
					alpha *= alpha; // Quadratic falloff for glow effect
				}

				int32 idx = (y * Size + x) * 4;
				pixels[idx] = 255;
				pixels[idx + 1] = 255;
				pixels[idx + 2] = 255;
				pixels[idx + 3] = (uint8)(Math.Clamp(alpha, 0.0f, 1.0f) * 255.0f);
			}
		}

		var layout = TextureDataLayout() { BytesPerRow = Size * 4, RowsPerImage = Size };
		var writeSize = Extent3D(Size, Size, 1);
		mDevice.Queue.WriteTexture(mStarTexture, Span<uint8>(&pixels[0], Bytes), &layout, &writeSize);

		TextureViewDescriptor viewDesc = .() { Label = "Star Decal View", Dimension = .Texture2D };
		switch (mDevice.CreateTextureView(mStarTexture, &viewDesc))
		{
		case .Ok(let view): mStarTextureView = view;
		case .Err:
		}
	}

	private void CreateDecals()
	{
		// Floor decal: red circle projected downward onto the floor
		mFloorDecal = mWorld.CreateDecal();
		if (let proxy = mWorld.GetDecal(mFloorDecal))
		{
			proxy.Position = .(0, 0.5f, 0);
			proxy.Rotation = .Identity;  // Projects along -Y onto floor
			proxy.Scale = .(3, 2, 3);    // 3x3 unit area, 2 units deep
			proxy.AlbedoTexture = mCircleTextureView;
			proxy.Color = .(1.0f, 0.3f, 0.2f, 0.8f);  // Red tint
			proxy.BlendMode = .Alpha;
			proxy.SortOrder = 0;
		}

		// Wall decal: blue crosshair projected horizontally onto the tall cube
		mWallDecal = mWorld.CreateDecal();
		if (let proxy = mWorld.GetDecal(mWallDecal))
		{
			proxy.Position = .(-1, 1, 0.5f);
			proxy.Rotation = Quaternion.CreateFromAxisAngle(.(1, 0, 0), Math.PI_f * 0.5f);  // Rotate to project along -Z
			proxy.Scale = .(1.2f, 2, 1.2f);
			proxy.AlbedoTexture = mCrosshairTextureView;
			proxy.Color = .(0.3f, 0.5f, 1.0f, 0.9f);  // Blue tint
			proxy.BlendMode = .Alpha;
			proxy.SortOrder = 1;
		}

		// Additive glow decal: yellow star on the floor
		mGlowDecal = mWorld.CreateDecal();
		if (let proxy = mWorld.GetDecal(mGlowDecal))
		{
			proxy.Position = .(3, 0.5f, -2);
			proxy.Rotation = .Identity;
			proxy.Scale = .(2, 2, 2);
			proxy.AlbedoTexture = mStarTextureView;
			proxy.Color = .(1.0f, 0.9f, 0.3f, 1.0f);  // Yellow
			proxy.BlendMode = .Additive;
			proxy.SortOrder = 2;
		}

		// Large decal: spans floor and cube edge
		mLargeDecal = mWorld.CreateDecal();
		if (let proxy = mWorld.GetDecal(mLargeDecal))
		{
			proxy.Position = .(-3, 0.5f, -2);
			proxy.Rotation = .Identity;
			proxy.Scale = .(4, 2, 4);  // Large area
			proxy.AlbedoTexture = mCircleTextureView;
			proxy.Color = .(0.2f, 0.8f, 0.3f, 0.6f);  // Green tint
			proxy.BlendMode = .Alpha;
			proxy.SortOrder = 0;
		}
	}

	private void CreateLights()
	{
		// Directional sun
		mSunLight = mWorld.CreateDirectionalLight(
			Vector3.Normalize(.(-0.5f, -1.0f, -0.3f)),
			.(1.0f, 0.95f, 0.8f),
			2.0f
		);
		if (let light = mWorld.GetLight(mSunLight))
			light.CastsShadows = true;
		if (mForwardFeature?.ShadowRenderer != null)
			mForwardFeature.ShadowRenderer.EnableShadows = true;
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

		let keyboard = mShell.InputManager.Keyboard;
		float speed = keyboard.IsKeyDown(.LeftShift) ? FastMoveSpeed : MoveSpeed;

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
		if (mCubeMeshHandle.IsValid)
			mRenderSystem.ResourceManager.ReleaseMesh(mCubeMeshHandle, mRenderSystem.FrameNumber);
		if (mPlaneMeshHandle.IsValid)
			mRenderSystem.ResourceManager.ReleaseMesh(mPlaneMeshHandle, mRenderSystem.FrameNumber);

		if (mRenderSystem != null)
			mRenderSystem.Shutdown();

		Console.WriteLine("Render Decals shutting down");
	}
}
