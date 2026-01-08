# Sedulous.Shell

A platform abstraction layer for windowing, input, and application lifecycle. Provides interfaces for creating windows, handling keyboard/mouse/gamepad/touch input, and managing the main loop.

## Overview

```
Sedulous.Shell        - Core interfaces
Sedulous.Shell.SDL3   - SDL3 backend implementation
```

## Core Types

| Type | Purpose |
|------|---------|
| `IShell` | Main entry point - lifecycle, window manager, input manager. |
| `IWindowManager` | Creates and manages windows. |
| `IWindow` | Platform window with position, size, state. |
| `IInputManager` | Coordinates keyboard, mouse, gamepad, touch. |
| `IKeyboard` | Keyboard state and events. |
| `IMouse` | Mouse position, buttons, scroll. |
| `IGamepad` | Controller buttons, axes, rumble. |
| `ITouch` | Multi-touch input. |
| `IClipboard` | Clipboard text operations. |

## Application Lifecycle

### Basic Setup

```beef
let shell = new SDL3Shell();
defer delete shell;

// Initialize
if (shell.Initialize() case .Err)
{
    Console.WriteLine("Failed to initialize");
    return 1;
}

// Create window
let settings = WindowSettings()
{
    Title = "My App",
    Width = 1280,
    Height = 720
};

let windowResult = shell.WindowManager.CreateWindow(settings);
if (windowResult case .Err)
{
    Console.WriteLine("Failed to create window");
    return 1;
}

let window = windowResult.Value;
```

### Main Loop

```beef
while (shell.IsRunning)
{
    // Process events and update input state
    shell.ProcessEvents();

    // Check for exit
    if (shell.InputManager.Keyboard.IsKeyPressed(.Escape))
        shell.RequestExit();

    // Update game logic
    Update(deltaTime);

    // Render
    Render();
}

// Cleanup
shell.Shutdown();
```

## IShell API

```beef
interface IShell
{
    IWindowManager WindowManager { get; }
    IInputManager InputManager { get; }
    bool IsRunning { get; }

    Result<void> Initialize();
    void Shutdown();
    void ProcessEvents();
    void RequestExit();
}
```

## Window Management

### WindowSettings

```beef
struct WindowSettings
{
    String Title;
    int32 X, Y;           // Position (Centered=-1, Undefined=-2)
    int32 Width, Height;  // Size
    bool Resizable;       // Can resize
    bool Bordered;        // Has border/title bar
    bool Maximized;       // Start maximized
    bool Minimized;       // Start minimized
    bool Fullscreen;      // Fullscreen mode
    bool Hidden;          // Start hidden

    static WindowSettings Default { get; }  // 1280x720, centered
}
```

### IWindowManager API

```beef
interface IWindowManager
{
    int WindowCount { get; }
    EventAccessor<WindowEventDelegate> OnWindowEvent { get; }

    Result<IWindow> CreateWindow(WindowSettings settings);
    void DestroyWindow(IWindow window);
    IWindow GetWindow(uint32 id);
}
```

### IWindow API

```beef
interface IWindow
{
    uint32 ID { get; }
    String Title { get; set; }
    int32 X { get; set; }
    int32 Y { get; set; }
    int32 Width { get; set; }
    int32 Height { get; set; }
    WindowState State { get; }
    bool Visible { get; set; }
    bool Focused { get; }
    void* NativeHandle { get; }  // HWND on Windows

    void Show();
    void Hide();
    void Minimize();
    void Maximize();
    void Restore();
    void Close();
    void SetFullscreen(bool fullscreen);
}
```

### WindowState

```beef
enum WindowState
{
    Normal,
    Minimized,
    Maximized,
    Fullscreen
}
```

### Window Events

```beef
enum WindowEventType
{
    Shown, Hidden, Exposed,
    Moved, Resized,
    Minimized, Maximized, Restored,
    MouseEnter, MouseLeave,
    FocusGained, FocusLost,
    CloseRequested,
    EnterFullscreen, LeaveFullscreen
}

// Subscribe to events
shell.WindowManager.OnWindowEvent.Subscribe(new (window, event) => {
    if (event.Type == .Resized)
    {
        int32 newWidth = event.Data1;
        int32 newHeight = event.Data2;
        OnResize(newWidth, newHeight);
    }
    else if (event.Type == .CloseRequested)
    {
        shell.RequestExit();
    }
});
```

