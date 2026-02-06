namespace FrameworkSerialization;

using System;
using System.IO;
using Sedulous.Mathematics;
using Sedulous.Framework.Runtime;
using Sedulous.Framework.Core;
using Sedulous.Framework.Scenes;
using Sedulous.Framework.Render;
using Sedulous.RHI;
using Sedulous.Shell;
using Sedulous.Render;
using Sedulous.Profiler;

class FrameworkSerializationApp : Application
{
	private const String SceneFilePath = "scene.oddl";

	// Framework
	private SceneSubsystem mSceneSubsystem;
	private RenderSubsystem mRenderSubsystem;
	private Scene mMainScene;

	// Render system
	private RenderSystem mRenderSystem ~ delete _;
	private RenderView mRenderView ~ delete _;

	// Render features
	private FinalOutputFeature mFinalOutputFeature;

	// Scene resource
	private SceneResource mSceneResource ~ delete _;

	public this(IShell shell, IDevice device, IBackend backend) : base(shell, device, backend)
	{
	}

	protected override void OnInitialize(Context context)
	{
		Console.WriteLine("=== Framework Serialization Sample ===\n");

		InitializeRenderSystem();
		RegisterSubsystems(context);
	}

	protected override void OnContextStarted()
	{
		SProfiler.Initialize();
		LoadOrCreateScene();
	}

	private void InitializeRenderSystem()
	{
		mRenderSystem = new RenderSystem();
		if (mRenderSystem.Initialize(mDevice, scope $"{AssetDirectory}/Render/Shaders", .BGRA8UnormSrgb, .Depth24PlusStencil8) case .Err)
		{
			Console.WriteLine("ERROR: Failed to initialize RenderSystem");
			return;
		}

		mRenderView = new RenderView();
		mRenderView.Width = mSwapChain.Width;
		mRenderView.Height = mSwapChain.Height;

		mFinalOutputFeature = new FinalOutputFeature();
		mRenderSystem.RegisterFeature(mFinalOutputFeature);
	}

	private void RegisterSubsystems(Context context)
	{
		// Scene
		mSceneSubsystem = new SceneSubsystem();
		context.RegisterSubsystem(mSceneSubsystem);

		// Render
		mRenderSubsystem = new RenderSubsystem(mRenderSystem, takeOwnership: false);
		context.RegisterSubsystem(mRenderSubsystem);
	}

	private void LoadOrCreateScene()
	{
		if (File.Exists(SceneFilePath))
		{
			// Load existing scene resource from file with component types registered
			mSceneResource = new SceneResource();
			mSceneResource.RegisterComponentType<TestComponent>();
			mSceneResource.RegisterComponentType<LightComponent>();
			mSceneResource.RegisterComponentType<CameraComponent>();
			switch (mSceneResource.Load(SceneFilePath))
			{
			case .Ok:
				let loadedScene = mSceneResource.Scene;
				Console.WriteLine($"Loaded scene from file: {loadedScene.Name} ({loadedScene.EntityCount} entities)");
				PrintComponentData(loadedScene);

				// Create a managed scene with the loaded name
				mMainScene = mSceneSubsystem.CreateScene(loadedScene.Name);
				mSceneSubsystem.SetActiveScene(mMainScene);

			case .Err:
				Console.WriteLine("ERROR: Failed to load scene from file, creating new one");
				delete mSceneResource;
				mSceneResource = null;
				CreateAndSaveScene();
			}
		}
		else
		{
			CreateAndSaveScene();
		}
	}

