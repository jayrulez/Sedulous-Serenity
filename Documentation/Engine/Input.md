# Sedulous.Engine.Input

High-level input framework that abstracts physical inputs (keyboard, mouse, gamepad) into named actions with support for multiple bindings, runtime remapping, input contexts, and serialization.

## Overview

```
Sedulous.Shell.Input      - Low-level input polling (keyboard, mouse, gamepad)
Sedulous.Engine.Input     - High-level action-based input system
```

The Engine Input layer sits above Shell Input and provides:

- **Named Actions**: "Jump", "Fire", "Move" instead of raw key codes
- **Multiple Bindings**: Space OR Gamepad A both trigger "Jump"
- **Input Contexts**: Different bindings for gameplay vs. menu
- **Value Types**: Boolean (buttons), float (triggers), Vector2 (sticks/WASD)
- **Polling & Callbacks**: Query state or receive events
- **Serialization**: Save/load user bindings

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                     APPLICATION LAYER                                │
│                   (Samples, Game Code)                               │
├─────────────────────────────────────────────────────────────────────┤
│  Query actions:                                                      │
│    inputService.GetAction("Jump").WasPressed                        │
│    inputService.GetAction("Move").Vector2Value                      │
│  Register callbacks:                                                 │
│    context.OnAction("Fire", (a) => Shoot());                        │
├─────────────────────────────────────────────────────────────────────┤
│                     ENGINE INPUT LAYER                               │
│                  (Sedulous.Engine.Input)                             │
├─────────────────────────────────────────────────────────────────────┤
│  InputService : IContextService                                      │
│  ├── InputContext[] (priority stack)                                │
│  │   ├── InputAction "Jump"                                         │
│  │   │   ├── KeyBinding(Space)                                      │
│  │   │   └── GamepadButtonBinding(South)                            │
│  │   └── InputAction "Move"                                         │
│  │       ├── CompositeBinding(WASD)                                 │
│  │       └── GamepadStickBinding(LeftStick)                         │
│  └── UIConsumedInput flag                                           │
├─────────────────────────────────────────────────────────────────────┤
│                      SHELL INPUT LAYER                               │
│                   (Sedulous.Shell.Input)                             │
├─────────────────────────────────────────────────────────────────────┤
│  IInputManager                                                       │
│  ├── IKeyboard (IsKeyDown, IsKeyPressed, IsKeyReleased)             │
│  ├── IMouse (position, buttons, scroll)                             │
│  ├── IGamepad[] (buttons, axes, rumble)                             │
│  └── ITouch (touch points)                                          │
└─────────────────────────────────────────────────────────────────────┘
```

## Core Types

| Type | Purpose |
|------|---------|
| `InputService` | IContextService that manages contexts and actions. |
| `InputContext` | Named context with actions (e.g., "Gameplay", "Menu"). |
| `InputAction` | Named action with multiple bindings. |
| `InputValue` | Unified value struct (bool, float, Vector2). |
| `InputBinding` | Abstract base for all binding types. |

## Basic Setup

```beef
// Create shell and window
let shell = new SDL3Shell();
shell.Initialize();
shell.WindowManager.CreateWindow(.Default);

// Create engine context
let context = new Context(null, 1);

// Create and register input service
let inputService = new InputService(shell.InputManager);
context.RegisterService<InputService>(inputService);

// Create gameplay context and register actions
let gameplay = inputService.CreateContext("Gameplay", priority: 0);

// Jump: Space or Gamepad A
let jump = gameplay.RegisterAction("Jump");
jump.AddBinding(new KeyBinding(.Space));
jump.AddBinding(new GamepadButtonBinding(.South));

// Move: WASD or left stick
let move = gameplay.RegisterAction("Move");
move.AddBinding(new CompositeBinding(.W, .S, .A, .D));
move.AddBinding(new GamepadStickBinding(.Left));

// Start context (required!)
context.Startup();

// Main loop
while (shell.IsRunning)
{
    shell.ProcessEvents();
    context.Update(deltaTime);
    ProcessInput(inputService);
}

context.Shutdown();
```

## Polling Actions

```beef
void ProcessInput(InputService input)
{
    // Skip if UI consumed input
    if (input.UIConsumedInput)
        return;

    // Button press (fires once)
    let jump = input.GetAction("Jump");
    if (jump != null && jump.WasPressed)
        player.Jump();

    // Button held
    let sprint = input.GetAction("Sprint");
    if (sprint != null && sprint.IsActive)
        speed *= 2.0f;

    // 2D movement
    let move = input.GetAction("Move");
    if (move != null)
    {
        let dir = move.Vector2Value;
        position += forward * dir.Y + right * dir.X;
    }

    // Analog value (trigger)
    let fire = input.GetAction("Fire");
    if (fire != null && fire.Value > 0.5f)
        Shoot();
}
```

## Callbacks

```beef
// Register callback (fires on WasPressed)
gameplay.OnAction("Jump", new (action) => {
    Console.WriteLine("JUMP!");
    player.Jump();
});

