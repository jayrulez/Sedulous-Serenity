# Sedulous UI Framework

The Sedulous UI framework provides a retained-mode UI system for games and applications, inspired by WPF/UWP with a focus on simplicity and game-friendly features.

## Architecture

The UI system consists of several layers:

- **Sedulous.UI** - Core UI framework with elements, layouts, controls, and theming
- **Sedulous.Drawing** - 2D drawing primitives (DrawContext, batching)
- **Sedulous.Fonts** - Text rendering and measurement

## Quick Start

```beef
// Create UI context
let uiContext = new UIContext();

// Register services
uiContext.RegisterService<IFontService>(fontService);
uiContext.RegisterClipboard(clipboard);

// Set theme
uiContext.SetTheme(new DefaultTheme());

// Set viewport size
uiContext.SetViewportSize(1280, 720);

// Build UI tree
let root = new StackPanel();
root.Orientation = .Vertical;
root.Padding = Thickness(20);

let button = new Button();
button.ContentText = "Click Me";
button.Click.Subscribe(new (sender) => {
    Console.WriteLine("Button clicked!");
});
root.AddChild(button);

uiContext.RootElement = root;

// In your update loop:
uiContext.Update(deltaTime, totalTime);

// Route input:
uiContext.ProcessMouseMove(mouseX, mouseY);
uiContext.ProcessMouseDown(.Left, mouseX, mouseY);
uiContext.ProcessKeyDown(key, scanCode, modifiers);

// Render:
uiContext.Render(drawContext);
```

## UIContext

The central manager for the UI system. Owns the element tree and provides services.

### Properties

| Property | Description |
|----------|-------------|
| `RootElement` | The root of the UI tree |
| `FocusedElement` | Currently focused element |
| `HoveredElement` | Element under the mouse |
| `CapturedElement` | Element with mouse capture |
| `Scale` | UI scale factor (default 1.0, use 2.0 for HiDPI) |
| `ViewportWidth/Height` | Physical viewport size |
| `LogicalWidth/Height` | Viewport size in logical units (physical / scale) |
| `DebugSettings` | Debug visualization options |

### Methods

```beef
// Services
void RegisterService<T>(T service);
Result<T> GetService<T>();
void SetTheme(ITheme theme);

// Layout
void SetViewportSize(float width, float height);
void InvalidateLayout();
void InvalidateVisual();

// Focus
void SetFocus(UIElement element);
void CaptureMouse(UIElement element);
void ReleaseMouseCapture();

// Input (coordinates in physical pixels)
void ProcessMouseMove(float x, float y, KeyModifiers modifiers = .None);
void ProcessMouseDown(MouseButton button, float x, float y, KeyModifiers modifiers = .None);
void ProcessMouseUp(MouseButton button, float x, float y, KeyModifiers modifiers = .None);
void ProcessMouseWheel(float deltaX, float deltaY, float x, float y, KeyModifiers modifiers = .None);
void ProcessKeyDown(KeyCode key, int32 scanCode, KeyModifiers modifiers, bool isRepeat = false);
void ProcessKeyUp(KeyCode key, int32 scanCode, KeyModifiers modifiers);
void ProcessTextInput(char32 character);

// Frame update
void Update(float deltaTime, double totalTime);
void Render(DrawContext drawContext);
```

## UIElement

Base class for all UI elements. Provides layout, rendering, and input handling.

### Layout Properties

| Property | Type | Description |
|----------|------|-------------|
| `Width` | `SizeDimension` | Requested width (Fixed, Auto, Fill) |
| `Height` | `SizeDimension` | Requested height |
| `MinWidth/MaxWidth` | `float` | Size constraints |
| `MinHeight/MaxHeight` | `float` | Size constraints |
| `Margin` | `Thickness` | Space outside the element |
| `Padding` | `Thickness` | Space inside the element |
| `HorizontalAlignment` | `HorizontalAlignment` | Left, Center, Right, Stretch |
| `VerticalAlignment` | `VerticalAlignment` | Top, Center, Bottom, Stretch |

### Visual Properties

| Property | Type | Description |
|----------|------|-------------|
| `Visibility` | `Visibility` | Visible, Hidden, Collapsed |
| `Opacity` | `float` | 0.0 (transparent) to 1.0 (opaque) |
| `RenderTransform` | `Matrix` | Transform applied during rendering |
| `RenderTransformOrigin` | `Vector2` | Transform origin (0-1, default 0.5, 0.5) |
| `Cursor` | `CursorType?` | Cursor when hovering (null = inherit) |

