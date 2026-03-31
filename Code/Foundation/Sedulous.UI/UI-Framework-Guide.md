# Sedulous.UI Framework Guide

A comprehensive guide to building user interfaces with the Sedulous.UI framework — a GPU-accelerated, immediate-mode-inspired retained UI toolkit written in Beef, using SDL3 for windowing and OpenGL 3.3 for rendering.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Getting Started](#2-getting-started)
3. [Core Controls](#3-core-controls)
4. [Layouts](#4-layouts)
5. [Scrolling](#5-scrolling)
6. [Data Views](#6-data-views)
7. [Text Features](#7-text-features)
8. [Theming](#8-theming)
9. [Input & Commands](#9-input--commands)
10. [Drag & Drop](#10-drag--drop)
11. [Overlays](#11-overlays)
12. [Toolkit Controls](#12-toolkit-controls)
13. [Docking](#13-docking)
14. [Multi-Window](#14-multi-window)
15. [Animation](#15-animation)
16. [Extending the Framework](#16-extending-the-framework)

---

## 1. Overview

### Architecture

```
Application (SampleFramework)
  ├── UIContext          — Single shared context (theme, managers, registry)
  │   ├── RootView       — One per window (size, DPI, PopupLayer, cursor)
  │   │   ├── ViewGroup  — Container with child management
  │   │   │   └── View   — Base class (measure, layout, draw, hit-test)
  │   │   └── PopupLayer — Overlays (dialogs, menus, tooltips)
  │   ├── InputManager   — Mouse/keyboard routing
  │   ├── FocusManager   — Tab navigation, focus tracking
  │   ├── DragDropManager— Drag-and-drop orchestration
  │   ├── AnimationManager— Animation lifecycle
  │   └── TooltipManager — Hover tooltips
  └── DrawContext        — 2D drawing API → DrawBatch → OpenGL
```

### View Lifecycle

Every view follows a **measure → layout → draw** cycle:

1. **Measure** — `OnMeasure(widthSpec, heightSpec)` determines desired size
2. **Layout** — `OnLayout(width, height)` positions children within allocated bounds
3. **Draw** — `OnDraw(ctx)` renders content using `DrawContext`

### Ownership Model

- `ViewGroup.AddView()` transfers ownership — the parent deletes children in its destructor
- `ViewGroup.DetachView()` returns ownership to the caller
- Event delegates are owned by the subscriber (caller must `new` them)
- `MutationQueue.QueueDelete()` marks `IsPendingDeletion` immediately, deletes at frame end

---

## 2. Getting Started

### Minimal Application

```beef
using SampleFramework;
using Sedulous.Drawing;
using Sedulous.UI;
using Sedulous.UI.Toolkit;

class MyApp : Application
{
    public this() : base(.()
    {
        Title = "My App",
        Width = 1280,
        Height = 720,
        ClearColor = .(0.1f, 0.1f, 0.15f, 1.0f)
    })
    {
    }

    protected override bool OnInitialize()
    {
        // Register toolkit theme extensions before creating UIContext
        Theme.RegisterExtension(new ToolkitThemeExtension());

        mUIContext = new UIContext(FontService, Clipboard);

        mMainRoot = new RootView();
        let root = new FrameLayout();
        root.Padding = .(20);
        mMainRoot.AddView(root);
        mUIContext.AddRootView(mMainRoot);

        // Add controls to root
        let label = new Label("Hello, Sedulous.UI!");
        label.FontSize = 24;
        root.AddView(label);

        return true;
    }

    protected override void OnRender(DrawContext ctx)
    {
        mMainRoot.SetSize((float)Window.Width, (float)Window.Height);
        mUIContext.BeginFrame(DeltaTime);
        mUIContext.UpdateRootView(mMainRoot, DeltaTime);
        mUIContext.DrawRootView(mMainRoot, ctx);
    }

    protected override void OnCleanup()
    {
        if (mUIContext != null)
        {
            mUIContext.RemoveRootView(mMainRoot);
            delete mMainRoot;
            delete mUIContext;
        }
        Theme.ShutdownExtensions();
    }

    public static int Main(String[] args)
    {
        let app = scope MyApp();
        return app.Run();
    }
}
```

### Application Virtual Methods

| Method | Purpose |
|---|---|
| `OnInitialize()` | Set up UIContext, RootView, load assets |
| `OnUpdate(deltaTime)` | Per-frame logic |
| `OnRender(ctx)` | Draw UI and custom content |
| `OnCleanup()` | Delete UIContext, RootView, extensions |
| `OnKeyDown(key)` | Global key handling |
| `OnResize(w, h)` | Window resize |

### Frame Loop

Every frame must call three methods in order:

```beef
mMainRoot.SetSize((float)Window.Width, (float)Window.Height);
mUIContext.BeginFrame(DeltaTime);        // Process mutations, animations, timers
mUIContext.UpdateRootView(mMainRoot, DeltaTime);  // Measure + layout
mUIContext.DrawRootView(mMainRoot, ctx);          // Draw with DPI transform
```

---

## 3. Core Controls

All controls extend `View` and support these common properties:

| Property | Type | Description |
|---|---|---|
| `Enabled` | `bool` | Enable/disable (grays out, blocks input) |
| `Visibility` | `Visibility` | `.Visible`, `.Hidden` (invisible but takes space), `.Gone` (removed from layout) |
| `Alpha` | `float` | Opacity 0-1 |
| `Padding` | `Thickness` | Internal padding |
| `MinWidth/MinHeight` | `float` | Minimum size constraints |
| `MaxWidth/MaxHeight` | `float` | Maximum size constraints |
| `BackgroundColor` | `Color` | Convenience setter for solid background |
| `TooltipText` | `String` | Hover tooltip (must be `new`'d) |
| `CursorType` | `CursorType` | Cursor on hover |

### Label

Displays text with optional styling.

```beef
let label = new Label("Hello World");
label.FontSize = 20;
label.TextColor = .(0.3f, 0.8f, 0.4f, 1.0f);
label.TextAlignment = .Center;
label.VerticalAlignment = .Middle;
label.WordWrap = true;
label.TextOverflow = .Ellipsis;  // Truncate with "..." when too wide
```

**Constructors:**
- `Label()` — empty
- `Label(StringView text)` — with text
- `Label(StringView text, float fontSize)` — with text and size

### Button

Clickable button with text.

```beef
let btn = new Button("Click Me");
btn.OnClick.Subscribe(new (b) => {
    // Handle click
});

// Disabled button
let disabled = new Button("Disabled");
disabled.Enabled = false;
```

**Properties:**
- `Text`, `FontSize`, `TextColor` — text styling
- `Command` — bind to an `ICommand` (auto-disables when `CanExecute()` returns false)

**Events:**
- `OnClick` — `delegate void(Button)`

### CheckBox

Toggle with label text.

```beef
let cb = new CheckBox("Enable audio");
cb.IsChecked = true;
cb.OnCheckedChanged.Subscribe(new (checkbox, isChecked) => {
    // Handle state change
});
```

### RadioButton & RadioGroup

Mutually exclusive selection.

```beef
let group = new RadioGroup();  // Extends LinearLayout
group.Orientation = .Vertical;
group.Spacing = 4;

let rb1 = new RadioButton("Low");
let rb2 = new RadioButton("Medium");
let rb3 = new RadioButton("High");

group.AddRadioButton(rb1);
group.AddRadioButton(rb2);
group.AddRadioButton(rb3);
group.CheckAt(1);  // Select "Medium"

group.OnSelectionChanged.Subscribe(new (g, selected) => {
    // selected is the newly checked RadioButton
});
```

### ToggleButton

A button that stays pressed/unpressed.

```beef
let toggle = new ToggleButton("Dark Mode");
toggle.OnCheckedChanged.Subscribe(new (t, isOn) => {
    // Handle toggle
});
```

### EditText

Single or multi-line text input.

```beef
let edit = new EditText("Placeholder hint...");
edit.OnTextChanged.Subscribe(new (e) => {
    // e.Text contains current text
});
edit.OnSubmit.Subscribe(new (e) => {
    // Enter key pressed (single-line only)
});

// Numeric-only input
let numEdit = new EditText("0-9");
numEdit.Filter = InputFilter.Digits();
numEdit.MaxLength = 10;

// Read-only
let roEdit = new EditText();
roEdit.Text = "Cannot edit this";
roEdit.ReadOnly = true;
```

**Key Properties:**
- `Text`, `HintText`, `FontSize`, `TextColor`, `HintColor`
- `ReadOnly`, `Multiline`, `MaxLength`
- `Filter` — `InputFilter` for character filtering
- `CursorPosition`, `SelectionStart`, `SelectionEnd` (read-only)

### PasswordBox

Extends `EditText` with masked display.

```beef
let pw = new PasswordBox("Enter password");
pw.MaskChar = '*';  // Default mask character
```

### Slider

Draggable value selector.

```beef
let slider = new Slider();
slider.Min = 0;
slider.Max = 100;
slider.Step = 1;       // 0 = continuous
slider.Value = 50;
slider.Orientation = .Horizontal;  // or .Vertical

slider.OnValueChanged.Subscribe(new (s, value) => {
    // Handle value change
});
```

### ProgressBar

Displays progress 0-1.

```beef
let progress = new ProgressBar();
progress.Progress = 0.75f;
progress.TrackColor = .(0.3f, 0.3f, 0.3f, 1.0f);
progress.FillColor = .(0.2f, 0.6f, 1.0f, 1.0f);
```

### ImageView

Displays an image with scaling modes.

```beef
let imageView = new ImageView();
imageView.Source = myImageData;  // IImageData (not owned by ImageView)
imageView.ScaleType = .FitCenter;  // .None, .FitCenter, .FillBounds, .CenterCrop
imageView.Tint = .(1.0f, 0.5f, 0.5f, 1.0f);  // Optional tint
```

### ColorView

Solid color rectangle.

```beef
let colorView = new ColorView(.(0.2f, 0.5f, 0.9f, 1.0f));
colorView.Color = .(1.0f, 0.0f, 0.0f, 1.0f);  // Change color
```

### Panel

Bordered, filled container (extends `FrameLayout`).

```beef
let panel = new Panel();
panel.FillColor = .(0.2f, 0.2f, 0.3f, 1.0f);
panel.BorderColor = .(0.4f, 0.4f, 0.5f, 1.0f);
panel.BorderWidth = 2;
panel.CornerRadius = 8;
panel.Padding = .(12);

let content = new Label("Inside a panel");
panel.AddView(content, new FrameLayout.LayoutParams(
    LayoutParams.MatchParent, LayoutParams.MatchParent));
```

### Separator

Thin divider line.

```beef
let sep = new Separator();
sep.Orientation = .Horizontal;  // or .Vertical
sep.SeparatorColor = .(0.5f, 0.5f, 0.5f, 1.0f);
sep.Thickness = 1;
```

### Spacer

Empty space — useful for flexible gaps in layouts.

```beef
layout.AddView(new Spacer(), new LinearLayout.LayoutParams(0, 0, 1));
```

---

## 4. Layouts

### LayoutParams

Every child added to a layout can have `LayoutParams` controlling sizing:

```beef
// Constants
LayoutParams.MatchParent  // -1: fill parent
LayoutParams.WrapContent  // -2: size to content

// Basic usage
let lp = new LayoutParams(LayoutParams.MatchParent, LayoutParams.WrapContent);
lp.Margin = .(4, 8, 4, 8);  // left, top, right, bottom
layout.AddView(child, lp);
```

### LinearLayout

Arranges children in a line (horizontal or vertical). Supports weighted sizing.

```beef
let layout = new LinearLayout();
layout.Orientation = .Vertical;   // or .Horizontal
layout.Spacing = 8;
layout.Gravity = .CenterV;       // Cross-axis alignment
layout.BaselineAligned = true;    // Align text baselines (horizontal only)

// Fixed-size child
layout.AddView(label, new LinearLayout.LayoutParams(
    LayoutParams.WrapContent, LayoutParams.WrapContent));

// Weighted child (fills remaining space)
let lp = new LinearLayout.LayoutParams(0, LayoutParams.MatchParent);
lp.Weight = 1;
layout.AddView(slider, lp);

// Weighted with gravity
let glp = new LinearLayout.LayoutParams(0, LayoutParams.WrapContent, 1);
glp.Gravity = .Center;
layout.AddView(centered, glp);
```

### FrameLayout

Stacks children on top of each other. Position children with `Gravity`.

```beef
let frame = new FrameLayout();

// Fill the entire frame
frame.AddView(background, new FrameLayout.LayoutParams(
    LayoutParams.MatchParent, LayoutParams.MatchParent));

// Centered overlay
frame.AddView(overlay, new FrameLayout.LayoutParams(
    LayoutParams.WrapContent, LayoutParams.WrapContent, .Center));

// Bottom-right corner
frame.AddView(badge, new FrameLayout.LayoutParams(
    LayoutParams.WrapContent, LayoutParams.WrapContent,
    .Bottom | .Right));
```

### GridLayout

Grid with fixed, auto, or proportional (star) column/row sizing.

```beef
let grid = new GridLayout();
grid.ColumnCount = 3;
grid.ColumnSpacing = 4;
grid.RowSpacing = 4;

// Column sizing modes
grid.SetColumnSpecs(
    .Pixels(80),   // Fixed 80px
    .Star(1),      // 1x proportional
    .Star(2)       // 2x proportional (twice as wide as Star(1))
);

// Row sizing (optional)
grid.SetRowSpecs(.Auto, .Pixels(50), .Star(1));

// Add children (auto-placed left-to-right, top-to-bottom)
grid.AddView(cell1);
grid.AddView(cell2);
grid.AddView(cell3);

// Explicit row/column placement
let lp = new GridLayout.LayoutParams();
lp.Row = 1;
lp.Column = 0;
lp.ColumnSpan = 2;   // Span across 2 columns
lp.RowSpan = 1;
lp.Gravity = .Center;
grid.AddView(spanning, lp);
```

**GridSpec modes:**
- `GridSpec.Auto` — sized to content
- `GridSpec.Pixels(float)` — fixed pixel size
- `GridSpec.Star(float)` — proportional (weight-based, shares remaining space)

### FlowLayout

Wraps children to the next line when the current line is full.

```beef
let flow = new FlowLayout();
flow.HSpacing = 6;         // Horizontal gap between items
flow.VSpacing = 6;         // Vertical gap between lines
flow.Orientation = .Horizontal;  // .Horizontal wraps to rows; .Vertical wraps to columns

for (let tag in tags)
{
    let btn = new Button(tag);
    btn.Padding = .(8, 4, 8, 4);
    flow.AddView(btn);
}
```

### AbsoluteLayout

Positions children at explicit coordinates.

```beef
let abs = new AbsoluteLayout();

let child = new Label("At (50, 100)");
abs.AddView(child, new AbsoluteLayout.LayoutParams(50, 100, 200, 30));
//                                                  x   y   width height
```

---

## 5. Scrolling

### ScrollView

Scrollable container for content larger than the viewport.

```beef
let scroll = new ScrollView();
scroll.AllowVerticalScroll = true;
scroll.AllowHorizontalScroll = false;
scroll.HorizontalScrollBarPolicy = .Auto;   // .Auto, .Always, .Never
scroll.VerticalScrollBarPolicy = .Auto;
scroll.WheelSpeed = 40;
scroll.MomentumFriction = 5;
scroll.ScrollBarThickness = 12;

// Set the scrollable content (replaces any previous content)
let content = new LinearLayout();
content.Orientation = .Vertical;
scroll.SetContent(content);

// Programmatic scrolling
scroll.ScrollToTop();
scroll.ScrollToBottom();
scroll.ScrollBy(0, -50);
scroll.SetScroll(0, 100);
scroll.ScrollToView(someChild);
scroll.StopMomentum();

// Read-only properties
float maxY = scroll.MaxScrollY;
float viewH = scroll.ViewportHeight;
float extH = scroll.ExtentHeight;
```

---

## 6. Data Views

### ListView

Virtualized list with view recycling — handles 10,000+ items efficiently.

```beef
let listView = new ListView();
listView.FixedItemHeight = 22;  // Required for virtualization
parent.AddView(listView, new LinearLayout.LayoutParams(
    LayoutParams.MatchParent, 200));

// Create and set an adapter
let adapter = new MyListAdapter(10000);
listView.SetAdapter(adapter);  // ListView does NOT own the adapter

// Selection
listView.SelectionModel.Mode = .Single;  // .None, .Single, .Multiple
listView.OnItemClick.Subscribe(new (lv, position) => {
    // Handle item click
});
```

**Implementing an adapter:**

```beef
class MyListAdapter : ListAdapter
{
    private int mCount;

    public this(int count) { mCount = count; }

    public override int ItemCount => mCount;

    public override View CreateView(int32 viewType)
    {
        let label = new Label();
        label.Padding = .(8, 2, 8, 2);
        return label;
    }

    public override void BindView(View view, int position)
    {
        if (let label = view as Label)
            label.Text = scope:: $"Item {position + 1}";
    }
}
```

### TreeView

Hierarchical data with expand/collapse, built on ListView.

```beef
let tree = new TreeView();
tree.FixedItemHeight = 22;
tree.IndentPerDepth = 20;
parent.AddView(tree, new LinearLayout.LayoutParams(
    LayoutParams.MatchParent, 180));

let adapter = new MyTreeAdapter();
tree.SetAdapter(adapter);  // TreeView does NOT own the adapter

tree.OnItemClick.Subscribe(new (tv, position) => { });
tree.OnNodeToggled.Subscribe(new (tv, position) => { });
```

**Implementing a tree adapter:**

```beef
class MyTreeAdapter : ITreeAdapter
{
    // Maintain a flat list of visible nodes
    public int ItemCount => mVisible.Count;
    public int GetDepth(int position) => mVisible[position].Depth;
    public bool HasChildren(int position) => mVisible[position].HasKids;
    public bool IsExpanded(int position) => mVisible[position].Expanded;
    public int32 GetItemViewType(int position) => 0;

    public View CreateView(int32 viewType)
    {
        let label = new Label();
        label.Padding = .(4, 2, 4, 2);
        return label;
    }

    public void BindView(View view, int position)
    {
        if (let label = view as Label)
            label.Text = scope:: $"{mVisible[position].Name}";
    }

    public void ToggleExpand(int position)
    {
        // Insert or remove child nodes from mVisible
        // Then notify observers:
        for (let obs in mObservers) obs.OnDataChanged();
    }

    public void RegisterObserver(IAdapterObserver observer) { ... }
    public void UnregisterObserver(IAdapterObserver observer) { ... }
}
```

---

## 7. Text Features

### Word Wrap

```beef
let label = new Label("Long text that wraps to multiple lines...");
label.WordWrap = true;
```

### Text Overflow Ellipsis

Truncates text with "..." when it exceeds the available width:

```beef
let label = new Label("This very long text will be truncated with ellipsis");
label.TextOverflow = .Ellipsis;
// Add with constrained width:
parent.AddView(label, new LinearLayout.LayoutParams(
    LayoutParams.MatchParent, LayoutParams.WrapContent));
```

### Font Sizing

```beef
let small = new Label("Small", 11);
let normal = new Label("Normal");          // Default 16px
let large = new Label("Large", 24);
```

### Text Alignment

```beef
label.TextAlignment = .Left;    // .Left, .Center, .Right
label.VerticalAlignment = .Middle;  // .Top, .Middle, .Bottom
```

---

## 8. Theming

### Palette

The `Palette` struct holds 10 seed colors that derive the entire visual appearance:

| Color | Purpose |
|---|---|
| `Primary` | Primary brand color |
| `Secondary` | Secondary accent |
| `Accent` | Highlights, focus rings |
| `Background` | Window/app background |
| `Surface` | Control backgrounds |
| `Error` | Error states |
| `Warning` | Warning states |
| `Success` | Success states |
| `Text` | Default text color |
| `Border` | Default border color |

**State derivation** (static utility methods):
```beef
Color hover = Palette.ComputeHover(baseColor);
Color pressed = Palette.ComputePressed(baseColor);
Color disabled = Palette.ComputeDisabled(baseColor);
Color focused = Palette.ComputeFocused(baseColor, accentColor);
Color resolved = Palette.ResolveState(baseColor, state, accentColor);
```

**Color utilities:**
```beef
Color lighter = Palette.Lighten(color, 0.2f);
Color darker = Palette.Darken(color, 0.2f);
Color faded = Palette.Desaturate(color, 0.5f);
Color semi = Palette.WithAlpha(color, 128);
Color mixed = Palette.Lerp(colorA, colorB, 0.5f);
```

### Using Themes

The framework provides built-in dark and light themes:

```beef
// Create dark theme (default)
mUIContext.Theme = DarkTheme.Create();

// Create light theme
mUIContext.Theme = LightTheme.Create();
```

### Per-Control Color Overrides

Themes support typed color/dimension overrides per control type:

```beef
let theme = DarkTheme.Create();

// Override button colors
theme.SetColor("Button", "background", .(0.2f, 0.4f, 0.8f, 1.0f));
theme.SetColor("Button", "text", .(1.0f, 1.0f, 1.0f, 1.0f));

// Override dimensions
theme.SetDimension("Button", "cornerRadius", 4);
theme.SetDimension("Slider", "trackHeight", 6);

// Named colors (global, not per-control)
theme.SetNamedColor("accent", .(0.3f, 0.7f, 1.0f, 1.0f));

// Named dimensions
theme.SetNamedDimension("spacing", 8);

mUIContext.Theme = theme;
```

### Theme Switching at Runtime

```beef
// Cycle themes on key press
protected override void OnKeyDown(ShellKeyCode key)
{
    if (key == .T && mUIContext != null)
    {
        let name = mUIContext.Theme?.Name ?? "Dark";
        if (name == "Dark")
            mUIContext.Theme = LightTheme.Create();
        else
            mUIContext.Theme = DarkTheme.Create();

        // Update window clear color to match
        mConfig.ClearColor = mUIContext.Theme.Palette.Background;
    }
}
```

---

## 9. Input & Commands

### Mouse Events

Override these methods on any `View`:

```beef
public override void OnMouseDown(MouseButtonEventArgs e) { }
public override void OnMouseUp(MouseButtonEventArgs e) { }
public override void OnMouseMove(MouseEventArgs e) { }
public override void OnMouseWheel(MouseWheelEventArgs e) { }
public override void OnMouseEnter(MouseEventArgs e) { }
public override void OnMouseLeave(MouseEventArgs e) { }
```

### Keyboard Events

```beef
public override void OnKeyDown(KeyEventArgs e)
{
    if (e.Key == .Return)
        DoSomething();
}

public override void OnKeyUp(KeyEventArgs e) { }
public override void OnTextInput(TextInputEventArgs e) { }
```

### Focus

```beef
// Make a view focusable
myView.Focusable = true;
myView.IsTabStop = true;
myView.TabIndex = 0;

// Focus events
public override void OnFocusGained(FocusEventArgs e) { }
public override void OnFocusLost(FocusEventArgs e) { }

// Programmatic focus
mUIContext.FocusManager.SetFocus(myView);
```

### ICommand Pattern

Decouple button actions from UI logic:

```beef
// Create a command with execute + canExecute delegates
let command = new RelayCommand(
    new () => { DoAction(); },           // execute
    new () => mIsReady                    // canExecute (optional)
);

// Bind to a button — auto-disables when CanExecute() returns false
let btn = new Button("Run Command");
btn.Command = command;

// When external state changes, notify the command
mIsReady = false;
command.RaiseCanExecuteChanged();  // Button updates enabled state
```

**ICommand interface:**
```beef
public interface ICommand
{
    void Execute();
    bool CanExecute();
    EventAccessor<delegate void()> OnCanExecuteChanged { get; }
}
```

---

## 10. Drag & Drop

### Implementing a Drag Source

```beef
class DraggableItem : Panel, IDragSource
{
    public DragData CreateDragData()
    {
        return new ViewDragData("myapp/item", this);
    }

    public View CreateDragVisual(DragData data)
    {
        let visual = new Panel();
        visual.FillColor = .(0.5f, 0.5f, 0.8f, 0.8f);
        visual.MinWidth = 60;
        visual.MinHeight = 40;
        let label = new Label("Dragging...");
        visual.AddView(label, new FrameLayout.LayoutParams(-1, -1));
        return visual;
    }

    public void OnDragStarted(DragData data)
    {
        Alpha = 0.4f;  // Fade the source
    }

    public void OnDragCompleted(DragData data, DragDropEffects effect, bool cancelled)
    {
        Alpha = 1.0f;  // Restore
    }
}
```

### Implementing a Drop Target

```beef
class DropZone : LinearLayout, IDropTarget
{
    public DragDropEffects CanAcceptDrop(DragData data, float localX, float localY)
    {
        if (data.Format == "myapp/item")
            return .Move;
        return .None;
    }

    public void OnDragEnter(DragData data, float localX, float localY) { }
    public void OnDragOver(DragData data, float localX, float localY) { }
    public void OnDragLeave(DragData data) { }

    public DragDropEffects OnDrop(DragData data, float localX, float localY)
    {
        if (let viewData = data as ViewDragData)
        {
            let source = viewData.SourceView;
            source.Parent.DetachView(source);
            AddView(source);
            return .Move;
        }
        return .None;
    }
}
```

### DragDropManager Configuration

```beef
let dd = mUIContext.DragDrop;
dd.DragThreshold = 4.0f;        // Pixels before drag starts
dd.AdornerOffsetX = 4.0f;       // Visual offset from cursor
dd.AdornerOffsetY = 4.0f;
dd.AcceptCursor = .Move;         // Cursor over accepting target
dd.RejectCursor = .NotAllowed;   // Cursor over rejecting target
```

---

## 11. Overlays

### Context Menu

```beef
let menu = new ContextMenu();
menu.AddItem("Cut", new () => { DoCut(); });
menu.AddItem("Copy", new () => { DoCopy(); });
menu.AddSeparator();
menu.AddItem("Paste", new () => { DoPaste(); });

// Submenus
let sub = menu.AddSubmenu("More Options");
sub.AddItem("Option A", new () => { });
sub.AddItem("Option B", new () => { });

// Nested submenus
let nested = sub.AddSubmenu("Even More");
nested.AddItem("Deep Item", new () => { });

// Show at screen position
let screenPos = btn.ToScreen(.(0, btn.Height));
ContextMenu.Show(mUIContext, screenPos.X, screenPos.Y, menu);
```

### Dialog

Modal dialog with title, content, and buttons.

```beef
// Quick alert
let alert = Dialog.Alert("Warning", "Something happened.");
mUIContext.ShowModalPopup(alert);

// Confirm dialog with result
let confirm = Dialog.Confirm("Delete?", "Are you sure?");
confirm.OnResult.Subscribe(new (dialog, result) => {
    if (result == .Yes)
        DeleteItem();
});
mUIContext.ShowModalPopup(confirm);

// Custom dialog
let dialog = new Dialog();
dialog.Title = "Settings";

let content = new LinearLayout();
content.Spacing = 8;
content.AddView(new CheckBox("Enable feature"));
content.AddView(new Slider());
dialog.SetContent(content);

dialog.AddButton("OK", .OK);
dialog.AddButton("Cancel", .Cancel);

dialog.OnResult.Subscribe(new (d, r) => {
    if (r == .OK) ApplySettings();
});

mUIContext.ShowModalPopup(dialog);
```

**DialogResult values:** `.None`, `.OK`, `.Cancel`, `.Yes`, `.No`, `.Custom`

### Tooltips

Tooltips appear automatically on hover for views with `TooltipText` set:

```beef
let btn = new Button("Hover me");
btn.TooltipText = new .("This button does something!");
// The String is owned by the view and deleted automatically
```

**TooltipManager settings:**
```beef
mUIContext.Tooltips.ShowDelay = 0.5f;     // Seconds before showing
mUIContext.Tooltips.CursorOffsetY = 16;   // Pixels below cursor
```

### PopupLayer

Low-level popup API for custom overlays:

```beef
// Modeless popup at specific position
mUIContext.ShowPopup(myPopupView, owner, x, y,
    closeOnClickOutside: true,
    ownsView: true);

// Modal popup (centered, with backdrop)
mUIContext.ShowModalPopup(myPopupView, owner);

// Close programmatically
mUIContext.ClosePopup(myPopupView);
```

---

## 12. Toolkit Controls

The `Sedulous.UI.Toolkit` library provides higher-level controls. Register its theme extension before creating `UIContext`:

```beef
Theme.RegisterExtension(new ToolkitThemeExtension());
```

### TabView

Tabbed container with configurable tab placement.

```beef
let tabs = new TabView();
tabs.Placement = .Top;  // .Top, .Bottom, .Left, .Right
tabs.TabHeight = 30;

let tab1Content = new Label("Tab 1 content");
tab1Content.Padding = .(8);
tabs.AddTab("Info", tab1Content);

let tab2Content = new LinearLayout();
tabs.AddTab("Settings", tab2Content);

tabs.SelectedIndex = 0;

tabs.OnTabChanged.Subscribe(new (tv, index) => {
    // Tab changed
});

// Remove a tab
tabs.RemoveTab(1);
```

### SplitView

Resizable split pane with draggable divider.

```beef
let split = new SplitView(.Horizontal);  // or .Vertical
split.SplitRatio = 0.3f;    // 30% left, 70% right
split.DividerSize = 6;
split.MinPaneSize = 50;

let leftPane = new Panel();
let rightPane = new Panel();
split.SetPanes(leftPane, rightPane);

split.OnSplitChanged.Subscribe(new (sv, ratio) => { });
```

### ComboBox

Dropdown selection.

```beef
let combo = new ComboBox();
combo.AddItem("Red");
combo.AddItem("Green");
combo.AddItem("Blue");
combo.SelectedIndex = 0;
combo.MinWidth = 120;

combo.OnSelectionChanged.Subscribe(new (cb, index) => {
    let text = cb.SelectedText;  // StringView of selected item
});
```

### NumberField

Numeric input with spinner buttons and mouse wheel support.

```beef
let numField = new NumberField(50, 0, 100);  // initial, min, max
numField.Step = 5;
numField.DecimalPlaces = 0;
numField.ShowSpinners = true;
numField.AllowMouseWheel = true;

numField.OnValueChanged.Subscribe(new (nf, value) => { });
```

### Toolbar

Horizontal button bar with separators.

```beef
let toolbar = new Toolbar();

let btnNew = toolbar.AddButton("New");
btnNew.OnClick.Subscribe(new (b) => { });
let btnOpen = toolbar.AddButton("Open");
toolbar.AddSeparator();
let btnSave = toolbar.AddButton("Save");
```

### StatusBar

Bottom status strip with sections.

```beef
let statusBar = new StatusBar();
statusBar.SetText("Ready");              // Main section text
statusBar.AddSection("Ln 1, Col 1");     // Additional sections
```

### Expander

Collapsible section with header.

```beef
let expander = new Expander("Advanced Settings");
expander.IsExpanded = false;

let content = new LinearLayout();
content.Spacing = 4;
content.Padding = .(8);
content.AddView(new CheckBox("Option 1"));
content.AddView(new CheckBox("Option 2"));
expander.SetContent(content);

expander.OnExpandedChanged.Subscribe(new (e, expanded) => { });
```

### Breadcrumb

Navigable path display.

```beef
let bc = new Breadcrumb();
StringView[?] path = .("Root", "Assets", "Textures");
bc.SetPath(path);

// Dynamic navigation
bc.PushSegment("NewFolder");
bc.PopSegment();
bc.NavigateTo(1);  // Navigate to level 1

bc.OnNavigate.Subscribe(new (breadcrumb, level) => {
    // User clicked segment at level
    for (int i = 0; i <= level; i++)
        let seg = breadcrumb.GetSegment(i);
});
```

### LogView

Scrollable, filterable log display.

```beef
let log = new LogView();
log.AutoScroll = true;
log.MaxEntries = 1000;

log.AddEntry(.Info, "Application started");
log.AddEntry(.Debug, "Loading config...");
log.AddEntry(.Warning, "Deprecated API used");
log.AddEntry(.Error, "Connection failed");

// Filter by level
log.ShowDebug = true;
log.ShowInfo = true;
log.ShowWarning = true;
log.ShowError = true;

// Clear all entries
log.Clear();
```

**LogLevel values:** `.Debug`, `.Info`, `.Warning`, `.Error`

### ColorPicker

HSV color picker with saturation/value square, hue strip, and alpha strip.

```beef
let picker = new ColorPicker();
picker.SetColor(.(0.2f, 0.6f, 1.0f, 1.0f));

picker.OnColorChanged.Subscribe(new (cp, color) => {
    // color is the new Color value
});

// Utility functions
Color rgb = ColorPicker.HSVToRGB(0.5f, 1.0f, 1.0f);
float h = 0, s = 0, v = 0;
ColorPicker.RGBToHSV(0.5f, 0.8f, 1.0f, ref h, ref s, ref v);
```

### PropertyGrid

Categorized property editor grid.

```beef
let grid = new PropertyGrid();
grid.LabelWidthRatio = 0.4f;  // 40% labels, 60% editors
grid.RowHeight = 26;

// Built-in editor types
grid.AddProperty(new FloatEditor("Speed", 10.0f, 0, 100, 0.5f, "Physics"));
grid.AddProperty(new IntEditor("Health", 100, 0, 999, 1, "Stats"));
grid.AddProperty(new BoolEditor("IsActive", true, "General"));
grid.AddProperty(new StringEditor("Name", "Player1", "General"));
grid.AddProperty(new ColorEditor("Tint", Color(0.2f, 0.6f, 1.0f, 1.0f), "Appearance"));

// Enum editor
StringView[?] modes = .("Walk", "Run", "Fly", "Swim");
grid.AddProperty(new EnumEditor("MoveMode", 1, modes, "Physics"));

// Vector2 editor
grid.AddProperty(new Vector2Editor("Position", .(128, 256), -1000, 1000, 1, "Transform"));

// Range editor (0-1 slider)
grid.AddProperty(new RangeEditor("Volume", 0.8f, 0, 1, 0.05f, "Audio"));
```

### MenuBar

Application menu bar with dropdown menus.

```beef
let menuBar = new MenuBar();

let fileMenu = menuBar.AddMenu("File");
fileMenu.AddItem("New", new () => { });
fileMenu.AddItem("Open", new () => { });
fileMenu.AddSeparator();
fileMenu.AddItem("Exit", new () => { });

let editMenu = menuBar.AddMenu("Edit");
editMenu.AddItem("Undo", new () => { });
editMenu.AddItem("Redo", new () => { });
editMenu.AddSeparator();
editMenu.AddItem("Cut", new () => { });
editMenu.AddItem("Copy", new () => { });
editMenu.AddItem("Paste", new () => { });

parent.AddView(menuBar, new LinearLayout.LayoutParams(
    LayoutParams.MatchParent, LayoutParams.WrapContent));
```

### DraggableTreeView

TreeView with drag-to-reorder support.

```beef
let dragTree = new DraggableTreeView();
dragTree.FixedItemHeight = 22;
dragTree.DragEnabled = true;

// Requires IReorderableTreeAdapter
let adapter = new MyReorderableAdapter();
dragTree.SetAdapter(adapter);

dragTree.OnItemReordered.Subscribe(new (tree, fromPos, toPos) => {
    // Item moved
});
```

**IReorderableTreeAdapter** extends `ITreeAdapter` with:
```beef
public interface IReorderableTreeAdapter : ITreeAdapter
{
    bool CanMove(int fromPosition, int toPosition);
    bool MoveItem(int fromPosition, int toPosition);
}
```

---

## 13. Docking

### DockManager

IDE-style docking with split panes, tabs, and floating windows.

```beef
let dock = new DockManager();
dock.FloatingWindowHost = this;  // Enable OS floating windows (Application implements IFloatingWindowHost)

// Create panels
let scene = dock.AddPanel("Scene", new Label("Scene viewport"));
let props = dock.AddPanel("Properties", new Label("Properties"));
let console = dock.AddPanel("Console", new Label("Console output"));
let assets = dock.AddPanel("Assets", new Label("Asset browser"));

// Dock panels into the tree
dock.DockPanel(scene, .Center);                           // First panel fills center
dock.DockPanelRelativeTo(props, .Right, scene.Parent);    // Split right of scene
dock.DockPanelRelativeTo(console, .Bottom, dock.RootNode); // Split bottom of everything
dock.DockPanelRelativeTo(assets, .Center, console.Parent); // Tab alongside console
```

**DockPosition values:** `.Top`, `.Bottom`, `.Left`, `.Right`, `.Center`, `.Float`

### DockablePanel

Individual dockable panel with header bar.

```beef
let panel = dock.AddPanel("My Panel", contentView);
panel.Closable = true;
panel.HeaderHeight = 24;

panel.OnCloseRequested.Subscribe(new (p) => {
    dock.ClosePanel(p);
});
```

### Floating Windows

Panels can float as OS windows or virtual overlays:

```beef
// Float a panel at screen position
dock.FloatPanel(panel, 100, 200);

// Re-dock a floating window
dock.RedockFloatingWindow(floatingWindow);

// Double-click the floating window title bar to re-dock
```

### Drag-to-Dock

Users can drag panel headers or tab labels to dock zones. The DockManager implements `IDropTarget` and shows zone indicators (top/bottom/left/right/center) during drag operations.

---

## 14. Multi-Window

### Architecture

The framework uses a single `UIContext` shared across all windows. Each window gets its own `RootView` with independent size, DPI, PopupLayer, and cursor.

```
UIContext (shared)
  ├── RootView (main window)
  │   ├── Your content
  │   └── PopupLayer
  ├── RootView (floating window 1)
  │   ├── FloatingWindow
  │   └── PopupLayer
  └── RootView (floating window 2)
      ├── FloatingWindow
      └── PopupLayer
```

### RootView

```beef
let root = new RootView();
root.SetSize(1280, 720);       // Physical pixels
root.DpiScale = 1.0f;          // DPI scaling factor

// Properties
float w = root.WindowWidth;     // Physical pixels
float h = root.WindowHeight;
float lw = root.LogicalWidth;   // Physical / DpiScale
float lh = root.LogicalHeight;
PopupLayer popups = root.PopupLayer;
```

### IFloatingWindowHost

Implement this interface to support OS-level floating windows:

```beef
class MyApp : Application, IFloatingWindowHost
{
    public bool SupportsOSWindows => true;

    public void CreateFloatingWindow(View floatingWindow,
        float width, float height,
        float screenX = -1, float screenY = -1,
        delegate void(View) onCloseRequested = null)
    {
        // Create SDL window, GL context, RootView
        // Add RootView to UIContext
        // Add floatingWindow to RootView
    }

    public void DestroyFloatingWindow(View floatingWindow)
    {
        // Remove from UIContext, destroy GL context and SDL window
    }
}
```

The `Application` base class in SampleFramework already implements `IFloatingWindowHost`. Set `dock.FloatingWindowHost = this` to enable OS floating windows.

---

## 15. Animation

### FloatAnimation

Animate any float value over time:

```beef
let anim = new FloatAnimation(
    0, 1,           // from, to
    0.5f,            // duration (seconds)
    new (v) => { myView.Alpha = v; },  // setter delegate
    Easings.EaseOutQuadratic            // easing (optional)
);
anim.Target = myView;  // For CancelForView
mUIContext.Animations.Add(anim);  // Manager takes ownership
```

### ColorAnimation

Animate between colors:

```beef
let anim = new ColorAnimation(
    .(0.2f, 0.5f, 0.9f, 1.0f),  // from
    .(0.9f, 0.3f, 0.5f, 1.0f),  // to
    1.5f,                         // duration
    new (c) => { panel.FillColor = c; },
    Easings.EaseInOutSin
);
anim.AutoReverse = true;
anim.RepeatCount = -1;  // Infinite loop
anim.Target = panel;
mUIContext.Animations.Add(anim);
```

### ViewAnimator Convenience Methods

Static helpers that create common animations:

```beef
// Fade
ViewAnimator.FadeIn(view, 0.3f, Easings.EaseOutQuadratic);
ViewAnimator.FadeOut(view, 0.3f, Easings.EaseInQuadratic);
ViewAnimator.FadeTo(view, 0.5f, 1.0f, 0.3f);

// Translate (uses RenderTransform)
ViewAnimator.TranslateX(view, 0, 100, 0.3f, Easings.EaseOutBack);
ViewAnimator.TranslateY(view, 0, 50, 0.3f);

// Scale (uses RenderTransform)
ViewAnimator.ScaleTo(view, 1, 1.5f, 0.2f, Easings.EaseOutElastic);
```

> **Note:** These return `Animation` objects — you must add them to the manager:
> `mUIContext.Animations.Add(ViewAnimator.FadeIn(view, 0.3f));`

### Storyboard

Group animations to play sequentially or in parallel:

```beef
// Sequential: fade out, then slide in
let sb = new Storyboard(.Sequential);
sb.Add(ViewAnimator.FadeOut(btn, 0.4f, Easings.EaseInQuadratic));
sb.Add(ViewAnimator.FadeIn(btn, 0.4f, Easings.EaseOutQuadratic));
mUIContext.Animations.Add(sb);

// Parallel: fade and slide at the same time
let parallel = new Storyboard(.Parallel);
parallel.Add(ViewAnimator.FadeIn(view, 0.5f));
parallel.Add(ViewAnimator.TranslateY(view, -20, 0, 0.5f));
mUIContext.Animations.Add(parallel);

// Nested storyboards
let complex = new Storyboard(.Sequential);
complex.Add(parallel);  // First: fade+slide together
complex.Add(ViewAnimator.ScaleTo(view, 1, 1.2f, 0.2f));  // Then: bounce
mUIContext.Animations.Add(complex);
```

### Animation Properties

```beef
anim.Duration = 0.5f;       // Seconds
anim.Delay = 0.2f;          // Delay before start
anim.AutoReverse = true;    // Ping-pong
anim.RepeatCount = 3;       // 0=once, -1=infinite
anim.Easing = Easings.EaseOutBounce;

anim.OnComplete.Subscribe(new (a) => {
    // Animation finished (after all repeats)
});
```

### Available Easings

All available as properties on the `Easings` static class:

| Category | Functions |
|---|---|
| Linear | `EaseInLinear`, `EaseOutLinear` |
| Quadratic | `EaseInQuadratic`, `EaseOutQuadratic`, `EaseInOutQuadratic` |
| Cubic | `EaseInCubic`, `EaseOutCubic`, `EaseInOutCubic` |
| Quartic | `EaseInQuartic`, `EaseOutQuartic`, `EaseInOutQuartic` |
| Quintic | `EaseInQuintic`, `EaseOutQuintic`, `EaseInOutQuintic` |
| Sinusoidal | `EaseInSin`, `EaseOutSin`, `EaseInOutSin` |
| Exponential | `EaseInExponential`, `EaseOutExponential`, `EaseInOutExponential` |
| Circular | `EaseInCircular`, `EaseOutCircular`, `EaseInOutCircular` |
| Back | `EaseInBack`, `EaseOutBack`, `EaseInOutBack` |
| Elastic | `EaseInElastic`, `EaseOutElastic`, `EaseInOutElastic` |
| Bounce | `EaseInBounce`, `EaseOutBounce`, `EaseInOutBounce` |

### AnimationManager

```beef
mUIContext.Animations.Add(anim);           // Start animation (takes ownership)
mUIContext.Animations.CancelForView(view); // Cancel all animations targeting view
mUIContext.Animations.CancelAll();         // Cancel everything
int count = mUIContext.Animations.ActiveCount;
```

---

## 16. Extending the Framework

### Custom Control

Create a custom view by extending `View`:

```beef
using Sedulous.UI;
using Sedulous.Drawing;
using Sedulous.Mathematics;

public class CircleButton : View
{
    private String mText ~ delete _;
    private bool mIsPressed;

    public this(StringView text)
    {
        mText = new String(text);
        Focusable = true;
        CursorType = .Pointer;
    }

    public StringView Text
    {
        get => mText;
        set { mText.Set(value); Invalidate(); }
    }

    // Measure: declare desired size
    protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
    {
        float size = 60;  // Circle diameter
        SetMeasuredSize(
            MeasureSpec.ResolveSize(size, widthSpec),
            MeasureSpec.ResolveSize(size, heightSpec));
    }

    // Draw: render the control
    protected override void OnDraw(DrawContext ctx)
    {
        let palette = Context?.Theme?.Palette ?? Palette.Dark;
        var color = palette.Primary;

        if (!Enabled)
            color = Palette.ComputeDisabled(color);
        else if (mIsPressed)
            color = Palette.ComputePressed(color);
        else if (IsHovered)
            color = Palette.ComputeHover(color);

        float cx = Width / 2;
        float cy = Height / 2;
        float r = Math.Min(cx, cy) - 2;

        ctx.FillCircle(.(cx, cy), r, color);

        if (IsFocused)
            ctx.DrawCircle(.(cx, cy), r + 1, palette.Accent, 2);

        if (mText.Length > 0)
            ctx.DrawText(mText, 14,
                .(cx - 20, cy - 7), palette.Text);
    }

    // Input handling
    public override void OnMouseDown(MouseButtonEventArgs e)
    {
        if (e.Button == .Left && Enabled)
        {
            mIsPressed = true;
            e.Capture(this);
            Invalidate();
        }
    }

    public override void OnMouseUp(MouseButtonEventArgs e)
    {
        if (e.Button == .Left && mIsPressed)
        {
            mIsPressed = false;
            e.Release();
            Invalidate();

            if (IsHovered)
                OnClicked();
        }
    }

    private void OnClicked()
    {
        // Fire event, execute command, etc.
    }
}
```

### Custom Layout

Create a custom layout by extending `ViewGroup`:

```beef
public class RingLayout : ViewGroup
{
    public float Radius = 100;

    protected override void OnMeasure(MeasureSpec widthSpec, MeasureSpec heightSpec)
    {
        float size = Radius * 2 + Padding.Horizontal;

        // Measure children
        for (int i = 0; i < ChildCount; i++)
        {
            let child = GetChildAt(i);
            if (child.Visibility == .Gone) continue;
            MeasureChild(child, widthSpec, heightSpec);
        }

        SetMeasuredSize(
            MeasureSpec.ResolveSize(size, widthSpec),
            MeasureSpec.ResolveSize(size, heightSpec));
    }

    protected override void OnLayout(float width, float height)
    {
        float cx = (width - Padding.Horizontal) / 2 + Padding.Left;
        float cy = (height - Padding.Vertical) / 2 + Padding.Top;
        int visible = 0;

        for (int i = 0; i < ChildCount; i++)
            if (GetChildAt(i).Visibility != .Gone) visible++;

        int idx = 0;
        for (int i = 0; i < ChildCount; i++)
        {
            let child = GetChildAt(i);
            if (child.Visibility == .Gone) continue;

            float angle = (float)(idx * Math.PI_d * 2.0 / visible);
            float x = cx + Math.Cos(angle) * Radius - child.MeasuredWidth / 2;
            float y = cy + Math.Sin(angle) * Radius - child.MeasuredHeight / 2;

            child.Layout(x, y, child.MeasuredWidth, child.MeasuredHeight);
            idx++;
        }
    }
}
```

### Custom Theme Extension

Register custom theme defaults for your controls:

```beef
public class MyThemeExtension : IThemeExtension
{
    public void ApplyDefaults(Theme theme)
    {
        let isDark = theme.Name == "Dark";

        // Register colors for your custom control type
        theme.SetColor("CircleButton", "background",
            isDark ? .(0.3f, 0.5f, 0.8f, 1.0f) : .(0.2f, 0.4f, 0.7f, 1.0f));
        theme.SetColor("CircleButton", "text",
            isDark ? .(1.0f, 1.0f, 1.0f, 1.0f) : .(0.1f, 0.1f, 0.1f, 1.0f));

        // Register dimensions
        theme.SetDimension("CircleButton", "radius", 30);
    }
}
```

Register before creating UIContext:

```beef
Theme.RegisterExtension(new MyThemeExtension());
mUIContext = new UIContext(FontService, Clipboard);
```

Query theme values from your control:

```beef
protected override void OnDraw(DrawContext ctx)
{
    let theme = Context?.Theme;
    if (theme != null)
    {
        if (let bg = theme.GetColor("CircleButton", "background"))
            fillColor = bg.Value;
        if (let r = theme.GetDimension("CircleButton", "radius"))
            radius = r.Value;
    }
}
```

### DrawContext Drawing API

The full drawing API available in `OnDraw`:

**Filled shapes:**
```beef
ctx.FillRect(.(x, y, w, h), color);
ctx.FillRoundedRect(.(x, y, w, h), radius, color);
ctx.FillCircle(.(cx, cy), radius, color);
ctx.FillEllipse(.(cx, cy), rx, ry, color);
ctx.FillArc(.(cx, cy), radius, startAngle, sweepAngle, color);
ctx.FillPolygon(points, color);  // Span<Vector2>
```

**Outlined shapes:**
```beef
ctx.DrawRect(.(x, y, w, h), color, thickness);
ctx.DrawRoundedRect(.(x, y, w, h), radius, color, thickness);
ctx.DrawCircle(.(cx, cy), radius, color, thickness);
ctx.DrawEllipse(.(cx, cy), rx, ry, color, thickness);
ctx.DrawLine(.(x1, y1), .(x2, y2), color, thickness);
ctx.DrawPolyline(points, color, thickness);
ctx.DrawPolygon(points, color, thickness);
```

**Text:**
```beef
ctx.DrawText("Hello", fontSize, position, color);
ctx.DrawText("Hello", cachedFont, position, color);
ctx.DrawTextWrapped(text, font, atlasTexture, bounds, maxWidth, color);
```

**Images:**
```beef
ctx.DrawImage(texture, position);
ctx.DrawImage(texture, destRect);
ctx.DrawImage(texture, destRect, srcRect, tint);
ctx.DrawNineSlice(texture, destRect, srcRect, slices, tint);
```

**State management:**
```beef
ctx.PushState();           // Save transform + clip + opacity
ctx.PopState();

ctx.Translate(x, y);
ctx.Rotate(radians);
ctx.Scale(sx, sy);
ctx.SetTransform(matrix);
ctx.ResetTransform();

ctx.PushClipRect(rect);   // Scissor clipping
ctx.PopClip();

ctx.PushOpacity(0.5f);    // Multiplicative opacity
ctx.PopOpacity();

ctx.SetBlendMode(.Normal);
```

---

## Debug Mode

Press **F2** (in the sandbox) to toggle debug draw, which renders layout bounds, margins, and padding outlines for all views:

```beef
mUIContext.DebugDraw = !mUIContext.DebugDraw;
```
