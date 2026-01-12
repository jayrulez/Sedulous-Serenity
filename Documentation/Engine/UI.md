# Sedulous.Engine.UI

Engine-level integration for UI rendering. Provides scene components for screen-space overlay UI and world-space UI panels, with automatic input routing from the engine's input system.

## Overview

```
Sedulous.Engine.UI                - Engine integration layer
├── UISceneComponent              - Screen-space overlay UI per scene
├── UIComponent                   - World-space UI on entities
└── InputMapping                  - Shell → UI input type conversion
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                          Scene                                   │
│  └── UISceneComponent (screen-space overlay)                    │
│      ├── UIContext (root UI tree)                               │
│      ├── DrawContext (2D geometry batching)                     │
│      ├── UIRenderer (GPU rendering)                             │
│      └── Input routing from InputService                        │
├─────────────────────────────────────────────────────────────────┤
│                         Entities                                 │
│  └── Entity                                                     │
│      ├── Transform (Position, Rotation, Scale)                  │
│      └── UIComponent (world-space UI panel)                     │
│          ├── UIContext (isolated UI tree)                       │
│          ├── DrawContext                                        │
│          └── Render-to-texture                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Quick Start

### Screen-Space UI

```beef
// 1. Get scene's UI component (auto-created with scene)
let scene = context.SceneManager.CreateScene("Main");
let uiComponent = scene.GetSceneComponent<UISceneComponent>();

// 2. Initialize rendering
uiComponent.InitializeRendering(device, .BGRA8Unorm, frameCount: 2);
uiComponent.SetAtlasTexture(fontAtlasView);
uiComponent.SetWhitePixelUV(.(0, 0));  // For solid color rendering

// 3. Register services
uiComponent.UIContext.RegisterService<IFontService>(fontService);
uiComponent.UIContext.SetTheme(new DarkTheme());

// 4. Build UI
let root = new DockPanel();
root.Background = Color(30, 30, 40);

let header = new StackPanel();
header.Orientation = .Horizontal;
header.Background = Color(50, 50, 70);
header.Padding = Thickness(10, 5);
root.SetDock(header, .Top);
root.AddChild(header);

let title = new TextBlock("My Game");
title.Foreground = Color.White;
header.AddChild(title);

uiComponent.RootElement = root;

// Input is automatically routed from InputService
```

### World-Space UI

```beef
// Create entity with world-space UI panel
let entity = scene.CreateEntity("HealthBar");
entity.Transform.Position = .(0, 2, 0);

let uiPanel = new UIComponent();
uiPanel.WorldSize = .(1.0f, 0.2f);      // 1m x 0.2m in world
uiPanel.TextureSize = .(256, 64);       // Render texture resolution
uiPanel.Orientation = .Billboard;       // Face camera
entity.AddComponent(uiPanel);

// Build UI for this panel
let bar = new ProgressBar();
bar.Width = .Fill;
bar.Height = .Fill;
bar.Value = 75;
uiPanel.RootElement = bar;
```

## UISceneComponent

Per-scene component managing screen-space overlay UI.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `UIContext` | `UIContext` | The UI context for this scene |
| `RootElement` | `UIElement` | Root of the UI tree |
| `Width` | `uint32` | Current viewport width |
| `Height` | `uint32` | Current viewport height |
| `IsRenderingInitialized` | `bool` | Whether GPU resources are ready |

### Methods

```beef
// Initialize GPU rendering
Result<void> InitializeRendering(IDevice device, TextureFormat format, int32 frameCount);

// Set texture atlas for fonts/icons
void SetAtlasTexture(ITextureView atlasView);
void SetWhitePixelUV(Vector2 uv);

// Resize viewport
void SetViewportSize(uint32 width, uint32 height);

// Render the UI (called by render graph)
void Render(IRenderPassEncoder renderPass, int32 frameIndex);

