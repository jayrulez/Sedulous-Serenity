# ShellSample

Demonstrates the Sedulous shell system for windowing and input handling.

## Features

- Window creation with SDL3
- Keyboard input events (key press/release, text input)
- Mouse input events (movement, buttons, scroll wheel)
- Touch input events (down, up, move)
- Gamepad input polling
- Window events (resize, move)

## Controls

| Input | Action |
|-------|--------|
| Escape | Exit application |
| Any key | Prints key event to console |
| Mouse buttons | Prints button events to console |
| Scroll wheel | Prints scroll events to console |
| Gamepad buttons | Prints button events to console |

## Technical Details

- Uses `SDL3Shell` implementation
- Demonstrates event subscription pattern via `OnKeyEvent`, `OnTextInput`, etc.
- Shows polling-based input checking with `IsKeyPressed()`
- Supports multiple gamepads

## Dependencies

- Sedulous.Shell
- Sedulous.Shell.SDL3