	private void CreateAndSaveScene()
	{
		// Create scene resource with test entities and components
		mSceneResource = SceneResource.CreateEmpty("SerializationTest");
		mSceneResource.RegisterComponentType<TestComponent>();
		mSceneResource.RegisterComponentType<LightComponent>();
		mSceneResource.RegisterComponentType<CameraComponent>();
		let scene = mSceneResource.Scene;

		// Root entity at origin with component
		let root = scene.CreateEntity();
		scene.SetName(root, "Root");
		scene.SetComponent<TestComponent>(root, .() { Speed = 5.0f, Health = 100, Active = true });

		// Child entity parented to root with component
		let child = scene.CreateEntity();
		scene.SetName(child, "Child");
		scene.SetTransform(child, .(.(2, 1, 0)));
		scene.SetParent(child, root);
		scene.SetComponent<TestComponent>(child, .() { Speed = 2.5f, Health = 50, Active = false });

		// Another root entity (no component - tests sparse serialization)
		let otherRoot = scene.CreateEntity();
		scene.SetName(otherRoot, "OtherRoot");
		scene.SetTransform(otherRoot, .(.(- 3, 0, 5)));

		// Lights with full configuration data
		let dirLight = scene.CreateEntity();
		scene.SetName(dirLight, "DirectionalLight");
		scene.SetTransform(dirLight, .(.(0, 10, 0), Quaternion.CreateFromAxisAngle(.(1, 0, 0), -0.8f)));
		scene.SetComponent<LightComponent>(dirLight, .() {
			Type = .Directional, Color = .(1.0f, 0.95f, 0.8f), Intensity = 2.0f,
			Enabled = true, ShadowBias = 0.005f, ShadowNormalBias = 0.02f, LayerMask = 0xFFFFFFFF
		});
		scene.SetComponent<CameraComponent>(dirLight, .() { Active = false, IsMainCamera = false,
			Projection = .Perspective, FieldOfView = Math.PI_f / 4.0f, AspectRatio = 16.0f / 9.0f,
			NearPlane = 0.1f, FarPlane = 1000.0f, OrthoWidth = 10.0f, OrthoHeight = 10.0f
		});

		let pointLight = scene.CreateEntity();
		scene.SetName(pointLight, "PointLight");
		scene.SetTransform(pointLight, .(.(3, 2, -1)));
		scene.SetComponent<LightComponent>(pointLight, .() {
			Type = .Point, Color = .(1.0f, 0.8f, 0.6f), Intensity = 5.0f, Range = 15.0f,
			Enabled = true, ShadowBias = 0.005f, ShadowNormalBias = 0.02f, LayerMask = 0xFFFFFFFF
		});

		let spotLight = scene.CreateEntity();
		scene.SetName(spotLight, "SpotLight");
		scene.SetTransform(spotLight, .(.(- 2, 5, 3), Quaternion.CreateFromAxisAngle(.(1, 0, 0), -1.2f)));
		scene.SetComponent<LightComponent>(spotLight, .() {
			Type = .Spot, Color = .(0.8f, 0.8f, 1.0f), Intensity = 8.0f, Range = 20.0f,
			InnerConeAngle = Math.PI_f / 8.0f, OuterConeAngle = Math.PI_f / 4.0f,
			Enabled = true, ShadowBias = 0.005f, ShadowNormalBias = 0.02f, LayerMask = 0xFFFFFFFF
		});

		// Save to file
		switch (mSceneResource.SaveToFile(SceneFilePath))
		{
		case .Ok:
			Console.WriteLine($"Created and saved scene: {scene.Name} ({scene.EntityCount} entities)");
			PrintComponentData(scene);
		case .Err:
			Console.WriteLine("ERROR: Failed to save scene to file");
		}

		// Create managed scene
		mMainScene = mSceneSubsystem.CreateScene(mSceneResource.Scene.Name);
		mSceneSubsystem.SetActiveScene(mMainScene);
	}

	private void PrintComponentData(Scene scene)
	{
		for (let (entity, comp) in scene.Query<TestComponent>())
		{
			let name = scene.GetName(entity);
			Console.WriteLine($"  {name}: Speed={comp.Speed}, Health={comp.Health}, Active={comp.Active}");
		}
		for (let (entity, comp) in scene.Query<LightComponent>())
		{
			let name = scene.GetName(entity);
			Console.WriteLine($"  {name}: Light(Type={comp.Type}, Color=({comp.Color.X:.2},{comp.Color.Y:.2},{comp.Color.Z:.2}), Intensity={comp.Intensity}, Range={comp.Range}, Enabled={comp.Enabled})");
		}
		for (let (entity, comp) in scene.Query<CameraComponent>())
		{
			let name = scene.GetName(entity);
			Console.WriteLine($"  {name}: Camera(Projection={comp.Projection}, FOV={comp.FieldOfView:.2}, Near={comp.NearPlane}, Far={comp.FarPlane}, Active={comp.Active}, IsMain={comp.IsMainCamera})");
		}
	}

	protected override void OnInput()
	{
		let keyboard = mShell.InputManager.Keyboard;

		if (keyboard.IsKeyPressed(.Escape))
			Exit();
	}

	protected override bool OnRenderFrame(RenderContext render)
	{
		mRenderSystem.BeginFrame((float)render.Frame.TotalTime, (float)render.Frame.DeltaTime);

		if (mFinalOutputFeature != null)
			mFinalOutputFeature.SetSwapChain(render.SwapChain);

		mRenderView.Width = mSwapChain.Width;
		mRenderView.Height = mSwapChain.Height;

		if (mRenderSystem.BuildRenderGraph(mRenderView) case .Ok)
			mRenderSystem.Execute(render.Encoder);

		mRenderSystem.EndFrame();
		return true;
	}

	protected override void OnShutdown()
	{
		Profiler.Shutdown();

		if (mRenderSystem != null)
			mRenderSystem.Shutdown();
	}
}
