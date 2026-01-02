using System;
using Sedulous.Shell;
using Sedulous.Shell.Input;
using Sedulous.Shell.SDL3;

namespace ShellSample;

class Program
{
	public static int Main(String[] args)
	{
		let shell = new SDL3Shell();
		defer delete shell;

		if (shell.Initialize() case .Err)
		{
			Console.WriteLine("Failed to initialize shell");
			return 1;
		}

		// Create a window
		let windowSettings = WindowSettings()
		{
			Title = "Shell Sample",
			Width = 1280,
			Height = 720,
			Resizable = true,
			Bordered = true
		};

		let windowResult = shell.WindowManager.CreateWindow(windowSettings);
		if (windowResult case .Err)
		{
			Console.WriteLine("Failed to create window");
			return 1;
		}

		// Subscribe to events
		shell.WindowManager.OnWindowEvent.Subscribe(new (win, evt) => {
			Console.WriteLine(scope $"Window Event: {evt.Type}");
			if (evt.Type == .Resized || evt.Type == .Moved)
				Console.WriteLine(scope $"  Data: {evt.Data1}, {evt.Data2}");
		});

		shell.InputManager.Keyboard.OnKeyEvent.Subscribe(new (key, down) => {
			Console.WriteLine(scope $"Key: {key} {(down ? "pressed" : "released")}");
		});

		shell.InputManager.Keyboard.OnTextInput.Subscribe(new (text) => {
			Console.WriteLine(scope $"Text: {text}");
		});

		shell.InputManager.Mouse.OnMove.Subscribe(new (x, y) => {
			// Only log occasionally to avoid spam
			// Console.WriteLine(scope $"Mouse: {x}, {y}");
		});

		shell.InputManager.Mouse.OnButton.Subscribe(new (button, down) => {
			Console.WriteLine(scope $"Mouse Button: {button} {(down ? "pressed" : "released")}");
		});

		shell.InputManager.Mouse.OnScroll.Subscribe(new (x, y) => {
			Console.WriteLine(scope $"Mouse Scroll: {x}, {y}");
		});

		shell.InputManager.Touch.OnTouchDown.Subscribe(new (point) => {
			Console.WriteLine(scope $"Touch Down: ID={point.ID} ({point.X}, {point.Y}) pressure={point.Pressure}");
		});

		shell.InputManager.Touch.OnTouchUp.Subscribe(new (point) => {
			Console.WriteLine(scope $"Touch Up: ID={point.ID} ({point.X}, {point.Y})");
		});

		shell.InputManager.Touch.OnTouchMove.Subscribe(new (point) => {
			Console.WriteLine(scope $"Touch Move: ID={point.ID} ({point.X}, {point.Y})");
		});

		Console.WriteLine("Shell Sample running. Press Escape to exit.");
		Console.WriteLine("Move mouse, press keys, scroll wheel, etc. to see input events.");

		// Main loop
		while (shell.IsRunning)
		{
			shell.ProcessEvents();

			// Check for escape key to exit
			if (shell.InputManager.Keyboard.IsKeyPressed(.Escape))
			{
				Console.WriteLine("Escape pressed, exiting...");
				shell.RequestExit();
			}

			// Log gamepad info if connected
			for (int i = 0; i < shell.InputManager.GamepadCount; i++)
			{
				let gamepad = shell.InputManager.GetGamepad(i);
				if (gamepad != null && gamepad.Connected)
				{
					// Log any button presses
					for (let button in Enum.GetValues<GamepadButton>())
					{
						if (button == .Count)
							continue;
						if (gamepad.IsButtonPressed(button))
							Console.WriteLine(scope $"Gamepad {i} Button: {button} pressed");
						if (gamepad.IsButtonReleased(button))
							Console.WriteLine(scope $"Gamepad {i} Button: {button} released");
					}
				}
			}
		}

		Console.WriteLine("Shell Sample finished.");
		shell.Shutdown();
		return 0;
	}
}