## Keyboard Input

### IKeyboard API

```beef
interface IKeyboard
{
    KeyModifiers Modifiers { get; }
    EventAccessor<KeyEventDelegate> OnKeyEvent { get; }
    EventAccessor<TextInputDelegate> OnTextInput { get; }

    bool IsKeyDown(KeyCode key);     // Currently pressed
    bool IsKeyPressed(KeyCode key);  // Just pressed this frame
    bool IsKeyReleased(KeyCode key); // Just released this frame
}
```

### Key State Polling

```beef
let keyboard = shell.InputManager.Keyboard;

// Check current state
if (keyboard.IsKeyDown(.W))
    MoveForward();

// Check for press this frame (good for toggles)
if (keyboard.IsKeyPressed(.Space))
    Jump();

// Check modifiers
if (keyboard.Modifiers.HasFlag(.Ctrl) && keyboard.IsKeyPressed(.S))
    Save();
```

### Key Events

```beef
keyboard.OnKeyEvent.Subscribe(new (key, down) => {
    if (down)
        Console.WriteLine($"Key pressed: {key}");
    else
        Console.WriteLine($"Key released: {key}");
});

// Text input (for text fields)
keyboard.OnTextInput.Subscribe(new (text) => {
    textField.Append(text);
});
```

### KeyCode (Common Keys)

```beef
enum KeyCode
{
    // Letters
    A, B, C, ..., Z,

    // Numbers
    Num0, Num1, ..., Num9,

    // Function keys
    F1, F2, ..., F24,

    // Navigation
    Left, Right, Up, Down,
    Home, End, PageUp, PageDown,

    // Special
    Return, Escape, Backspace, Tab, Space,
    CapsLock, LeftShift, RightShift,
    LeftCtrl, RightCtrl, LeftAlt, RightAlt,

    // Keypad
    KpNum0, ..., KpNum9,
    KpEnter, KpPlus, KpMinus, KpMultiply, KpDivide
}
```

### KeyModifiers

```beef
[Flags]
enum KeyModifiers
{
    None,
    LeftShift, RightShift, Shift,    // Combined
    LeftCtrl, RightCtrl, Ctrl,       // Combined
    LeftAlt, RightAlt, Alt,          // Combined
    LeftGui, RightGui, Gui,          // Combined (Win/Cmd key)
    NumLock, CapsLock, ScrollLock
}
```

## Mouse Input

### IMouse API

```beef
interface IMouse
{
    float X { get; }
    float Y { get; }
    float DeltaX { get; }
    float DeltaY { get; }
    float ScrollX { get; }
    float ScrollY { get; }
    bool RelativeMode { get; set; }  // Capture mode
    bool Visible { get; set; }
    CursorType Cursor { get; set; }

    EventAccessor<MouseMoveDelegate> OnMove { get; }
    EventAccessor<MouseButtonDelegate> OnButton { get; }
    EventAccessor<MouseScrollDelegate> OnScroll { get; }

    bool IsButtonDown(MouseButton button);
    bool IsButtonPressed(MouseButton button);
    bool IsButtonReleased(MouseButton button);
}
```

### Mouse State Polling

```beef
let mouse = shell.InputManager.Mouse;

// Position
float mouseX = mouse.X;
float mouseY = mouse.Y;

// Movement (for camera control)
float deltaX = mouse.DeltaX;
float deltaY = mouse.DeltaY;

// Scroll
float scroll = mouse.ScrollY;

// Buttons
if (mouse.IsButtonDown(.Left))
    OnDrag();

if (mouse.IsButtonPressed(.Right))
    ShowContextMenu();
```

### Relative Mode (FPS Camera)

```beef
// Enable for FPS-style camera
mouse.RelativeMode = true;
mouse.Visible = false;

// In update loop
float lookX = mouse.DeltaX * sensitivity;
float lookY = mouse.DeltaY * sensitivity;
camera.Rotate(lookX, lookY);

// Disable when done
mouse.RelativeMode = false;
mouse.Visible = true;
```