### State Properties

| Property | Type | Description |
|----------|------|-------------|
| `IsEnabled` | `bool` | Whether element accepts input |
| `IsFocused` | `bool` | Whether element has keyboard focus |
| `IsMouseOver` | `bool` | Whether mouse is over element |
| `Focusable` | `bool` | Whether element can receive focus |

### Layout Results

| Property | Type | Description |
|----------|------|-------------|
| `DesiredSize` | `DesiredSize` | Size requested during measure |
| `Bounds` | `RectangleF` | Final bounds after arrange |
| `ContentBounds` | `RectangleF` | Bounds minus padding |

### Events

```beef
EventAccessor<delegate void(UIElement)> OnGotFocusEvent;
EventAccessor<delegate void(UIElement)> OnLostFocusEvent;
EventAccessor<delegate void(UIElement)> OnMouseEnterEvent;
EventAccessor<delegate void(UIElement)> OnMouseLeaveEvent;
EventAccessor<delegate void(UIElement, float, float)> OnMouseMoveEvent;
EventAccessor<delegate void(UIElement, int, float, float)> OnMouseDownEvent;
EventAccessor<delegate void(UIElement, int, float, float)> OnMouseUpEvent;
EventAccessor<delegate void(UIElement, float, float)> OnMouseWheelEvent;
EventAccessor<delegate void(UIElement, KeyCode, KeyModifiers)> OnKeyDownEvent;
EventAccessor<delegate void(UIElement, KeyCode, KeyModifiers)> OnKeyUpEvent;
EventAccessor<delegate void(UIElement, char32)> OnTextInputEvent;
EventAccessor<delegate void(UIElement)> OnClickEvent;
```

### Tree Manipulation

```beef
void AddChild(UIElement child);
void InsertChild(int index, UIElement child);
bool RemoveChild(UIElement child);
void ClearChildren();
UIElement FindElementById(UIElementId id);
```

## Layout System

The UI uses a two-pass layout system similar to WPF:

1. **Measure Pass** - Each element calculates its desired size
2. **Arrange Pass** - Each element is positioned within its final bounds

### SizeDimension

Specifies how an element's size is determined:

```beef
// Fixed size in logical pixels
element.Width = 200;

// Auto - size to content
element.Width = .Auto;

// Fill - stretch to available space
element.Width = .Fill;
```

### Thickness

Represents margin or padding on four sides:

```beef
// All sides equal
element.Margin = Thickness(10);

// Horizontal, Vertical
element.Margin = Thickness(10, 5);

// Left, Top, Right, Bottom
element.Margin = Thickness(10, 5, 10, 5);
```

### Alignment

Controls how elements are positioned within available space:

```beef
// Horizontal: Left, Center, Right, Stretch
element.HorizontalAlignment = .Center;

// Vertical: Top, Center, Bottom, Stretch
element.VerticalAlignment = .Top;
```

## Layout Panels

### StackPanel

Arranges children in a single line (horizontal or vertical).

```beef
let stack = new StackPanel();
stack.Orientation = .Vertical;  // or .Horizontal
stack.Spacing = 10;             // Space between children
stack.AddChild(child1);
stack.AddChild(child2);
```

### DockPanel

Docks children to edges, with the last child filling remaining space.

```beef
let dock = new DockPanel();

let header = new Border();
dock.SetDock(header, .Top);
dock.AddChild(header);

let sidebar = new Border();
dock.SetDock(sidebar, .Left);
dock.AddChild(sidebar);

let content = new Border();  // Fills remaining space
dock.AddChild(content);
```

### Grid

Arranges children in rows and columns with flexible sizing.

```beef
let grid = new Grid();

// Define rows
let row0 = new RowDefinition();
row0.Height = .Auto;              // Size to content
grid.RowDefinitions.Add(row0);

let row1 = new RowDefinition();
row1.Height = .Star;              // Fill remaining (1*)
grid.RowDefinitions.Add(row1);

let row2 = new RowDefinition();
row2.Height = GridLength.StarWeight(2);  // Fill with 2* weight
grid.RowDefinitions.Add(row2);

// Define columns
let col0 = new ColumnDefinition();
col0.Width = GridLength.Pixel(100);  // Fixed 100px
grid.ColumnDefinitions.Add(col0);

let col1 = new ColumnDefinition();
col1.Width = .Star;
grid.ColumnDefinitions.Add(col1);

// Add children
let cell = new Border();
grid.SetRow(cell, 0);
grid.SetColumn(cell, 1);
grid.SetColumnSpan(cell, 2);  // Span multiple columns
grid.AddChild(cell);
```

