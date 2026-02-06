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