### Cursor Types

```beef
enum CursorType
{
    Default,
    Text,
    Wait,
    Crosshair,
    Progress,
    ResizeNWSE, ResizeNESW, ResizeEW, ResizeNS,
    ResizeNW, ResizeN, ResizeNE, ResizeE,
    ResizeSE, ResizeS, ResizeSW, ResizeW,
    Move,
    NotAllowed,
    Pointer
}

// Change cursor
mouse.Cursor = .Text;      // Text input
mouse.Cursor = .Pointer;   // Clickable link
mouse.Cursor = .Default;   // Normal arrow
```

### MouseButton

```beef
enum MouseButton
{
    Left,
    Middle,
    Right,
    X1,
    X2
}
```

## Gamepad Input

### IGamepad API

```beef
interface IGamepad
{
    int Index { get; }
    StringView Name { get; }
    bool Connected { get; }

    bool IsButtonDown(GamepadButton button);
    bool IsButtonPressed(GamepadButton button);
    bool IsButtonReleased(GamepadButton button);
    float GetAxis(GamepadAxis axis);
    void SetRumble(float lowFreq, float highFreq, uint32 durationMs);
}
```

### Gamepad Enumeration

```beef
for (int i = 0; i < shell.InputManager.GamepadCount; i++)
{
    let gamepad = shell.InputManager.GetGamepad(i);
    if (gamepad != null && gamepad.Connected)
    {
        Console.WriteLine($"Gamepad {i}: {gamepad.Name}");
    }
}
```

### Gamepad State

```beef
let gamepad = shell.InputManager.GetGamepad(0);
if (gamepad == null || !gamepad.Connected)
    return;

// Face buttons (Xbox layout)
if (gamepad.IsButtonPressed(.South))  // A
    Jump();
if (gamepad.IsButtonDown(.East))      // B
    Sprint();

// Sticks (-1 to 1)
float leftX = gamepad.GetAxis(.LeftX);
float leftY = gamepad.GetAxis(.LeftY);
MovePlayer(leftX, leftY);

float rightX = gamepad.GetAxis(.RightX);
float rightY = gamepad.GetAxis(.RightY);
RotateCamera(rightX, rightY);

// Triggers (0 to 1)
float leftTrigger = gamepad.GetAxis(.LeftTrigger);
float rightTrigger = gamepad.GetAxis(.RightTrigger);

// D-pad
if (gamepad.IsButtonPressed(.DPadUp))
    SelectPrevious();

// Rumble
gamepad.SetRumble(0.5f, 0.5f, 200);  // 200ms rumble
```

### GamepadButton

```beef
enum GamepadButton
{
    // Face buttons (Xbox: A, B, X, Y)
    South, East, West, North,

    // Stick clicks
    LeftStick, RightStick,

    // Shoulders
    LeftShoulder, RightShoulder,

    // D-pad
    DPadUp, DPadDown, DPadLeft, DPadRight,

    // Special
    Back, Guide, Start,

    // Paddles (elite controllers)
    RightPaddle1, RightPaddle2, LeftPaddle1, LeftPaddle2,

    Touchpad, Misc1
}
```

### GamepadAxis

```beef
enum GamepadAxis
{
    LeftX, LeftY,       // Left stick (-1 to 1)
    RightX, RightY,     // Right stick (-1 to 1)
    LeftTrigger,        // LT (0 to 1)
    RightTrigger        // RT (0 to 1)
}
```

## Touch Input

### ITouch API

```beef
interface ITouch
{
    int TouchCount { get; }
    bool HasTouch { get; }

    EventAccessor<TouchEventDelegate> OnTouchDown { get; }
    EventAccessor<TouchEventDelegate> OnTouchUp { get; }
    EventAccessor<TouchEventDelegate> OnTouchMove { get; }

    bool GetTouchPoint(int index, out TouchPoint point);
}
```

### TouchPoint

```beef
struct TouchPoint
{
    uint64 ID;      // Unique finger ID
    float X, Y;     // Position
    float Pressure; // 0.0 to 1.0
}
```