### Canvas

Positions children using absolute coordinates.

```beef
let canvas = new Canvas();
canvas.Width = 400;
canvas.Height = 300;

let box = new Border();
box.Width = 50;
box.Height = 50;
canvas.SetLeft(box, 100);   // or SetRight
canvas.SetTop(box, 50);     // or SetBottom
canvas.AddChild(box);
```

### WrapPanel

Arranges children in rows/columns that wrap to the next line.

```beef
let wrap = new WrapPanel();
wrap.Orientation = .Horizontal;
wrap.ItemWidth = 100;   // Optional fixed item size
wrap.ItemHeight = 50;

for (int i = 0; i < 20; i++)
{
    let item = new Border();
    wrap.AddChild(item);
}
```

### ScrollViewer

Provides scrolling for content larger than the viewport.

```beef
let scroll = new ScrollViewer();
scroll.HorizontalScrollBarVisibility = .Auto;
scroll.VerticalScrollBarVisibility = .Visible;

let content = new StackPanel();
// Add many children...
scroll.Content = content;
```

## Controls

### Control (Base Class)

Base class for interactive controls with theming support.

```beef
// Common control properties
control.Background = Color(50, 50, 50);
control.Foreground = Color.White;
control.FontFamily = "Roboto";
control.FontSize = 14;
control.CornerRadius = 4;
```

### Button

Clickable button with text or custom content.

```beef
let button = new Button();
button.ContentText = "Click Me";
button.Padding = Thickness(15, 8);
button.Click.Subscribe(new (sender) => {
    // Handle click
});
```

### TextBlock

Displays read-only text.

```beef
let text = new TextBlock();
text.Text = "Hello World";
text.TextAlignment = .Center;
text.TextWrapping = .Wrap;
text.Foreground = Color.White;
```

### TextBox

Editable text input with selection, clipboard, and cursor support.

```beef
let textBox = new TextBox();
textBox.Width = 200;
textBox.Placeholder = "Enter text...";
textBox.MaxLength = 100;
textBox.TextChanged.Subscribe(new (sender) => {
    let newText = textBox.Text;
});
```

Features:
- Text selection (mouse drag, Shift+Arrow)
- Clipboard (Ctrl+C/X/V)
- Cursor navigation (Arrow, Home, End, Ctrl+Arrow)
- Blinking cursor

### CheckBox

Toggle control with checked/unchecked state.

```beef
let checkbox = new CheckBox();
checkbox.ContentText = "Enable Feature";
checkbox.IsChecked = true;
checkbox.CheckedChanged.Subscribe(new (sender) => {
    let isChecked = checkbox.IsChecked;
});
```

### RadioButton

Mutually exclusive selection within a group.

```beef
let radio1 = new RadioButton("Option A", "myGroup");
radio1.IsChecked = true;

let radio2 = new RadioButton("Option B", "myGroup");

let radio3 = new RadioButton("Option C", "myGroup");
```

### Slider

Horizontal slider for selecting a value in a range.

```beef
let slider = new Slider();
slider.Width = 200;
slider.Minimum = 0;
slider.Maximum = 100;
slider.Value = 50;
slider.ValueChanged.Subscribe(new (sender) => {
    let value = slider.Value;
});
```

### ProgressBar

Displays progress as a filled bar.

```beef
let progress = new ProgressBar();
progress.Width = 200;
progress.Height = 20;
progress.Minimum = 0;
progress.Maximum = 100;
progress.Value = 75;
```

### Border

Container with background, border, and corner radius.

```beef
let border = new Border();
border.Background = Color(40, 40, 50);
border.BorderBrush = Color(100, 100, 120);
border.BorderThickness = Thickness(2);
border.CornerRadius = 8;
border.Padding = Thickness(10);
border.AddChild(content);
```

### ContentControl

Base class for controls that contain a single piece of content.

```beef
let content = new ContentControl();
content.Content = someUIElement;
// or
content.ContentText = "Text content";
```

## Theming

Themes provide consistent colors across controls.

### Built-in Themes

```beef
// Light theme (default)
uiContext.SetTheme(new DefaultTheme());

// Dark theme
uiContext.SetTheme(new DarkTheme());

// Game-styled theme (cyan/orange accents)
uiContext.SetTheme(new GameTheme());
```

### ITheme Interface