// Manual input routing (usually automatic)
void ProcessMouseMove(float x, float y);
void ProcessMouseDown(MouseButton button, float x, float y);
void ProcessMouseUp(MouseButton button, float x, float y);
void ProcessMouseWheel(float deltaX, float deltaY, float x, float y);
void ProcessKeyDown(KeyCode key, int32 scanCode, KeyModifiers modifiers);
void ProcessKeyUp(KeyCode key, int32 scanCode, KeyModifiers modifiers);
void ProcessTextInput(char32 character);
```

### Input Routing

UISceneComponent automatically subscribes to InputService events:

```
InputService                    UISceneComponent
────────────────────────────────────────────────
OnMouseMove        →    ProcessMouseMove
OnMouseButtonDown  →    ProcessMouseDown
OnMouseButtonUp    →    ProcessMouseUp
OnMouseWheel       →    ProcessMouseWheel
OnKeyDown          →    ProcessKeyDown
OnKeyUp            →    ProcessKeyUp
OnTextInput        →    ProcessTextInput
```

Input types are mapped from Shell types to UI types via `InputMapping`.

## UIComponent

Entity component for world-space UI panels. Each component has its own isolated UIContext.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `UIContext` | `UIContext` | Isolated UI context |
| `RootElement` | `UIElement` | Root of the UI tree |
| `Orientation` | `WorldUIOrientation` | Billboard or Fixed |
| `WorldSize` | `Vector2` | Panel size in world units |
| `TextureSize` | `Vector2` | Render texture resolution |
| `Visible` | `bool` | Panel visibility |

### World UI Orientations

| Orientation | Description |
|-------------|-------------|
| `Billboard` | Panel always faces the camera |
| `Fixed` | Panel uses the entity's rotation |

### Example: Floating Name Tag

```beef
let entity = scene.CreateEntity("NPC");
entity.Transform.Position = npcPosition;

let nameTag = new UIComponent();
nameTag.WorldSize = .(2.0f, 0.3f);
nameTag.TextureSize = .(512, 64);
nameTag.Orientation = .Billboard;
entity.AddComponent(nameTag);

let panel = new Border();
panel.Background = Color(0, 0, 0, 180);
panel.CornerRadius = 4;
panel.Padding = Thickness(10, 5);

let text = new TextBlock("Guard Captain");
text.Foreground = Color.White;
text.HorizontalAlignment = .Center;
panel.AddChild(text);

nameTag.RootElement = panel;
```

### Example: In-World Control Panel

```beef
let console = scene.CreateEntity("Console");
console.Transform.Position = consolePosition;
console.Transform.Rotation = consoleRotation;

let panel = new UIComponent();
panel.WorldSize = .(0.5f, 0.4f);    // 50cm x 40cm physical panel
panel.TextureSize = .(512, 410);     // ~1:1 pixel density
panel.Orientation = .Fixed;          // Uses entity rotation
console.AddComponent(panel);

// Build interactive UI
let root = new StackPanel();
root.Orientation = .Vertical;
root.Spacing = 10;
root.Padding = Thickness(15);
root.Background = Color(20, 30, 40);

let slider = new Slider();
slider.Width = .Fill;
slider.Minimum = 0;
slider.Maximum = 100;
root.AddChild(slider);

let button = new Button();
button.ContentText = "Activate";
button.Click.Subscribe(new (s) => ActivateConsole());
root.AddChild(button);

panel.RootElement = root;
```

## Input Mapping

Converts Shell input types to UI input types.

```beef
// Key mapping
Sedulous.UI.KeyCode uiKey = InputMapping.MapKey(shellKey);

// Modifier mapping
Sedulous.UI.KeyModifiers uiMods = InputMapping.MapModifiers(shellMods);

