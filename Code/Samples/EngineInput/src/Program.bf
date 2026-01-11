namespace EngineInput;

using System;
using Sedulous.Shell;
using Sedulous.Shell.SDL3;
using Sedulous.Shell.Input;
using Sedulous.Engine.Core;
using Sedulous.Engine.Input;
using Sedulous.Mathematics;

class Program
{
	private static IShell mShell;
	private static Context mContext;
	private static InputService mInputService;

	// Simulated camera position for demonstration
	private static Vector3 mPosition = .(0, 0, 0);
	private static float mYaw = 0;
	private static float mPitch = 0;
	private static float mMoveSpeed = 5.0f;
	private static float mLookSpeed = 0.003f;
	private static bool mMouseCaptured = false;

	public static int Main(String[] args)
	{
		Console.WriteLine("=== Sedulous Engine Input Sample ===");
		Console.WriteLine("Demonstrates the high-level input framework.");
		Console.WriteLine("");

		// Create shell
		mShell = new SDL3Shell();
		defer delete mShell;

		if (mShell.Initialize() case .Err)
		{
			Console.WriteLine("Failed to initialize shell");
			return 1;
		}

		// Create a window
		let windowSettings = WindowSettings()
		{
			Title = "Engine Input Sample",
			Width = 1280,
			Height = 720,
			Resizable = true,
			Bordered = true
		};
		if (mShell.WindowManager.CreateWindow(windowSettings) case .Err)
		{
			Console.WriteLine("Failed to create window");
			return 1;
		}

		// Create engine context
		mContext = new Context(null, 1);
		defer delete mContext;

		// Create and register input service
		mInputService = new InputService(mShell.InputManager);
		mContext.RegisterService<InputService>(mInputService);

		// Setup input actions
		SetupInputActions();

		// Start the context (required for Update to process services)
		mContext.Startup();

		// Print instructions
		Console.WriteLine("Controls:");
		Console.WriteLine("  WASD / Arrow Keys / Left Stick - Move");
		Console.WriteLine("  Mouse / Right Stick - Look (when captured)");
		Console.WriteLine("  Tab - Toggle mouse capture");
		Console.WriteLine("  Space / Gamepad A - Jump");
		Console.WriteLine("  Left Mouse / Right Trigger - Fire");
		Console.WriteLine("  Shift - Sprint");
		Console.WriteLine("  Escape - Exit");
		Console.WriteLine("");

		// Main loop
		while (mShell.IsRunning)
		{
			mShell.ProcessEvents();

			if (mShell.InputManager.Keyboard.IsKeyPressed(.Escape))
			{
				mShell.RequestExit();
				continue;
			}

			// Update context (updates InputService)
			mContext.Update(0.016f); // ~60fps

			// Process input
			ProcessInput();
		}

		// Shutdown
		mContext.Shutdown();

		//delete mGamplayInputContext;
		delete mInputService;

		mShell.Shutdown();

		Console.WriteLine("Input sample completed.");
		return 0;
	}

	private static void SetupInputActions()
	{
		// Create gameplay context
		let context = mInputService.CreateContext("Gameplay", priority: 0);

		// Movement action with WASD + Arrow keys + Gamepad left stick
		let move = context.RegisterAction("Move");
		move.AddBinding(new CompositeBinding(.W, .S, .A, .D));
		move.AddBinding(new CompositeBinding(.Up, .Down, .Left, .Right));
		move.AddBinding(new GamepadStickBinding(.Left));

		// Look action with mouse and gamepad right stick
		let look = context.RegisterAction("Look");
		look.AddBinding(new MouseAxisBinding(.Delta, 1.0f));
		let rightStick = new GamepadStickBinding(.Right);
		rightStick.Sensitivity = 2.0f;
		look.AddBinding(rightStick);

		// Jump action with Space and Gamepad A
		let jump = context.RegisterAction("Jump");
		jump.AddBinding(new KeyBinding(.Space));
		jump.AddBinding(new GamepadButtonBinding(.South));

		// Fire action with Left Mouse and Right Trigger
		let fire = context.RegisterAction("Fire");
		fire.AddBinding(new MouseButtonBinding(.Left));
		fire.AddBinding(new GamepadAxisBinding(.RightTrigger));

		// Sprint modifier with Shift
		let sprint = context.RegisterAction("Sprint");
		sprint.AddBinding(new KeyBinding(.LeftShift));
		sprint.AddBinding(new KeyBinding(.RightShift));

		// Mouse capture toggle with Tab
		let toggleCapture = context.RegisterAction("ToggleCapture");
		toggleCapture.AddBinding(new KeyBinding(.Tab));

		// Register callback for jump
		context.OnAction("Jump", new (action) => {
			Console.WriteLine("JUMP!");
		});

		// Register callback for toggle capture
		context.OnAction("ToggleCapture", new (action) => {
			mMouseCaptured = !mMouseCaptured;
			mShell.InputManager.Mouse.RelativeMode = mMouseCaptured;
			mShell.InputManager.Mouse.Visible = !mMouseCaptured;
			Console.WriteLine(mMouseCaptured ? "Mouse captured" : "Mouse released");
		});

		Console.WriteLine($"Input actions registered: {context.ActionCount} actions");
	}

	private static void ProcessInput()
	{
		let deltaTime = 0.016f;

		// Get movement
		let moveAction = mInputService.GetAction("Move");
		if (moveAction != null)
		{
			let moveDir = moveAction.Vector2Value;
			if (moveDir.LengthSquared() > 0.01f)
			{
				// Calculate movement speed
				float speed = mMoveSpeed;
				let sprintAction = mInputService.GetAction("Sprint");
				if (sprintAction != null && sprintAction.IsActive)
					speed *= 2.0f;

				// Calculate forward/right vectors from yaw
				float cosYaw = Math.Cos(mYaw);
				float sinYaw = Math.Sin(mYaw);
				let forward = Vector3(sinYaw, 0, cosYaw);
				let right = Vector3(cosYaw, 0, -sinYaw);

				// Apply movement
				mPosition += forward * moveDir.Y * speed * deltaTime;
				mPosition += right * moveDir.X * speed * deltaTime;

				// Print position occasionally
				if (Math.Abs(moveDir.X) > 0.5f || Math.Abs(moveDir.Y) > 0.5f)
				{
					// Only print when significant movement
				}
			}
		}

		// Get look input (only when mouse captured)
		if (mMouseCaptured)
		{
			let lookAction = mInputService.GetAction("Look");
			if (lookAction != null)
			{
				let lookDelta = lookAction.Vector2Value;
				if (lookDelta.LengthSquared() > 0.01f)
				{
					mYaw -= lookDelta.X * mLookSpeed;
					mPitch -= lookDelta.Y * mLookSpeed;
					mPitch = Math.Clamp(mPitch, -Math.PI_f * 0.49f, Math.PI_f * 0.49f);
				}
			}
		}

		// Fire action
		let fireAction = mInputService.GetAction("Fire");
		if (fireAction != null && fireAction.WasPressed)
		{
			Console.WriteLine("FIRE!");
		}
	}
}