```beef
public interface ITheme
{
    Color? GetColor(StringView name);
}
```

### Theme Colors

| Name | Description |
|------|-------------|
| `Primary` | Primary accent color |
| `PrimaryHover` | Primary color on hover |
| `PrimaryPressed` | Primary color when pressed |
| `Secondary` | Secondary accent color |
| `Background` | Default background |
| `Surface` | Elevated surface background |
| `Foreground` | Default text color |
| `ForegroundDisabled` | Disabled text color |
| `Border` | Default border color |
| `Selection` | Text selection highlight |
| `ProgressTrack` | Progress bar track |
| `ProgressFill` | Progress bar fill |
| `SliderTrack` | Slider track |
| `SliderThumb` | Slider thumb |
| `CheckMark` | Checkbox/radio check mark |

### Using Theme Colors

```beef
// In a control
protected ITheme GetTheme()
{
    return Context?.CurrentTheme;
}

protected override void OnRender(DrawContext dc)
{
    let theme = GetTheme();
    let bg = Background ?? theme?.GetColor("Surface") ?? Color.Gray;
    dc.FillRect(Bounds, bg);
}
```

## Animation

The animation system provides property animations with easing.

### Animation Manager

```beef
// Access via context
let animations = uiContext.Animations;

// Add animation
animations.Add(myAnimation);
```

### Float Animation

```beef
let anim = new FloatAnimation(0, 100);
anim.Duration = 1.0f;
anim.Easing = .QuadraticInOut;
anim.OnValueChanged = new (value) => {
    progressBar.Value = value;
};
anim.Completed.Subscribe(new (a) => {
    Console.WriteLine("Animation complete");
});
uiContext.Animations.Add(anim);
```

### UIElement Animations

Helper methods for common element animations:

```beef
// Fade
let fadeOut = UIElementAnimations.FadeOpacity(element, 1.0f, 0.0f, 0.5f, .QuadraticOut);

// Slide (via margin)
let slide = UIElementAnimations.AnimateMargin(element, startMargin, endMargin, 0.3f, .QuadraticOut);

// Size
let grow = UIElementAnimations.AnimateWidth(element, 80, 120, 0.2f, .BackOut);
let stretch = UIElementAnimations.AnimateHeight(element, 40, 80, 0.2f, .BackOut);
```

### Easing Functions

| Easing | Description |
|--------|-------------|
| `Linear` | Constant speed |
| `QuadraticIn/Out/InOut` | Smooth acceleration/deceleration |
| `CubicIn/Out/InOut` | Stronger curve |
| `BackIn/Out/InOut` | Overshoot effect |
| `BounceIn/Out/InOut` | Bouncy effect |
| `ElasticIn/Out/InOut` | Spring effect |

### Chained Animations

```beef
let phase1 = UIElementAnimations.AnimateWidth(box, 80, 120, 0.2f, .QuadraticOut);
phase1.Completed.Subscribe(new (anim) => {
    let phase2 = UIElementAnimations.AnimateWidth(box, 120, 80, 0.2f, .QuadraticIn);
    uiContext.Animations.Add(phase2);
});
uiContext.Animations.Add(phase1);
```

## RenderTransform

Apply visual transforms without affecting layout:

```beef
// Rotation
element.RenderTransform = Matrix.CreateRotationZ(15.0f * (Math.PI_f / 180.0f));

// Scale
element.RenderTransform = Matrix.CreateScale(1.5f, 1.5f, 1.0f);

// Skew
var skew = Matrix.Identity;
skew.M21 = 0.3f;  // Horizontal shear
element.RenderTransform = skew;

// Combined
let rotate = Matrix.CreateRotationZ(angle);
let scale = Matrix.CreateScale(1.2f, 1.2f, 1.0f);
element.RenderTransform = rotate * scale;

// Transform origin (0-1 relative coordinates)
element.RenderTransformOrigin = .(0.5f, 0.5f);  // Center (default)
element.RenderTransformOrigin = .(0, 0);         // Top-left
```

## Resolution Independence

The UI framework supports resolution-independent layout via the Scale property.

```beef
// Default scale (1 logical pixel = 1 physical pixel)
uiContext.Scale = 1.0f;

// HiDPI / Retina (1 logical pixel = 2 physical pixels)
uiContext.Scale = 2.0f;

// Smaller UI
uiContext.Scale = 0.8f;
```

**How it works:**
- Layout uses logical pixels (`LogicalWidth`, `LogicalHeight`)
- Input coordinates are converted from physical to logical
- Rendering applies scale transform