// Toggle mouse capture
gameplay.OnAction("ToggleCapture", new (action) => {
    captured = !captured;
    mouse.RelativeMode = captured;
    mouse.Visible = !captured;
});
```

## InputAction Properties

| Property | Type | Description |
|----------|------|-------------|
| `IsActive` | bool | Currently held (button down or axis > 0.5) |
| `WasPressed` | bool | Just pressed this frame |
| `WasReleased` | bool | Just released this frame |
| `Value` | float | Primary axis value (0-1 for triggers) |
| `Vector2Value` | Vector2 | 2D value (sticks, WASD composite) |
| `RawValue` | InputValue | Raw unified value |

## Binding Types

### KeyBinding

Single keyboard key with optional modifiers.

```beef
// Simple key
let jump = new KeyBinding(.Space);

// With modifiers
let save = new KeyBinding(.S);
save.RequiredModifiers = .Ctrl;
```

### MouseButtonBinding

Mouse button (left, right, middle, X1, X2).

```beef
let fire = new MouseButtonBinding(.Left);
let altFire = new MouseButtonBinding(.Right);
```

### MouseAxisBinding

Mouse movement or scroll.

```beef
// Delta movement (for look control)
let look = new MouseAxisBinding(.Delta, sensitivity: 1.0f);

// Scroll wheel
let scroll = new MouseAxisBinding(.ScrollY, sensitivity: 0.1f);
```

### CompositeBinding

Four keys mapped to Vector2 (WASD-style).

```beef
// WASD movement
let wasd = new CompositeBinding(.W, .S, .A, .D);  // up, down, left, right

// Arrow keys
let arrows = new CompositeBinding(.Up, .Down, .Left, .Right);
```

### GamepadButtonBinding

Gamepad face buttons, shoulders, d-pad, etc.

```beef
let jump = new GamepadButtonBinding(.South);      // A button
let sprint = new GamepadButtonBinding(.East);     // B button
let menu = new GamepadButtonBinding(.Start);
```

### GamepadAxisBinding

Single gamepad axis (triggers or individual stick axis).

```beef
// Trigger (0 to 1)
let fire = new GamepadAxisBinding(.RightTrigger);
fire.DeadZone = 0.1f;

// Single stick axis
let horizontal = new GamepadAxisBinding(.LeftX);
```

### GamepadStickBinding

Full analog stick as Vector2.

```beef
// Left stick for movement
let move = new GamepadStickBinding(.Left);
move.DeadZone = 0.15f;

// Right stick for camera
let look = new GamepadStickBinding(.Right);
look.Sensitivity = 2.0f;
look.InvertY = true;
```

## Input Contexts

Contexts group related actions and can be enabled/disabled.

```beef
// Create contexts with priority (higher = processed first)
let gameplay = inputService.CreateContext("Gameplay", priority: 0);
let pauseMenu = inputService.CreateContext("PauseMenu", priority: 10);

// Pause menu blocks gameplay input when active
pauseMenu.BlocksInput = true;
pauseMenu.Enabled = false;

// Register pause menu actions
pauseMenu.RegisterAction("Resume").AddBinding(new KeyBinding(.Escape));
pauseMenu.OnAction("Resume", new (a) => ClosePauseMenu());

// Open pause menu
void OpenPauseMenu()
{
    pauseMenu.Enabled = true;
}

// Close pause menu
void ClosePauseMenu()
{
    pauseMenu.Enabled = false;
}
```

### Context Priority

- Higher priority contexts are updated first
- `BlocksInput = true` prevents lower-priority contexts from receiving input
- Use for modal dialogs, pause menus, etc.

## UI Integration

The `UIConsumedInput` flag coordinates with UI systems:

```beef
// UI sets this when it handles input
if (uiContext.ProcessMouseDown())
{
    inputService.UIConsumedInput = true;
}

// Game code checks before processing
void ProcessGameInput()
{
    if (inputService.UIConsumedInput)
        return;  // UI handled it

    // Process game input...
}
```

The flag is automatically reset to `false` at the start of each `Update()`.

## Runtime Rebinding

```beef
// Get the action to rebind
let jumpAction = inputService.GetContext("Gameplay").GetAction("Jump");

// Clear existing bindings
jumpAction.ClearBindings();

// Add new binding from user selection
jumpAction.AddBinding(new KeyBinding(userSelectedKey));
```

## Serialization

Save and load user bindings:

```beef
// Save bindings
let bindingsFile = new InputBindingsFile();
bindingsFile.SaveFromService(inputService);
// ... write to file using serialization ...

// Load bindings
// ... read from file ...
bindingsFile.ApplyToService(inputService);
```

## InputValue

Unified value type for all inputs:

```beef
struct InputValue
{
    public float X, Y;

    // Conversions
    public bool AsBool => X > 0.5f;
    public float AsFloat => X;
    public Vector2 AsVector2 => .(X, Y);

    // Factory methods
    public static InputValue FromBool(bool value);
    public static InputValue FromFloat(float value);
    public static InputValue FromVector2(Vector2 value);
    public static InputValue Zero;
}
```

## Complete Example

```beef
using System;
using Sedulous.Shell;
using Sedulous.Shell.SDL3;
using Sedulous.Engine.Core;
using Sedulous.Engine.Input;