// Mouse button mapping
Sedulous.UI.MouseButton uiButton = InputMapping.MapMouseButton(shellButton);
```

### Supported Keys

Common keys are mapped: A-Z, 0-9, Arrow keys, Home, End, PageUp, PageDown, Delete, Insert, Tab, Return, Escape, Backspace, Space.

### Supported Modifiers

| Shell Modifier | UI Modifier |
|----------------|-------------|
| `Shift` | `Shift` |
| `Ctrl` | `Ctrl` |
| `Alt` | `Alt` |

## Render Graph Integration

UISceneComponent registers itself with the render graph:

```beef
// In your render setup
let renderGraph = rendererService.RenderGraph;

// UI pass is added automatically after main scene pass
// Renders screen-space UI as overlay

// World UI is rendered as part of the sprite pass
// (UIComponent creates sprite proxies for render-to-texture results)
```

## Sample Usage

```beef
class GameUI
{
    private UISceneComponent mUIScene;
    private UIComponent mHealthBar;
    private TextBlock mScoreText;
    private ProgressBar mHealthProgress;

    public void Initialize(Scene scene, IDevice device, IFontService fontService)
    {
        // Setup screen-space UI
        mUIScene = scene.GetSceneComponent<UISceneComponent>();
        mUIScene.InitializeRendering(device, .BGRA8Unorm, 2);
        mUIScene.UIContext.RegisterService<IFontService>(fontService);
        mUIScene.UIContext.SetTheme(new GameTheme());

        BuildHUD();

        // Setup world-space health bar on player
        let player = scene.FindEntity("Player");
        SetupHealthBar(player);
    }

    private void BuildHUD()
    {
        let root = new DockPanel();

        // Score in top-right
        mScoreText = new TextBlock("Score: 0");
        mScoreText.HorizontalAlignment = .Right;
        mScoreText.Margin = Thickness(0, 10, 20, 0);
        root.SetDock(mScoreText, .Top);
        root.AddChild(mScoreText);

        // Health bar bottom-left
        let healthPanel = new StackPanel();
        healthPanel.Orientation = .Horizontal;
        healthPanel.Margin = Thickness(20, 0, 0, 20);
        healthPanel.Spacing = 10;
        root.SetDock(healthPanel, .Bottom);

        let healthLabel = new TextBlock("HP:");
        healthLabel.VerticalAlignment = .Center;
        healthPanel.AddChild(healthLabel);

        mHealthProgress = new ProgressBar();
        mHealthProgress.Width = 200;
        mHealthProgress.Height = 20;
        mHealthProgress.Maximum = 100;
        mHealthProgress.Value = 100;
        healthPanel.AddChild(mHealthProgress);

        root.AddChild(healthPanel);

        mUIScene.RootElement = root;
    }

    private void SetupHealthBar(Entity player)
    {
        // Add world-space health bar above player
        mHealthBar = new UIComponent();
        mHealthBar.WorldSize = .(1.0f, 0.15f);
        mHealthBar.TextureSize = .(256, 32);
        mHealthBar.Orientation = .Billboard;
        player.AddComponent(mHealthBar);

        let bar = new ProgressBar();
        bar.Width = .Fill;
        bar.Height = .Fill;
        bar.Maximum = 100;
        bar.Value = 100;
        mHealthBar.RootElement = bar;
    }

    public void UpdateScore(int score)
    {
        mScoreText.Text = scope $"Score: {score}";
    }

    public void UpdateHealth(float health)
    {
        mHealthProgress.Value = health;

        // Update world health bar too
        if (mHealthBar?.RootElement != null)
        {
            if (let bar = mHealthBar.RootElement as ProgressBar)
                bar.Value = health;
        }
    }
}
```

## Dependencies

```
Sedulous.Engine.UI
├── Sedulous.Engine.Core      - Entity/component system
├── Sedulous.Engine.Input     - Input routing
├── Sedulous.Engine.Renderer  - Render integration
├── Sedulous.UI               - Core UI framework
├── Sedulous.UI.Renderer      - GPU rendering
├── Sedulous.Drawing          - 2D drawing primitives
├── Sedulous.RHI              - Graphics abstraction
└── Sedulous.Mathematics      - Math types
```