### Touch Events

```beef
let touch = shell.InputManager.Touch;

touch.OnTouchDown.Subscribe(new (point) => {
    Console.WriteLine($"Touch down: ID={point.ID} at ({point.X}, {point.Y})");
});

touch.OnTouchMove.Subscribe(new (point) => {
    // Handle drag
});

touch.OnTouchUp.Subscribe(new (point) => {
    Console.WriteLine($"Touch up: ID={point.ID}");
});
```

### Touch Polling

```beef
for (int i = 0; i < touch.TouchCount; i++)
{
    TouchPoint point;
    if (touch.GetTouchPoint(i, out point))
    {
        DrawTouchIndicator(point.X, point.Y, point.Pressure);
    }
}
```

## Clipboard

```beef
interface IClipboard
{
    bool HasText { get; }
    Result<void> GetText(String outText);
    Result<void> SetText(StringView text);
}

// Usage
if (shell.Clipboard.HasText)
{
    let text = scope String();
    if (shell.Clipboard.GetText(text) case .Ok)
        textField.Paste(text);
}

shell.Clipboard.SetText("Copied text");
```

## Input Models

The library supports two input models:

### 1. Polling (Frame-based)

Best for games with continuous input:

```beef
// In update loop
if (keyboard.IsKeyDown(.W))
    MoveForward(deltaTime);

if (mouse.IsButtonDown(.Left))
    FireWeapon();
```

### 2. Events (Callback-based)

Best for UI and discrete actions:

```beef
keyboard.OnKeyEvent.Subscribe(new (key, down) => {
    if (key == .Return && down)
        SubmitForm();
});

mouse.OnButton.Subscribe(new (button, down) => {
    if (button == .Left && down)
        HandleClick(mouse.X, mouse.Y);
});
```

### Frame Timing

- `ProcessEvents()` must be called once per frame
- Updates "pressed" and "released" states
- Resets delta values
- Fires subscribed event callbacks

## Native Handle

For RHI integration, get the platform window handle:

```beef
void* hwnd = window.NativeHandle;  // HWND on Windows

// Use for RHI surface creation
rhiDevice.CreateSurface(hwnd, width, height);
```

## Best Practices

1. **Call ProcessEvents() every frame** - Required for input updates
2. **Use IsKeyPressed for toggles** - Not IsKeyDown
3. **Check gamepad.Connected** - Controllers may disconnect
4. **Use RelativeMode for FPS** - Captures and hides cursor
5. **Subscribe to OnTextInput for text** - Not OnKeyEvent
6. **Handle CloseRequested** - Allow graceful shutdown
7. **Use defer for cleanup** - Ensures Shutdown() is called

## Project Structure

```
Code/Sedulous/Sedulous.Shell/src/
├── IShell.bf              - Main shell interface
├── IWindowManager.bf      - Window management
├── IWindow.bf             - Window interface
├── WindowSettings.bf      - Window creation options
├── WindowState.bf         - Window state enum
├── WindowEvent.bf         - Window event struct
├── WindowEventType.bf     - Event type enum
├── IClipboard.bf          - Clipboard interface
└── Input/
    ├── IInputManager.bf   - Input coordinator
    ├── IKeyboard.bf       - Keyboard interface
    ├── IMouse.bf          - Mouse interface
    ├── IGamepad.bf        - Gamepad interface
    ├── ITouch.bf          - Touch interface
    ├── KeyCode.bf         - Key codes enum
    ├── KeyModifiers.bf    - Modifier flags
    ├── MouseButton.bf     - Mouse button enum
    ├── GamepadButton.bf   - Gamepad button enum
    ├── GamepadAxis.bf     - Gamepad axis enum
    ├── CursorType.bf      - Cursor type enum
    └── TouchPoint.bf      - Touch point struct

Code/Sedulous/Sedulous.Shell.SDL3/src/
├── SDL3Shell.bf           - SDL3 implementation
├── SDL3WindowManager.bf
├── SDL3Window.bf
├── SDL3InputManager.bf
├── SDL3Keyboard.bf
├── SDL3Mouse.bf
├── SDL3Gamepad.bf
└── SDL3Touch.bf
```