class Game
{
    IShell mShell;
    Context mContext;
    InputService mInputService;
    Vector3 mPosition;
    float mYaw, mPitch;
    bool mMouseCaptured;

    public void Run()
    {
        // Initialize
        mShell = new SDL3Shell();
        mShell.Initialize();
        mShell.WindowManager.CreateWindow(.Default);

        mContext = new Context(null, 1);
        mInputService = new InputService(mShell.InputManager);
        mContext.RegisterService<InputService>(mInputService);

        SetupInput();
        mContext.Startup();

        // Main loop
        while (mShell.IsRunning)
        {
            mShell.ProcessEvents();

            if (mShell.InputManager.Keyboard.IsKeyPressed(.Escape))
                mShell.RequestExit();

            mContext.Update(0.016f);
            ProcessInput();
        }

        // Cleanup
        mContext.Shutdown();
        delete mInputService;
        delete mContext;
        mShell.Shutdown();
        delete mShell;
    }

    void SetupInput()
    {
        let ctx = mInputService.CreateContext("Gameplay", 0);

        // Movement
        let move = ctx.RegisterAction("Move");
        move.AddBinding(new CompositeBinding(.W, .S, .A, .D));
        move.AddBinding(new GamepadStickBinding(.Left));

        // Look
        let look = ctx.RegisterAction("Look");
        look.AddBinding(new MouseAxisBinding(.Delta, 1.0f));
        let stick = new GamepadStickBinding(.Right);
        stick.Sensitivity = 2.0f;
        look.AddBinding(stick);

        // Jump
        let jump = ctx.RegisterAction("Jump");
        jump.AddBinding(new KeyBinding(.Space));
        jump.AddBinding(new GamepadButtonBinding(.South));
        ctx.OnAction("Jump", new (a) => Console.WriteLine("JUMP!"));

        // Fire
        let fire = ctx.RegisterAction("Fire");
        fire.AddBinding(new MouseButtonBinding(.Left));
        fire.AddBinding(new GamepadAxisBinding(.RightTrigger));

        // Toggle capture
        let toggle = ctx.RegisterAction("ToggleCapture");
        toggle.AddBinding(new KeyBinding(.Tab));
        ctx.OnAction("ToggleCapture", new (a) => {
            mMouseCaptured = !mMouseCaptured;
            mShell.InputManager.Mouse.RelativeMode = mMouseCaptured;
            mShell.InputManager.Mouse.Visible = !mMouseCaptured;
        });
    }

    void ProcessInput()
    {
        let dt = 0.016f;
        let speed = 5.0f;

        // Movement
        let move = mInputService.GetAction("Move");
        if (move != null)
        {
            let dir = move.Vector2Value;
            mPosition.Z += dir.Y * speed * dt;
            mPosition.X += dir.X * speed * dt;
        }

        // Look (when captured)
        if (mMouseCaptured)
        {
            let look = mInputService.GetAction("Look");
            if (look != null)
            {
                let delta = look.Vector2Value;
                mYaw -= delta.X * 0.003f;
                mPitch -= delta.Y * 0.003f;
            }
        }

        // Fire
        let fire = mInputService.GetAction("Fire");
        if (fire != null && fire.WasPressed)
            Console.WriteLine("FIRE!");
    }
}
```

## Project Structure

```
Code/Sedulous/Sedulous.Engine.Input/
├── BeefProj.toml
└── src/
    ├── InputService.bf           - IContextService, main entry point
    ├── InputContext.bf           - Context with actions and callbacks
    ├── InputAction.bf            - Named action with bindings
    ├── InputValue.bf             - Unified value struct
    ├── Bindings/
    │   ├── InputBinding.bf       - Abstract base
    │   ├── KeyBinding.bf         - Keyboard key
    │   ├── MouseButtonBinding.bf - Mouse button
    │   ├── MouseAxisBinding.bf   - Mouse delta/scroll
    │   ├── GamepadButtonBinding.bf
    │   ├── GamepadAxisBinding.bf
    │   ├── GamepadStickBinding.bf
    │   └── CompositeBinding.bf   - 4 keys -> Vector2
    └── Serialization/
        └── InputBindingsFile.bf  - Save/load bindings
```

## Dependencies

```toml
[Dependencies]
corlib = "*"
Sedulous.Engine.Core = "*"
Sedulous.Shell = "*"
Sedulous.Mathematics = "*"
Sedulous.Serialization = "*"
```

## Best Practices

1. **Call context.Startup()** - Required before Update() processes services
2. **Use WasPressed for actions** - Not IsActive for one-shot events
3. **Use IsActive for continuous** - Held buttons, sprinting
4. **Check UIConsumedInput** - Let UI have priority
5. **Use contexts for states** - Separate gameplay, menu, dialog
6. **Set BlocksInput on modals** - Prevent input bleed-through
7. **Provide multiple bindings** - Support keyboard and gamepad
8. **Use dead zones for sticks** - Filter out noise