All measurements (Width, Margin, Padding, etc.) are in **logical pixels**.

## Input Handling

### Mouse Input

```beef
// Process in your input loop
uiContext.ProcessMouseMove(physicalX, physicalY);
uiContext.ProcessMouseDown(.Left, physicalX, physicalY, modifiers);
uiContext.ProcessMouseUp(.Left, physicalX, physicalY, modifiers);
uiContext.ProcessMouseWheel(deltaX, deltaY, physicalX, physicalY, modifiers);
```

### Keyboard Input

```beef
uiContext.ProcessKeyDown(keyCode, scanCode, modifiers, isRepeat);
uiContext.ProcessKeyUp(keyCode, scanCode, modifiers);
uiContext.ProcessTextInput(character);
```

### Mouse Capture

```beef
// Capture mouse to receive events even outside element bounds
protected override void OnMouseDownRouted(MouseButtonEventArgs args)
{
    Context.CaptureMouse(this);
    args.Handled = true;
}

protected override void OnMouseUpRouted(MouseButtonEventArgs args)
{
    Context.ReleaseMouseCapture();
}
```

### Focus

```beef
// Request focus
Context.SetFocus(element);

// Check focus state
if (element.IsFocused) { ... }

// Handle focus events
element.OnGotFocusEvent.Subscribe(new (e) => { ... });
element.OnLostFocusEvent.Subscribe(new (e) => { ... });
```

## Services

### IFontService

Provides fonts for text rendering:

```beef
public interface IFontService
{
    StringView DefaultFontFamily { get; }
    CachedFont GetFont(float pixelHeight);
    CachedFont GetFont(StringView familyName, float pixelHeight);
    DrawingTexture GetAtlasTexture(CachedFont font);
}
```

### IClipboard

System clipboard access:

```beef
public interface IClipboard
{
    Result<void> GetText(String outText);
    Result<void> SetText(StringView text);
    bool HasText { get; }
}
```

### ISystemServices

System-level services:

```beef
public interface ISystemServices
{
    double CurrentTime { get; }
}
```

## Debug Visualization

Enable debug overlays to visualize layout:

```beef
uiContext.DebugSettings.ShowLayoutBounds = true;   // Blue borders
uiContext.DebugSettings.ShowMargins = true;        // Orange areas
uiContext.DebugSettings.ShowPadding = true;        // Green areas
uiContext.DebugSettings.ShowFocused = true;        // Yellow highlight
uiContext.DebugSettings.ShowHitTestBounds = true;  // Magenta borders
uiContext.DebugSettings.TransformDebugOverlay = true;  // Transform debug visuals
```

## Complete Example

```beef
class MyUIApp
{
    private UIContext mUIContext ~ delete _;
    private DrawContext mDrawContext = new .() ~ delete _;

    public void Initialize()
    {
        mUIContext = new UIContext();
        mUIContext.SetTheme(new DarkTheme());
        mUIContext.SetViewportSize(1280, 720);
        mUIContext.Scale = 1.0f;

        BuildUI();
    }

    private void BuildUI()
    {
        let root = new DockPanel();
        root.Background = Color(30, 30, 40);

        // Header
        let header = new StackPanel();
        header.Orientation = .Horizontal;
        header.Background = Color(50, 50, 70);
        header.Padding = Thickness(10, 5);
        root.SetDock(header, .Top);

        let title = new TextBlock("My Application");
        title.Foreground = Color.White;
        header.AddChild(title);

        root.AddChild(header);

        // Content
        let content = new StackPanel();
        content.Orientation = .Vertical;
        content.Spacing = 10;
        content.Padding = Thickness(20);

        let textBox = new TextBox();
        textBox.Width = 300;
        textBox.Placeholder = "Enter your name";
        content.AddChild(textBox);

        let button = new Button();
        button.ContentText = "Submit";
        button.Click.Subscribe(new (sender) => {
            Console.WriteLine(scope $"Name: {textBox.Text}");
        });
        content.AddChild(button);

        root.AddChild(content);

        mUIContext.RootElement = root;
    }

    public void Update(float deltaTime, double totalTime)
    {
        // Route input
        mUIContext.ProcessMouseMove(mouseX, mouseY);
        // ... other input

        // Update
        mUIContext.Update(deltaTime, totalTime);
    }

    public void Render()
    {
        mDrawContext.Clear();
        mUIContext.Render(mDrawContext);
        // Submit mDrawContext batches to GPU
    }
}
```
