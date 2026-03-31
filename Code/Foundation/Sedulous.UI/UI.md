# Sedulous.UI — GUI Framework Plan

An Android-inspired, renderer-agnostic GUI framework for game engine tooling and in-game UI, built on top of the Sedulous low-level libraries.

---

## Table of Contents

1. [Design Philosophy](#design-philosophy)
2. [Architecture Overview](#architecture-overview)
3. [Project Structure](#project-structure)
4. [Dependency Map](#dependency-map)
5. [Phase 1 — Core View System](#phase-1--core-view-system)
6. [Phase 2 — Layout System](#phase-2--layout-system)
7. [Phase 3 — Input & Focus](#phase-3--input--focus)
8. [Phase 4 — Basic Controls](#phase-4--basic-controls)
9. [Phase 5 — Theming & Styling](#phase-5--theming--styling)
10. [Phase 6 — Text Editing](#phase-6--text-editing)
11. [Phase 7 — Scrolling & Clipping](#phase-7--scrolling--clipping)
12. [Phase 8 — Data-Driven Views](#phase-8--data-driven-views)
13. [Phase 9 — Animation](#phase-9--animation)
14. [Phase 10 — Dialogs, Menus & Overlays](#phase-10--dialogs-menus--overlays)
15. [Phase 11 — Drag & Drop](#phase-11--drag--drop)
16. [Phase 12 — Tooling Controls (Toolkit)](#phase-12--tooling-controls-toolkit)
17. [Phase 13 — Game Controls (Gamekit)](#phase-13--game-controls-gamekit)
18. [Phase 14 — Docking System](#phase-14--docking-system)
19. [Phase 15 — Framework Gaps](#phase-15--framework-gaps)
20. [Phase 16 — XML Layouts](#phase-16--xml-layouts)
21. [Appendix A — Existing Infrastructure](#appendix-a--existing-infrastructure)
22. [Appendix B — File Layout](#appendix-b--file-layout)
23. [Appendix C — Resolved Design Decisions](#appendix-c--resolved-design-decisions)
24. [Appendix D — Legacy GUI Analysis](#appendix-d--legacy-gui-analysis)
25. [Appendix E — AUI Framework Analysis](#appendix-e--aui-framework-analysis)
26. [Appendix F — Skinning Resources](#appendix-f--skinning-resources)
27. [Workflow](#workflow)

---

## Design Philosophy

| Principle | Description |
|-----------|-------------|
| **Android-inspired** | View/ViewGroup tree, measure/layout/draw passes, event bubbling/tunneling, LayoutParams for parent-child contracts. |
| **Renderer agnostic** | All painting goes through `DrawContext`. No GL/Vulkan/D3D calls in the UI layer. The renderer is plugged in externally. |
| **Platform agnostic** | UI knows nothing about SDL, Win32, or any windowing system. Platform concerns are bridged through `Sedulous.UI.Shell` adapters. |
| **Immediate-friendly** | Designed for game loops — the entire UI tree can be measured, laid out, and drawn every frame without requiring invalidation. Invalidation is a toggleable *optimization*, not a requirement. |
| **Manual memory** | Beef has no GC. Views own their children. Deferred mutation prevents use-after-free during event routing. `ElementHandle<T>` provides safe weak references. |
| **Composition over inheritance** | Prefer small, composable Views. Complex widgets are built from simpler ones (e.g., a ComboBox is a Button + Popup + ListView). |
| **Custom elements first-class** | Custom View subclasses are as well supported as built-in controls. Theming, layout, input, and serialization all work uniformly. |
| **DPI-independent** | All coordinates are in logical pixels. `UIContext.DpiScale` applies a global transform at the root. Views never deal with physical pixels. |
| **Multi-window** | UIContext supports multiple root views — one per window. Windows can be real platform windows or virtual windows within a dock layout. |
| **Arbitrary transforms** | Views support a `RenderTransform` matrix with configurable origin. Transforms affect rendering and hit-testing (via matrix inversion). |
| **Debug visualization** | A global debug-draw toggle on UIContext renders layout bounds, margins, padding, and focus indicators as overlays. |

---

## Architecture Overview

```
┌────────────────────────────────────────────────────────┐
│                    Application                          │
│            (Sandbox / Game / Tool)                      │
├──────────────────┬─────────────────────────────────────┤
│ Sedulous.UI      │ Sedulous.UI        │ Sedulous.UI    │
│ .Toolkit         │ .Gamekit           │ (core)         │
│ (PropertyGrid,   │ (HUD, HealthBar,   │                │
│  DockPanel,      │  Inventory,        │ View, Layout,  │
│  TreeView,       │  Minimap, ...)     │ Input, Theme,  │
│  TabView, ...)   │                    │ Animation, ... │
├──────────────────┴─────────────────────┴───────────────┤
│                  Sedulous.UI.Shell                      │
│    (Platform bridge: input routing, clipboard,          │
│     cursor management, window metrics)                  │
├──────────┬──────────┬──────────┬───────────────────────┤
│ Drawing  │  Fonts   │  Math    │  Foundation            │
│(DrawCtx) │(FontSvc) │(Vec,Mat) │ (EventAccessor)       │
└──────────┴──────────┴──────────┴───────────────────────┘
```

### Key Types (Preview)

| Type | Role |
|------|------|
| `View` | Base class. Has bounds, padding, margin, visibility, background, cursor type, render transform, event handlers. Knows how to measure, layout, and draw itself. |
| `ViewGroup` | A View that contains children. Manages child list, dispatches input, delegates layout to a strategy. |
| `MeasureSpec` | Constraint passed from parent to child during measurement (Exactly, AtMost, Unspecified). |
| `LayoutParams` | Per-child layout metadata (width/height request, margins, weight, gravity). Subclassed per layout type. |
| `UIContext` | Root-level state: focus owner, captured view, clipboard, font service, theme, DPI scale, mutation queue, animation manager, debug flags. Owns one or more root views. |
| `MutationQueue` | Defers tree mutations (add/remove/delete) to end of frame, preventing use-after-free during event routing. |
| `ElementHandle<T>` | Safe weak reference to a View. Uses ID lookup to detect deleted elements. |
| `Theme` | Named collection of styles. Styles are dictionaries of property values (colors, fonts, padding, drawables). |
| `Drawable` | Abstract paintable (ColorDrawable, GradientDrawable, NineSliceDrawable, StateListDrawable). Used for backgrounds, borders, icons. |

---

## Project Structure

The framework is split into three projects:

| Project | Purpose | Contains |
|---------|---------|----------|
| **Sedulous.UI** | Core framework | View, ViewGroup, layouts, input, focus, theming, drawables, animation, overlays, scrolling, adapters, EditText, basic controls (Label, Button, CheckBox, Slider, etc.) |
| **Sedulous.UI.Toolkit** | Developer tooling controls | PropertyGrid, DockPanel, TabView, SplitView, TreeView, ComboBox, Toolbar, StatusBar, LogView, NumberField, ColorPicker, Breadcrumb |
| **Sedulous.UI.Gamekit** | In-game UI controls | HUD overlays, HealthBar, Minimap, InventoryGrid, DialogBox (RPG-style), Radial Menu, Hotbar, Notification toast |

**Sedulous.UI.Tests** — Unit tests for all three projects.

All three projects depend on `Sedulous.UI` core. Custom elements can be built by subclassing `View` or `ViewGroup` from the core — the same mechanisms used by Toolkit and Gamekit.

---

## Dependency Map

```
Sedulous.UI depends on:
  - Sedulous.Drawing        (DrawContext, IBrush, IFontService, Color, BlendMode)
  - Sedulous.Fonts           (IFont, IFontAtlas, ITextShaper, GlyphPosition, CachedFont)
  - Sedulous.Mathematics     (Vector2, RectangleF, Matrix, Color)
  - Sedulous.Foundation      (EventAccessor<T>)
  - Sedulous.Xml             (optional, Phase 14 only — XML layout inflation)

Sedulous.UI.Toolkit depends on:
  - Sedulous.UI

Sedulous.UI.Gamekit depends on:
  - Sedulous.UI

None of these depend on:
  - Sedulous.Shell (or any platform/windowing system)
  - Sedulous.Drawing.OpenGL (or any renderer backend)
  - SDL3
```

---

## Phase 1 — Core View System

**Goal:** Establish the View tree, measurement, layout, drawing, deferred mutation, and debug visualization. At the end of this phase, you can create Views, arrange them, draw them, and safely delete them.

### Checklist

- [x] `MeasureSpec` struct (Exactly, AtMost, Unspecified + Resolve helper)
- [x] `LayoutParams` class (Width, Height, Margin; MatchParent/WrapContent constants)
- [x] `Thickness` struct (Left, Top, Right, Bottom, Horizontal, Vertical)
- [x] `Visibility` enum (Visible, Invisible, Gone)
- [x] `ViewId` struct (unique ID generation via atomic counter)
- [x] `ElementHandle<T>` struct (safe weak reference via ID lookup in UIContext)
- [x] `View` base class
  - [x] Identity: ViewId, parent reference, UIContext reference
  - [x] Geometry: left, top, width, height (relative to parent)
  - [x] Layout: LayoutParams, measuredWidth/Height, dirty flags
  - [x] Padding (Thickness)
  - [x] Appearance: Visibility, Alpha, ClipToBounds, IsHitTestVisible
  - [x] CursorType stored on view (EffectiveCursor walks parent chain)
  - [x] RenderTransform (Matrix) + RenderTransformOrigin (Vector2, default 0.5,0.5)
  - [x] State: Enabled, Focusable, IsTabStop, TabIndex, Focused, Hovered, Pressed
  - [x] IsPendingDeletion flag
  - [x] Measure(MeasureSpec, MeasureSpec) → calls OnMeasure
  - [x] Layout(left, top, width, height) → calls OnLayout
  - [x] Draw(DrawContext) → applies transform, opacity, calls OnDraw
  - [x] HitTest(Vector2) → accounts for RenderTransform inversion
  - [x] OnAttachedToContext / OnDetachedFromContext lifecycle callbacks
  - [x] ToLocal / ToScreen coordinate conversion
  - [x] InvalidateLayout / Invalidate
  - [x] Tooltip text (StringView)
  - [x] ContentDescription for accessibility
  - [x] MinWidth, MinHeight, MaxWidth, MaxHeight constraints
- [x] `ViewGroup` abstract class
  - [x] Child list with ownership (destructor deletes children)
  - [x] AddView, RemoveView, RemoveViewAt, RemoveAllViews, GetChildAt, ChildCount
  - [x] InsertView at index
  - [x] DetachView (remove without delete, transfer ownership to caller)
  - [x] LayoutParams factory (CreateDefaultLayoutParams / CheckLayoutParams)
  - [x] MeasureChild / MeasureChildWithMargins helpers
  - [x] OnDraw draws children in order
  - [x] HitTest checks children in reverse order (topmost first)
  - [x] Clipping support (ClipToBounds → PushClipRect)
  - [x] OnAttachedToContext / OnDetachedFromContext propagates to children
  - [x] FindViewByTag(StringView)
- [x] `UIContext` class
  - [x] Services: IFontService, IClipboard
  - [x] DPI scale (float, default 1.0)
  - [x] Root view list (multi-window: List of root ViewGroups)
  - [x] Element registry (Dictionary<ViewId, View>) for handle resolution
  - [x] RegisterElement / UnregisterElement / GetElementById
  - [x] MutationQueue (deferred add/remove/delete)
  - [x] SetSize / Update(deltaTime) / Draw(DrawContext)
  - [x] Debug drawing toggle: `bool DebugDraw`
  - [x] Debug draw overlay: layout bounds, margins (orange), padding (green), focus ring (blue)
  - [x] Dirty flag optimization toggle: `bool UseDirtyTracking` (default false)
  - [x] Cursor request (CursorType, read by UI.Shell)
  - [x] Total time tracking (for double-click, cursor blink, etc.)
- [x] `MutationQueue` class
  - [x] QueueAddChild(parent, child)
  - [x] QueueRemoveChild(parent, child, deleteAfterRemove)
  - [x] QueueDelete(element) — marks IsPendingDeletion immediately
  - [x] QueueAction(delegate void()) — deferred arbitrary action
  - [x] Process(UIContext) — executes all pending mutations at end of frame
  - [x] Tracks deleted IDs per frame to prevent double-deletion
  - [x] Clears focus/capture/hover when elements are deleted (implemented in Phase 3 — MutationQueue calls NotifyElementDeleted)
- [x] `ColorView` — simple leaf view that fills its bounds with a color (for testing)
- [x] Unit tests (Sedulous.UI.Tests project)
  - [x] MeasureSpec resolve logic
  - [x] View measure/layout lifecycle
  - [x] ViewGroup child management (add, remove, detach, clear)
  - [x] ElementHandle resolution and deletion tracking
  - [x] MutationQueue deferred operations
  - [x] Hit testing with transforms
- [x] Sandbox demo: manually create ViewGroup with colored Views, measure/layout/draw in OnRender
- [x] `FrameLayout` (simple stacking container — needed for demo, pulled forward from Phase 2)
- [x] Builds with 0 errors

---

## Phase 2 — Layout System

**Goal:** Implement layout managers that automatically position children.

### Checklist

- [x] `Gravity` flags enum (Left, Right, CenterH, Top, Bottom, CenterV, Center, Fill, FillH, FillV)
- [x] `GravityHelper` — static methods to apply gravity within bounds
- [x] `Orientation` enum (Horizontal, Vertical) *(done in Phase 1)*
- [x] `LinearLayout` ViewGroup
  - [x] Orientation, Gravity, Spacing
  - [x] LinearLayout.LayoutParams with Weight and per-child Gravity
  - [x] Two-pass measure: fixed children first, then distribute remaining space by weight
  - [x] Layout: advance cursor along main axis, cross-axis gravity
- [x] `FrameLayout` ViewGroup
  - [x] Stacks children, each positioned by gravity
  - [x] FrameLayout.LayoutParams with Gravity
  - [x] Measure: max of all children, two-pass for MatchParent children
- [x] `GridLayout` ViewGroup
  - [x] ColumnCount, RowSpacing, ColumnSpacing
  - [x] GridLayout.LayoutParams with Row, Column, RowSpan, ColumnSpan, Gravity
  - [x] Auto-assign row/column when -1
  - [ ] Support for star-sizing columns *(deferred — not needed yet)*
- [x] `AbsoluteLayout` ViewGroup
  - [x] AbsoluteLayout.LayoutParams with X, Y
  - [x] No measurement constraints on children
- [x] Unit tests (51 new tests, 118 total)
  - [x] LinearLayout horizontal/vertical with weights
  - [x] FrameLayout gravity positioning
  - [x] GridLayout row/column placement with spans
  - [x] AbsoluteLayout pixel positioning
  - [x] Nested layouts (LinearLayout inside FrameLayout)
- [x] Sandbox demo: multi-column layout with LinearLayout weights, GridLayout, FrameLayout gravity

---

## Phase 3 — Input & Focus

**Goal:** Route mouse, keyboard, and text input through the view tree. Implement focus navigation.

### 3.1 Event Flow

```
          ┌─── Tunnel Phase (top-down) ───┐
          │  OnInterceptInputEvent()       │
          │  Parent can steal the event    │
 Root ──► │                                │ ──► Target View
          │                                │
          └─── Bubble Phase (bottom-up) ───┘
              OnInputEvent()
              Handled flag stops propagation
```

### 3.2 InputManager

Separate class managing input routing, hover tracking, double-click detection. Lives in UIContext.

### Checklist

- [x] `InputManager` class
  - [x] ProcessMouseMove — hit-test, enter/leave, coordinate conversion
  - [x] ProcessMouseDown — click count/double-click, focus-on-click
  - [x] ProcessMouseUp — release tracking
  - [x] ProcessMouseWheel — bubble up through ancestors
  - [x] ProcessKeyDown — tab navigation, route to focused
  - [x] ProcessKeyUp — route to focused
  - [x] ProcessTextInput — route to focused
  - [x] Hover state tracking with enter/leave events
  - [x] Double-click detection (configurable time/distance thresholds)
  - [x] Coordinate conversion (screen → local for each element)
  - [x] OnElementDeleted — clears hover if needed
- [x] `FocusManager` class
  - [x] SetFocus / ClearFocus
  - [x] SetCapture / ReleaseCapture (mouse grab)
  - [x] FocusNext / FocusPrevious (tab navigation)
  - [x] Tab order: HTML model — TabIndex > 0 sorted first, TabIndex == 0 in tree order
  - [x] OnElementDeleted — clears focus/capture if needed
- [x] View input handler virtuals (implemented in Phase 1)
  - [x] OnMouseDown, OnMouseUp, OnMouseMove, OnMouseWheel
  - [x] OnMouseEnter, OnMouseLeave
  - [x] OnKeyDown, OnKeyUp, OnTextInput
  - [x] OnFocusGained, OnFocusLost
- [x] ViewGroup input dispatch
  - [x] OnInterceptMouseEvent — parents can steal events (for scrolling)
  - [x] Route to deepest hit child, then bubble
- [x] Cursor management
  - [x] View.CursorType property (stored on view)
  - [x] View.EffectiveCursor walks parent chain if Default
  - [x] UIContext.RequestedCursor updated during input processing
  - [x] UI.Shell reads and applies cursor to platform (Application.UpdateCursor)
- [ ] `IAcceleratorHandler` interface — for Alt+key menu shortcuts (deferred to Phase 10 — Menus)
- [x] Wire Application.ProcessUIInput to poll Shell → UIContext
- [x] Wire Application.OnTextInput to forward to UIContext
- [x] Unit tests
  - [x] Focus navigation (tab order, cycle, HTML model)
  - [x] Mouse capture routing
  - [x] Event bubbling (handled flag stops propagation)
  - [x] Enter/leave tracking
  - [x] Mouse down/up, hover, double-click detection
  - [x] Keyboard routing to focused view
  - [x] OnElementDeleted clears references
- [x] Sandbox demo: interactive panels that change color on hover/press/focus; Tab cycles focus

---

## Phase 4 — Basic Controls

**Goal:** First usable widgets. Each control is a View or ViewGroup subclass.

### Checklist

- [x] `Label` (text display)
  - [x] Text (owned String), FontSize, TextColor
  - [x] TextAlignment (Left, Center, Right), VerticalAlignment
  - [x] WordWrap *(MaxLines and TextOverflow deferred to Phase 6 text editing)*
  - [x] Measure via text shaping
- [x] `ImageView`
  - [x] IImageData Source, ScaleType (None, FitCenter, CenterCrop, FillBounds), Tint
- [x] `Button`
  - [x] Text *(Drawable Icon deferred to Phase 5 theming)*
  - [x] Visual states (Normal, Hovered, Pressed, Disabled, Focused)
  - [x] OnClick event (EventAccessor), keyboard activation (Space/Enter)
  - [ ] RepeatButton behavior (optional: fires repeatedly while held) — deferred
- [x] `ToggleButton` — button with on/off state, OnCheckedChanged event
- [x] `CheckBox` — toggle with check indicator + text
  - [x] Checked state, OnCheckedChanged event
- [x] `RadioButton` / `RadioGroup` — mutual exclusion via RadioGroup.AddRadioButton()
- [x] `Slider`
  - [x] Value, Min, Max, Step (0 = continuous)
  - [x] Horizontal/Vertical orientation
  - [x] Mouse capture for thumb drag
  - [x] OnValueChanged event
  - [x] Keyboard navigation (Arrow keys, Home/End)
- [x] `ProgressBar`
  - [x] Progress (0..1), TrackColor, FillColor
  - [ ] Indeterminate mode — deferred
- [x] `Separator` — horizontal/vertical divider line
- [x] `Panel` — FrameLayout with background, border
  - [x] CornerRadius, BorderColor, BorderWidth
- [x] `Spacer` — fixed or expanding empty space
- [x] Unit tests (48 new tests, 206 total UI tests)
  - [x] Button click handling, disabled state, keyboard activation
  - [x] CheckBox toggle, disabled state
  - [x] ToggleButton toggle, event firing
  - [x] Slider value clamping, step snapping, drag
  - [x] ProgressBar clamping, default height
  - [x] Label text properties, empty text measurement
  - [x] Separator thickness/orientation
  - [x] Panel child layout, padding
- [x] Sandbox demo: showcase all controls (Labels, Buttons, CheckBoxes, RadioGroup, Slider, ProgressBar, Panel, ImageView with procedural images)

---

## Phase 5 — Theming & Styling

**Goal:** Decouple visual appearance from control logic. Allow global and per-control styling.

### 5.1 Drawable System

| Type | Description |
|------|-------------|
| `ColorDrawable` | Solid color fill |
| `GradientDrawable` | Linear or radial gradient |
| `RoundedRectDrawable` | Rounded rect with fill, border, optional shadow |
| `NineSliceDrawable` | 9-slice image for scalable textures |
| `ImageDrawable` | Single image with tiling/stretch options |
| `ShapeDrawable` | Custom shape via draw callback |
| `StateListDrawable` | Selects child Drawable based on View state |
| `LayerDrawable` | Stacks multiple Drawables with insets |
| `InsetDrawable` | Wraps another Drawable with offsets |

### 5.2 ControlState & State Resolution

Controls have a `ControlState` enum (Normal, Hover, Pressed, Disabled, Focused) and virtual `GetState*()` methods that resolve the effective color/size for the current state. Controls override these for custom behavior. State derivation uses Palette utilities directly — no intermediate StateStyle wrapper.

The `StateListDrawable` handles background state switching (different drawable per state). For colors, controls call `Palette.ComputeHover(baseColor)` etc. at draw time. This avoids the redundant dual-system problem where both a style struct and the control do state resolution.

### 5.3 Palette

8 seed colors with automatic state derivation:

| Seed | Purpose |
|------|---------|
| Primary | Primary action color (buttons, selections) |
| Secondary | Secondary accent |
| Accent | Focus rings, highlights |
| Background | Window/root background |
| Surface | Panel/card backgrounds |
| Error | Error states, destructive actions |
| Text | Primary text color |
| Border | Default border color |

Derivation methods (static, pure functions):
- `ComputeHover(color)` → Lighten 15%
- `ComputePressed(color)` → Darken 15%
- `ComputeDisabled(color)` → Desaturate 50% + halve alpha
- `ComputeFocused(color, accent)` → Lerp 20% toward accent

Utilities: `Lighten`, `Darken`, `Desaturate`, `Lerp` — ~30 lines total.

### 5.4 Theme

A `Theme` class holds:
- A `Palette` (seed colors)
- A flat map of `(controlTypeName, propertyName) → value` for per-control-type defaults (background color, border, corner radius, padding, background image)
- Named colors and dimensions for app-level customization

Controls query the theme for initial property values at creation/attach time. State resolution happens in the control via `GetState*()` virtuals + Palette, not in the theme.

### Checklist

- [x] `Drawable` abstract class (Draw, IntrinsicSize, Padding)
- [x] `ColorDrawable`
- [x] `RoundedRectDrawable`
- [x] `StateListDrawable`
- [x] `NineSliceDrawable`
- [x] `ImageDrawable`
- [x] `LayerDrawable`
- [x] `InsetDrawable`
- [x] `GradientDrawable`
- [x] `ShapeDrawable`
- [x] `Palette` struct (8 seed colors + Lighten, Darken, Desaturate, Lerp, ComputeHover/Pressed/Disabled/Focused)
- [x] `ControlState` enum (Normal, Hover, Pressed, Disabled, Focused)
- [x] `Theme` class (Palette, per-control-type property map, named colors/dimensions)
- [x] Built-in `DarkTheme`
- [x] Built-in `LightTheme`
- [x] View.Background changed from Color? to Drawable, BackgroundColor convenience setter
- [x] UIContext.Theme property, default DarkTheme
- [x] Controls updated: `GetControlState()`, `GetStateBackground()`, `GetStateForeground()`, `GetStateBorderColor()`, `GetFocusBorderColor()` — Button, ToggleButton, CheckBox, RadioButton, Slider, ProgressBar, Panel, Separator
- [x] Unit tests (48 new, 259 total UI tests)
  - [x] StateListDrawable selects correct drawable for state, default fallback
  - [x] Palette color derivation (Lighten, Darken, Desaturate, WithAlpha, ComputeHover/Pressed/Disabled/Focused, ResolveState)
  - [x] Theme property lookup by control type, named colors/dimensions, DarkTheme/LightTheme factories
  - [x] ControlState priority (Disabled > Pressed > Focused > Hover > Normal)
- [x] Sandbox demo: T key toggles dark/light themes, status bar shows current theme
- [x] Control text colors are theme-aware (default mTextColor queries theme when not explicitly set)
- [x] Panel fills default to theme "Panel.background" when no explicit FillColor set
- [x] Sandbox labels/panels use theme defaults instead of hardcoded dark-theme colors
- [x] Kenney UI pack NineSlice demo section in Sandbox (buttons, checkboxes, stars, slider tracks)

---

## Phase 6 — Text Editing

**Goal:** Editable text input with cursor, selection, clipboard, and undo support.

### Checklist

- [x] `EditText` control
  - [x] Owned mutable String text
  - [x] Hint/placeholder text
  - [x] Single-line and multiline modes
  - [x] ReadOnly mode
  - [x] MaxLength constraint
  - [x] CursorPosition, SelectionRange
  - [x] OnTextChanged, OnSubmit events
- [x] `TextEditingBehavior` (extracted logic, reusable)
  - [x] Character insertion/deletion
  - [x] Cursor movement (arrow keys, Home, End, word boundaries)
  - [x] Text selection (Shift+Arrow, Shift+Home/End, Ctrl+A)
  - [x] Mouse click-to-position via ITextShaper.HitTest
  - [x] Mouse drag selection
  - [x] Double-click word selection, triple-click line selection
- [x] Clipboard integration (Ctrl+C, Ctrl+V, Ctrl+X)
- [x] `UndoStack` — text state snapshots with cursor position
  - [x] Ctrl+Z (undo), Ctrl+Y / Ctrl+Shift+Z (redo)
- [x] Cursor blink timer (500ms toggle)
- [x] Cursor and selection rendering via ITextShaper
- [x] `InputFilter` (Digits, HexDigits, Custom predicate)
- [x] `PasswordBox` — EditText with character masking
- [x] Unit tests
  - [x] Text insertion and deletion
  - [x] Cursor movement and selection
  - [x] Undo/redo state management
  - [x] Input filtering
  - [x] Clipboard operations (mock)
- [x] Sandbox demo: form with labeled text fields, password field

---

## Phase 7 — Scrolling & Clipping

**Goal:** Scrollable containers for content larger than its bounds.

### Checklist

- [x] `ScrollView` (vertical, horizontal, or both)
  - [x] ScrollX, ScrollY offset
  - [x] MaxScroll computed from content vs viewport
  - [x] ScrollBarPolicy (Never, Always, Auto) per axis
  - [x] Mouse wheel scrolling (configurable speed)
  - [x] Momentum/inertia scrolling (velocity + friction, configurable)
  - [x] Measures child with Unspecified spec
  - [x] Clips child with PushClipRect
  - [x] Adjusts hit-test coordinates for scroll offset
  - [ ] OnInterceptInputEvent for drag-to-scroll *(deferred — requires touch/drag gesture detection)*
- [x] `ScrollBar` view (thumb + track)
  - [x] Draggable thumb with mouse capture
  - [x] Click-on-track for page scroll
  - [x] Auto-hide when content fits
- [x] ClipToBounds on any ViewGroup (uses PushClipRect) *(existed since Phase 1)*
- [x] Unit tests
  - [x] Scroll range calculation
  - [x] Hit testing with scroll offset
  - [x] Scrollbar thumb size calculation
  - [x] Momentum decay
- [x] Sandbox demo: long list of Labels in a ScrollView

---

## Phase 8 — Data-Driven Views

**Goal:** Efficient display of large, dynamic data sets with view recycling.

### Checklist

- [x] `IListAdapter` interface + `ListAdapter` base class
  - [x] ItemCount, GetItemViewType, CreateView, BindView, RegisterObserver/UnregisterObserver
  - [x] `IAdapterObserver` interface with OnDataChanged
  - [x] `ListAdapter` base with observer management + NotifyDataChanged
- [x] `SelectionModel` class (None, Single, Multiple selection modes)
  - [x] HashSet-based O(1) lookup, OnSelectionChanged event, ShiftIndices
- [x] `ViewRecycler` — scrap pool keyed by view type
  - [x] ObtainView/RecycleView, create/recycle/reuse counters
- [x] `ListView` with view recycling
  - [x] Recycler pool (Dictionary<int32, List<View>>)
  - [x] Visible range tracking (fixed + variable item height)
  - [x] Scroll integration (internal ScrollBar + MomentumHelper)
  - [x] Fixed or variable item height
  - [x] Selection support (single, multi via SelectionModel)
  - [x] OnItemClick event + keyboard navigation (Up/Down/Home/End)
- [x] `ITreeAdapter` interface
  - [x] GetDepth, IsExpanded, HasChildren, ToggleExpand
- [x] `FlattenedTreeAdapter` — wraps ITreeAdapter as IListAdapter with depth indentation
- [x] `TreeView` (ListView + FlattenedTreeAdapter)
  - [x] Indent per depth level
  - [x] Expand/collapse toggle on click
  - [x] Selection support (via ListView's SelectionModel)
- [x] Unit tests
  - [x] SelectionModel tests (modes, events, shift indices)
  - [x] ViewRecycler tests (pool, counters, clear)
  - [x] FlattenedTreeAdapter tests (count, indentation, data propagation)
  - [x] ListView tests (recycling, visible range, scroll, selection, events, keyboard)
  - [x] TreeView tests (expand/collapse, events)
- [x] Sandbox demo: list of 10,000 items with smooth scrolling; tree with nested nodes

---

## Phase 9 — Animation

**Goal:** Smooth property transitions and visual effects.

### Checklist

- [x] `Animation` abstract base class (elapsed, duration, delay, easing, repeat, auto-reverse, OnComplete event)
- [x] `EasingFunction` — 30 preset easing functions already exist in `Sedulous.Mathematics.Easings`
- [x] `FloatAnimation`, `ColorAnimation` (Vector2Animation deferred — not needed yet)
- [x] `ViewAnimator` static helpers (FadeIn, FadeOut, FadeTo, TranslateX/Y, ScaleTo)
- [x] `AnimationManager` in UIContext (ticks each frame before view tick, removes completed, CancelForView)
- [x] `Storyboard` — sequential/parallel animation groups (nestable)
- [ ] `LayoutTransition` — animate add/remove/resize of children (deferred to future phase)
- [x] Unit tests
  - [x] FloatAnimation lifecycle (start, update, complete, delay, repeat, reset, easing)
  - [x] ColorAnimation interpolation and easing
  - [x] AnimationManager (add, tick, cancel, CancelForView, OnComplete)
  - [x] Storyboard sequencing (sequential, parallel, reset, nesting with AnimationManager)
- [x] Sandbox demo: fade/slide/bounce buttons, color pulse panel

---

## Phase 10 — Dialogs, Menus & Overlays

**Goal:** Popup UI elements that float above the main content.

### 10.1 PopupLayer

A dedicated overlay container (like the legacy GUI's PopupLayer). Popups are rendered above all content and receive input first. Positioned relative to anchor bounds with viewport clamping.

### 10.2 Modal System

ModalManager tracks a stack of modal overlays. When modal is active, input to views below is blocked. Tab navigation is trapped within the modal.

### Checklist

- [x] `PopupLayer` — overlay container for popups
  - [x] ShowPopup(popup, owner, anchorBounds, closeOnClickOutside)
  - [x] ClosePopup, CloseAllPopups, ClosePopupsOwnedBy
  - [x] HandleClickOutside — closes popup chains
  - [x] Viewport-aware positioning (below anchor, flip if needed) — via PopupPositioner
  - [x] Hit testing in reverse order (topmost first)
- [x] `ModalManager` — integrated into PopupLayer (ShowModalPopup, ModalBackdrop)
  - [x] Push/pop modal
  - [x] Backdrop rendering (dim)
  - [x] Input blocking for views below
  - [x] Tab focus trapping within modal
- [x] `Dialog`
  - [x] Title, content view, button row
  - [x] Static: Alert, Confirm, Custom
  - [x] DialogResult enum (None, OK, Cancel, Yes, No, Custom)
- [x] `ContextMenu`
  - [x] MenuItem list (Label, Action, Enabled, Separator)
  - [x] Nested submenu support with hover timing
  - [x] Show at screen position
- [x] `TooltipManager`
  - [x] Show delay (configurable, default 0.5s)
  - [x] Hides on mouse move/click
  - [x] Reads View.TooltipText
- [x] `PopupWindow` — generic popup anchored to a view
  - [x] ShowAsDropDown(anchor)
  - [x] Dismiss
- [x] `IPopupOwner` interface — notification when popup closes
- [x] Unit tests
  - [x] Popup positioning with viewport clamping
  - [x] Click-outside closing
  - [x] Modal popup tests
  - [x] Tooltip show/hide timing
- [x] Sandbox demo: buttons opening dialogs, context menus, hover tooltips
- [x] Escape key closes topmost popup

---

## Phase 11 — Drag & Drop

**Goal:** Drag and drop system for reordering, moving views, and data transfer.

### Checklist

- [x] `DragData` base class (Format string for type identification)
- [x] `IDragSource` interface (CreateDragVisual, OnDragStarted, OnDragCompleted)
- [x] `IDropTarget` interface (CanAcceptDrop, OnDragEnter, OnDragOver, OnDragLeave, OnDrop)
- [x] `DragDropEffects` enum (None, Move, Copy, Link)
- [x] `DragDropManager` class
  - [x] BeginPotentialDrag — starts on mousedown, activates after threshold (4px)
  - [x] UpdateDrag — hit-test for drop targets, enter/leave/over
  - [x] EndDrag — complete or cancel
  - [x] DragStarted / DragCompleted events
  - [x] FindDropTarget — walks up parent chain for IDropTarget
  - [x] Mouse capture during drag
- [x] `DragAdorner` — visual feedback during drag (semi-transparent preview)
- [ ] Unit tests
  - [ ] Drag threshold detection
  - [ ] Drop target enter/leave/over cycling
  - [ ] Drag cancel on element deletion
- [x] Sandbox demo: draggable colored panels that can be reordered

---

## Phase 12 — Tooling Controls (Toolkit)

**Goal:** Advanced controls for game engine tool UI. These live in `Sedulous.UI.Toolkit`.

### Checklist

- [x] `TabView` — tabbed interface with closable tabs
  - [x] Tab strip placement (top, bottom, left, right)
  - [x] OnTabChanged, OnTabClosed events
- [x] `SplitView` — resizable split between two panes
  - [x] Orientation, SplitRatio, MinPaneSize
  - [x] Draggable splitter with mouse capture
- [x] `ComboBox` — dropdown selection (Button + PopupWindow + ListView)
  - [x] IAdapter for items, SelectedIndex, Hint
  - [x] OnSelectionChanged event
- [x] `NumberField` — numeric input with spinner buttons
  - [x] Value, Min, Max, Step, DecimalPlaces
  - [x] OnValueChanged event
- [x] `Toolbar` — horizontal button strip with separators
- [x] `StatusBar` — bottom bar with status text + widgets
- [x] `Breadcrumb` — hierarchical path navigation
- [x] `LogView` — scrolling log with level filtering
- [x] `PropertyGrid` — object inspector
  - [x] Built-in editors: Float, Int, Bool, String, Color, Enum, Vector2, Range
  - [x] Collapsible categories (via Expander)
  - [x] Custom editor registration (PropertyEditor base class)
- [x] `DraggableTreeView` — TreeView with drag-to-reorder (uses DragDrop system)
- [x] `ColorPicker` — hue strip, SV square, alpha slider, hex/RGB inputs
- [x] `Expander` — collapsible section with header
- [x] `IThemeExtension` — extensible theme system for Toolkit controls (ToolkitThemeExtension)
- [x] Unit tests
  - [x] SplitView ratio clamping
  - [x] ComboBox selection
  - [x] PropertyGrid editor creation
- [x] Sandbox demo: property grid, tree view, tabs, breadcrumb, log view, color picker

---

## Phase 13 — Game Controls (Gamekit)

**Goal:** Controls optimized for in-game UI. These live in `Sedulous.UI.Gamekit`.

### Checklist

- [ ] `HealthBar` — horizontal/vertical bar with optional text overlay
- [ ] `Minimap` — image view with overlay markers
- [ ] `InventoryGrid` — grid of item slots with drag-drop
- [ ] `DialogBox` — RPG-style text box with typewriter effect
- [ ] `RadialMenu` — pie-shaped selection menu
- [ ] `Hotbar` — fixed-count item slots with keybind labels
- [ ] `NotificationToast` — auto-dismiss message with fade animation
- [ ] `CooldownOverlay` — radial sweep overlay on icons
- [ ] Unit tests
  - [ ] HealthBar value clamping
  - [ ] InventoryGrid slot management
  - [ ] NotificationToast auto-dismiss timing
- [ ] Sandbox demo: game HUD mockup with health bar, minimap, hotbar

---

## Phase 14 — Docking System

**Goal:** Multi-window docking system for editor-style layouts. Depends on Phase 12 controls (SplitView, TabView patterns) and Phase 11 (Drag & Drop).

### Checklist

- [x] `DockManager` — docking system (implements IDropTarget, IPopupOwner, IDockHost)
  - [x] Binary split tree (DockSplit)
  - [x] Tabbed groups (DockTabGroup) — tab drag to undock via IDragSource
  - [x] DockablePanel with title bar and close button — header drag to undock via IDragSource
  - [x] Dock positions: Left, Right, Top, Bottom, Center, Float
  - [x] Drag-to-dock with zone indicators (DockZoneIndicator overlay, DockTarget hit zones)
  - [x] Floating windows — dual mode:
    - [x] OS window mode: chromeless SDL windows via IFloatingWindowHost (shared GL context)
    - [x] Virtual mode: PopupLayer overlays within the same window
  - [x] FloatingWindow (implements IDockableWindow) — title bar, close button, double-click to re-dock
  - [x] Re-dock floating windows (drag panel header → zone indicators → drop to dock)
  - [x] IDropTarget integration — DockManager receives drops, resolves zone, docks panel
  - [x] Cross-window drag-to-redock for OS floating windows:
    - [x] Application routes input to main window during active drag (SDL_GetGlobalMouseState → main-window-relative coords)
    - [x] DragDropManager.mAdornerPopupLayer for stable adorner across root changes; adorner closed before OnDrop to avoid use-after-free
    - [x] UIInputHelper.ProcessMouseInput overload with explicit coordinate override
    - [x] OS floating window follows cursor during drag (SDL_SetWindowPosition)
    - [x] Window fades to 50% opacity over accepting dock zones (SDL_SetWindowOpacity)
    - [x] Cancelled drag: window stays at cursor position (no destroy+recreate)
    - [x] DragDropManager.LastGlobalX/Y for desktop-absolute cursor position
  - [x] IDockHost interface — DockablePanel/DockTabGroup use it instead of parent-chain walking
  - [x] IDockableWindow interface — FloatingWindow implements for panel detach
  - [x] IFloatingWindowHost interface — screenX/screenY params for window positioning
- [ ] Unit tests
  - [ ] DockManager dock/undock/float operations
- [x] Sandbox demo: mini editor layout with docked panels, floating windows, drag-to-dock

---

## Phase 15 — Framework Gaps

**Goal:** Fill feature gaps identified by comparing with the legacy Sedulous.GUI framework. Prioritized for game engine tooling use cases. Uses Android-inspired naming conventions consistent with our existing framework.

### 15.1 MenuBar

Top-level menu strip for editor windows (File, Edit, View, etc.). Each top-level item opens a ContextMenu dropdown. Integrates with the existing ContextMenu and PopupLayer systems.

### 15.2 FlowLayout

A layout that arranges children in a row (or column) and wraps to the next line when space runs out. Android equivalent of WPF's WrapPanel. Useful for tag displays, asset browser thumbnails, toolbar button grids.

### 15.3 Grid Star Sizing

Extend GridLayout with proportional column/row sizing. Android's GridLayout uses `Spec` objects; we add `ColumnSpec` and `RowSpec` with Auto/Fixed/Proportional modes, similar to Android's weight-based distribution.

### 15.4 Text Overflow

Add ellipsis truncation to Label (Android calls this `ellipsize`). When text exceeds available width and WordWrap is off, truncate with "..." at the end.

### 15.5 Palette Extension

Add Warning and Success seed colors to Palette. These are needed for log views, validation feedback, and status indicators in editor tooling.

### Checklist

- [ ] `MenuBar` control (Sedulous.UI.Toolkit)
  - [ ] Horizontal strip of top-level menu items
  - [ ] Click to open ContextMenu dropdown, hover to switch between open menus
  - [ ] Keyboard: Alt activates menu bar, arrow keys navigate, Enter selects, Escape closes
  - [ ] MenuBar.AddMenu(title, contextMenu)
  - [ ] Integration with IAcceleratorHandler for Alt+key shortcuts
- [ ] `FlowLayout` ViewGroup (Sedulous.UI)
  - [ ] Orientation (Horizontal wraps to next row, Vertical wraps to next column)
  - [ ] HSpacing, VSpacing (gap between items and between lines)
  - [ ] ItemAlignment (how items align within each line — start, center, end, stretch)
  - [ ] Measure: compute lines, track max cross-axis per line
  - [ ] Layout: position items in lines, wrap when exceeding main-axis extent
  - [ ] FlowLayout.LayoutParams (per-child override — none needed initially)
- [ ] `GridLayout` star sizing extension (Sedulous.UI)
  - [ ] `GridSizeMode` enum: Auto, Fixed, Proportional
  - [ ] `ColumnSpec` struct: Mode, Value (pixels for Fixed, weight for Proportional)
  - [ ] `RowSpec` struct: Mode, Value
  - [ ] GridLayout.SetColumnSpecs / SetRowSpecs
  - [ ] Measure: two-pass — Auto columns sized to content, remaining space distributed by Proportional weight
  - [ ] Backward compatible: no specs set = current behavior (equal columns)
- [ ] `Label` text overflow (Sedulous.UI)
  - [ ] `TextOverflow` enum: None, Ellipsis
  - [ ] When TextOverflow == Ellipsis and text exceeds width: measure truncated text + "...", render truncated
  - [ ] Only applies when WordWrap is false
- [ ] `Palette` — add Warning (amber/orange) and Success (green) seed colors
  - [ ] Update DarkTheme and LightTheme with appropriate default values
  - [ ] LogView updated to use Palette.Warning / Palette.Success for level colors
- [ ] `ICommand` interface + `RelayCommand` (Sedulous.UI)
  - [ ] ICommand: Execute(), CanExecute() → bool, OnCanExecuteChanged event
  - [ ] RelayCommand: delegate-based implementation
  - [ ] Button.Command property: when set, OnClick calls Execute(), Enabled tracks CanExecute()
- [ ] Unit tests
  - [ ] MenuBar open/close, keyboard navigation
  - [ ] FlowLayout wrapping, spacing, orientation
  - [ ] GridLayout proportional column sizing
  - [ ] Label ellipsis truncation
  - [ ] Palette Warning/Success colors exist and are non-zero
  - [ ] ICommand/RelayCommand execute and canExecute
- [ ] Sandbox demo: MenuBar with File/Edit/View menus, FlowLayout with wrapped items, GridLayout with proportional columns
- [ ] Builds with 0 errors

---

## Phase 16 — XML Layouts

**Goal:** Define UI layouts in XML files that are inflated at runtime.

### Checklist

- [ ] `LayoutInflater` class
  - [ ] Inflate from XML string
  - [ ] Inflate from file path
  - [ ] RegisterView<T>(tagName) for custom views
  - [ ] Property setter registry (maps attribute names to property setters)
  - [ ] LayoutParams creation from width/height/margin/gravity attributes
  - [ ] Recursive child inflation
- [ ] Built-in property parsers for Color, Thickness, Gravity, Orientation, etc.
- [ ] All built-in controls registered with inflater
- [ ] Unit tests
  - [ ] Simple layout inflation
  - [ ] Property parsing (colors, dimensions, enums)
  - [ ] Nested layouts
  - [ ] Custom view registration
- [ ] Sandbox demo: UI layout loaded from XML file

---

## Backlog — Editor & Framework Improvements

Items identified during the Banshee editor sandbox work. Prioritized for when they're needed.

### Critical for Editor

- [ ] **Drag-to-scrub on NumberField** — click+drag to adjust value continuously (standard editor UX like Unity/Unreal). Click without drag enters text edit mode.
- [ ] **TreeView multi-select** — Ctrl+Click adds to selection, Shift+Click range select. Needed for batch operations on scene hierarchy and asset browser.
- [ ] **TreeView inline rename** — F2 hotkey triggers inline text edit on selected node. Begin/Commit/Cancel API. Needed for scene hierarchy and asset browser.
- [ ] **Canvas view** — View subclass with DrawContext callback for arbitrary drawing. Needed for CurveEditor, GradientEditor, scene viewport overlay, etc.
- [ ] **Dock layout serialization** — Save/restore DockManager layout to JSON/TOML. Persist split ratios, panel positions, floating window state across sessions.
- [ ] **GridView** — Scrollable grid with adapter/recycling pattern (like ListView but N columns with wrapping). Needed for asset browser thumbnail view.

### Nice-to-Have

- [ ] **DockTabGroup tab reordering** — Drag tabs to reorder within group without undocking.
- [ ] **Color-coded vector fields** — Red=X, Green=Y, Blue=Z labels on Vector2/Vector3 editors.
- [ ] **KeyBindingManager** — Global accelerator dispatch (Ctrl+S, Alt+F, etc.) separate from menu rendering.
- [ ] **Inline hex color editor** — Hex field improvements on ColorEditor.

### Editor-Specific Controls (build in editor projects when needed)

- [ ] **CurveEditor** — Keyframe-based cubic Hermite curve editor widget.
- [ ] **GradientEditor** — Draggable color stop gradient editor widget.

---

## Appendix A — Existing Infrastructure

### Drawing (`Sedulous.Drawing`)
- `DrawContext` — Full 2D drawing API (shapes, text, images, transforms, clipping, opacity, blend modes)
- `DrawBatch` / `DrawCommand` / `DrawVertex` — Batched rendering output
- `ShapeRasterizer` — Tessellation for all 2D shapes
- `IBrush` / `SolidBrush` / `LinearGradientBrush` — Fill abstractions
- `Pen` — Stroke definition with line cap/join
- Sprites, images, nine-slice drawing

### Fonts (`Sedulous.Fonts`, `Sedulous.Drawing.Fonts`)
- `IFont` / `IFontAtlas` / `CachedFont` — Font loading and glyph atlas
- `ITextShaper` — Text shaping with kerning, wrapping, hit-test, cursor position, selection rects
- `FontService` — Font loading, caching, atlas texture creation

### Mathematics (`Sedulous.Mathematics`)
- `Vector2`, `Matrix`, `RectangleF`, `Color`

### Input (`Sedulous.UI` existing)
- `InputEventArgs` hierarchy, `KeyCode`, `KeyModifiers`, `MouseButton`, `CursorType`, `IClipboard`

### Platform Bridge (`Sedulous.UI.Shell`)
- `InputMapping`, `ShellClipboardAdapter`, `UIInputHelper`

### Events (`Sedulous.Foundation`)
- `EventAccessor<T>` — Thread-safe event subscription

---

## Appendix B — File Layout

```
Sedulous/Sedulous.UI/src/
├── View.bf
├── ViewGroup.bf
├── UIContext.bf
├── Core/
│   ├── ViewId.bf
│   ├── ElementHandle.bf
│   ├── MutationQueue.bf
│   ├── Thickness.bf
│   ├── Visibility.bf
│   ├── Orientation.bf
│   └── DebugDrawOverlay.bf
├── Layout/
│   ├── MeasureSpec.bf
│   ├── LayoutParams.bf
│   ├── Gravity.bf
│   ├── LinearLayout.bf
│   ├── FrameLayout.bf
│   ├── GridLayout.bf
│   ├── AbsoluteLayout.bf
│   └── FlowLayout.bf         (Phase 15)
├── Controls/
│   ├── ColorView.bf
│   ├── Label.bf
│   ├── ImageView.bf
│   ├── Button.bf
│   ├── ToggleButton.bf
│   ├── CheckBox.bf
│   ├── RadioButton.bf
│   ├── RadioGroup.bf
│   ├── Slider.bf
│   ├── ProgressBar.bf
│   ├── Separator.bf
│   ├── Spacer.bf
│   ├── Panel.bf
│   ├── EditText.bf
│   ├── PasswordBox.bf
│   ├── ScrollView.bf
│   ├── ScrollBar.bf
│   └── ListView.bf
├── Drawing/
│   ├── Drawable.bf
│   ├── ColorDrawable.bf
│   ├── GradientDrawable.bf
│   ├── RoundedRectDrawable.bf
│   ├── NineSliceDrawable.bf
│   ├── ImageDrawable.bf
│   ├── ShapeDrawable.bf
│   ├── StateListDrawable.bf
│   ├── LayerDrawable.bf
│   └── InsetDrawable.bf
├── Theming/
│   ├── Palette.bf
│   ├── ControlState.bf
│   ├── Theme.bf
│   ├── DarkTheme.bf
│   └── LightTheme.bf
├── Input/
│   ├── InputManager.bf
│   ├── FocusManager.bf
│   ├── DragDropManager.bf
│   ├── DragData.bf
│   ├── DragDropEffects.bf
│   ├── IDragSource.bf
│   ├── IDropTarget.bf
│   ├── DragAdorner.bf
│   ├── InputFilter.bf
│   ├── IAcceleratorHandler.bf
│   ├── FocusDirection.bf
│   ├── ICommand.bf             (Phase 15)
│   └── RelayCommand.bf         (Phase 15)
├── Editing/
│   ├── TextEditingBehavior.bf
│   └── UndoStack.bf
├── Animation/
│   ├── Animation.bf
│   ├── FloatAnimation.bf
│   ├── ColorAnimation.bf
│   ├── Vector2Animation.bf
│   ├── ViewAnimator.bf
│   ├── AnimationManager.bf
│   ├── EasingFunction.bf
│   ├── Storyboard.bf
│   └── LayoutTransition.bf
├── Overlay/
│   ├── PopupLayer.bf
│   ├── PopupInfo.bf
│   ├── IPopupOwner.bf
│   ├── PopupWindow.bf
│   ├── ModalManager.bf
│   ├── Dialog.bf
│   ├── ContextMenu.bf
│   └── TooltipManager.bf
├── Data/
│   ├── IAdapter.bf
│   ├── ITreeAdapter.bf
│   └── ISelectionModel.bf
├── RootView.bf
├── IFloatingWindowHost.bf
├── CursorType.bf          (existing)
├── IClipboard.bf          (existing)
├── InputEventArgs.bf      (existing)
└── KeyCode.bf             (existing)

Sedulous/Sedulous.UI.Toolkit/src/
├── TabView.bf
├── SplitView.bf
├── ComboBox.bf
├── NumberField.bf
├── Toolbar.bf
├── StatusBar.bf
├── Breadcrumb.bf
├── LogView.bf
├── Expander.bf
├── ColorPicker.bf
├── DraggableTreeView.bf
├── MenuBar.bf               (Phase 15)
├── ToolkitThemeExtension.bf
├── PropertyGrid/
│   ├── PropertyGrid.bf
│   ├── PropertyEditor.bf
│   ├── FloatEditor.bf
│   ├── IntEditor.bf
│   ├── BoolEditor.bf
│   ├── StringEditor.bf
│   ├── ColorEditor.bf
│   ├── EnumEditor.bf
│   ├── Vector2Editor.bf
│   └── RangeEditor.bf
└── Docking/
    ├── DockManager.bf
    ├── DockSplit.bf
    ├── DockTabGroup.bf
    ├── DockablePanel.bf
    ├── DockPosition.bf
    ├── DockPanelDragData.bf
    ├── DockZoneIndicator.bf
    ├── DockTarget.bf
    ├── FloatingWindow.bf
    ├── IDockHost.bf
    └── IDockableWindow.bf

Sedulous/Sedulous.UI.Gamekit/src/
├── HealthBar.bf
├── Minimap.bf
├── InventoryGrid.bf
├── DialogBox.bf
├── RadialMenu.bf
├── Hotbar.bf
├── NotificationToast.bf
└── CooldownOverlay.bf

Sedulous/Sedulous.UI.Tests/src/
├── Core/
│   ├── ViewTests.bf
│   ├── ViewGroupTests.bf
│   ├── MutationQueueTests.bf
│   └── ElementHandleTests.bf
├── Layout/
│   ├── MeasureSpecTests.bf
│   ├── LinearLayoutTests.bf
│   ├── FrameLayoutTests.bf
│   └── GridLayoutTests.bf
├── Input/
│   ├── InputManagerTests.bf
│   └── FocusManagerTests.bf
├── Controls/
│   ├── ButtonTests.bf
│   ├── SliderTests.bf
│   └── EditTextTests.bf
├── Theming/
│   ├── PaletteTests.bf
│   └── ThemeTests.bf
└── Animation/
    └── EasingTests.bf
```

---

## Appendix C — Resolved Design Decisions

| # | Decision | Resolution |
|---|----------|------------|
| 1 | Variant storage for Style properties | Use Beef's built-in `Variant` type from corlib. |
| 2 | View lifecycle callbacks | Yes — `OnAttachedToContext` / `OnDetachedFromContext` when added to / removed from tree. |
| 3 | Invalidation vs always-redraw | Always redraw by default. `UIContext.UseDirtyTracking` toggle for optional optimization. Game UI leaves it off; tool UI can turn it on. |
| 4 | DPI scaling | Logical pixels everywhere. `UIContext.DpiScale` applied as global root transform. |
| 5 | String ownership | Controls own `String` copies via `SetText(StringView)`. Caller doesn't keep string alive. |
| 6 | Accessibility | `View.ContentDescription` for screen readers. Hook point only for now. |
| 7 | Multi-window | Supported. UIContext holds multiple root views. Can be real platform windows or virtual windows within DockManager. |
| 8 | Touch / Gamepad | Input event system supports it. Focus navigation supports D-pad. Full support. |
| 9 | Z-order | Child order (last child draws on top). Overlays via PopupLayer. |
| 10 | Thread safety | UI runs on main thread. EventAccessor provides thread-safe subscription. Background work posts to UI thread via MutationQueue.QueueAction. |
| 11 | Cursor storage | Views store their own `CursorType`. `EffectiveCursor` walks parent chain. Context reads the effective cursor of the hovered view. |
| 12 | Deferred mutation | `MutationQueue` defers all tree mutations to end of frame. Prevents use-after-free during event routing. Elements marked `IsPendingDeletion` are skipped by handles and input. |
| 13 | Debug draw | `UIContext.DebugDraw` bool toggles debug overlay. Draws layout bounds (red), margins (orange), padding (green), focus ring (blue). |
| 14 | Custom elements | First-class. Same View/ViewGroup base, same theming, same layout, same input. Toolkit and Gamekit are built the same way user code builds custom elements. |
| 15 | Arbitrary transforms | `View.RenderTransform` (Matrix) + `View.RenderTransformOrigin` (Vector2). Affects rendering and hit-testing (via matrix inversion). |
| 16 | Theming state resolution | **No StateStyle struct.** Controls have `GetState*()` virtuals + `Palette.ComputeHover/Pressed/Disabled()`. Theme provides flat per-control-type defaults (data only, no getter logic). `StateListDrawable` handles background switching. This avoids the dual-system redundancy found in the legacy GUI. |
| 17 | Palette scope | 8 seed colors initially (Primary, Secondary, Accent, Background, Surface, Error, Text, Border). Warning and Success added in Phase 15 for tooling needs (log views, validation). TextSecondary, Link, LinkVisited not needed. |
| 18 | Kenney UI Pack | Included at `Assets/UI/`. CC0 license. 5 color variants, 82 sprites each. Used for NineSliceDrawable demos and skinned theme demos. |

---

## Appendix D — Legacy GUI Analysis

The legacy Sedulous.GUI framework (`Sedulous-Serenity`) was reviewed for ideas we might be missing. Key findings:

### Already incorporated into our plan
- **MutationQueue** — Deferred tree mutation system (add/remove/delete). Critical for Beef's manual memory.
- **ElementHandle<T>** — Safe weak reference via ID lookup. Prevents dangling pointers.
- **InputManager** — Separate class for input routing with double-click, hover tracking, coordinate conversion.
- **FocusManager** — Focus/capture management with tab navigation.
- **DragDropManager** — Full drag-drop system with drag threshold, adorner, IDragSource/IDropTarget.
- **DockManager** — Binary split tree docking with floating windows, zone indicators, drag-to-dock.
- **PopupLayer** — Overlay container with anchor positioning, click-outside closing, viewport clamping.
- **Palette** — Seed colors with automatic state derivation (hover=lighten, pressed=darken, disabled=desaturate). Trimmed from 13 to 8 seeds.
- **ControlState enum** — State-driven visual changes. Adopted directly.
- **Control.GetState*() virtuals** — Controls resolve their own state colors. Adopted directly.
- **TextEditingBehavior / UndoStack** — Reusable text editing logic.
- **RenderTransform + RenderTransformOrigin** — Arbitrary matrix transform per element.
- **ClipToBounds** — Opt-in clipping per container.
- **IsHitTestVisible** — Skip element in hit-testing (but still test children).
- **IAcceleratorHandler** — Alt+key menu shortcuts.
- **SizeDimension** — Auto/Fixed sizing (we use MatchParent/WrapContent/fixed via LayoutParams).

### Ideas NOT adopted (by user decision)
- **WPF-style architecture** (UIElement → Container → ContentControl → Decorator → Control) — Too deep. We use Android's simpler View → ViewGroup.
- **Measure/Arrange with SizeConstraints** — We use Android's MeasureSpec instead.
- **ControlTypeName string for theming** — We use Type-based lookup.
- **GUIContext as single-root** — We support multi-root for multi-window.
- **StateStyle/ControlStyle nullable-override structs** — Dual system: both the struct and controls did state resolution. Controls already have `GetState*()` virtuals that call Palette directly. The struct's getter methods were largely unused. Replaced with flat theme data + control-side state resolution.

### Gaps addressed in Phase 15
- **MenuBar** — Top-level menu strip. Essential for editor tooling. Added to Toolkit.
- **WrapPanel → FlowLayout** — Flow layout wrapping to next line. Added to core layouts.
- **Grid star sizing** — Proportional column/row sizing via ColumnSpec/RowSpec. Added to GridLayout.
- **TextTrimming → TextOverflow** — Ellipsis truncation on Label. Added to core.
- **ICommand / RelayCommand** — Command pattern for undo/redo integration. Added to core.
- **Warning/Success Palette colors** — Needed for log views and validation feedback. Added to Palette.

### Gaps not needed for our use case
- **DataGrid** — Spreadsheet-style tabular data. Not needed for game engine tooling.
- **Hyperlink** — Clickable link. Not needed (no web content in editor).
- **Flyout** — Similar to our PopupWindow.
- **MessageBox** — We have Dialog.Alert/Confirm.
- **UniformGrid** — Covered by GridLayout or FlowLayout.
- **RepeatButton** — NumberField spinner already handles this internally.
- **TileView** — Covered by ListView with grid adapter or FlowLayout.
- **DockPanel layout** — Edge-docking layout container (not drag-to-dock). Covered by nested LinearLayouts.
- **FillBehavior** — Animation HoldEnd/Reset. Game animations are fire-and-forget.
- **GameTheme** — We'd make our own engine-specific theme.
- **PasswordBox** — Already included (Phase 6).

### Legacy features we match or exceed
- **MutationQueue** — Both frameworks have full deferred mutation. Parity.
- **DragDropManager** — Both have full drag-drop. Ours adds cross-window support.
- **Docking** — Legacy is single-viewport virtual only. Ours has OS floating windows + cross-window drag.
- **Multi-window** — Legacy has none (single GUIContext, single root). Ours has multiple RootViews + per-window PopupLayer/DPI.
- **Drawables** — Legacy uses brush-based system. Ours has composable drawables (StateList, NineSlice, Layer, Inset, Gradient).
- **ViewRecycler** — Legacy has none. Ours has full view recycling for ListView.
- **Momentum scrolling** — Legacy has none. Ours has MomentumHelper with velocity/friction.
- **DPI scaling** — Legacy is global. Ours is per-window.
- **RenderTransform** — Parity (both have Matrix + origin).
- **Animation AutoReverse** — Parity (both support ping-pong).

---

## Appendix E — AUI Framework Analysis

The AUI framework (C++) was reviewed for innovative ideas. Key findings:

### Ideas already in our plan
- View hierarchy, layout system, CSS-like styling, animation, focus management, drag-drop, multi-window, devtools, scrolling, clipboard, cursor management.

### Notable ideas worth considering
- **ASS (AUI Stylesheet)** — CSS-like syntax with selectors (type, class, pseudo-state), cascading, combinators. More powerful than our Style/Theme system but significantly more complex. Could inspire a future DSL.
- **Declarative UI builder** — Fluent API for composing views in code. `Vertical { Button("OK"), Label("Hello") }` style. Beef's syntax could support this via operator overloading or builder pattern.
- **Signal-slot reactive system** — Properties that automatically update UI when data changes. More advanced than EventAccessor. Could inspire data binding.
- **IListModel / ITreeModel** — Separate model interfaces for data-driven views. Richer than our IAdapter. Has filtering, selection management, range operations.
- **Devtools panel** — Built-in development tools: layout inspector, property viewer, performance profiler, pointer debugging. Overlay toggled at runtime. Our DebugDraw is simpler; could evolve toward this.
- **AMetric** — DPI-aware measurement units (dp, sp, px, pt, mm). We use logical pixels with DpiScale; explicit unit types could be useful.
- **Mouse collision policy** — Per-view policy for how hit-testing works (margin-based, etc.).
- **Overflow enum** — Visible/Hidden/Scroll/Auto per axis. More granular than our ClipToBounds bool.
- **Word wrapping engine** — Sophisticated text layout with word-break strategies.
- **AForEachUI** — Dynamic view generation from data lists. Reactive: adds/removes views as data changes.
- **Embedding support** — Wrapping AUI inside other frameworks (AGLEmbedAuiWrap). We don't need this now but it's a good extensibility point.
- **Custom window chrome** — ACustomCaptionWindow for borderless windows with custom title bars.
- **Shimmer effect** — Loading placeholder animation (like skeleton screens).
- **A2FingerTransformArea** — Multi-touch gesture area for pinch/zoom/rotate.
- **ARulerView** — Measurement ruler widget (useful for design tools).

### Ideas NOT adopted
- **CSS selectors for styling** — Too complex for initial implementation. Our Style/Theme is simpler and sufficient.
- **Signal-slot property system** — Requires object system infrastructure Beef doesn't naturally have.
- **GPU rendering abstraction** — AUI has OpenGL renderer built in. We keep rendering external via DrawContext.

---

## Appendix F — Skinning Resources

### Kenney UI Pack (included)

**Location:** `Assets/UI/` (CC0 License — free for any use)

```
Assets/UI/
├── PNG/
│   ├── Blue/Default/    (82 sprites)
│   ├── Blue/Double/     (82 sprites, 2x resolution)
│   ├── Green/Default/
│   ├── Green/Double/
│   ├── Grey/Default/
│   ├── Grey/Double/
│   ├── Red/Default/
│   ├── Red/Double/
│   ├── Yellow/Default/
│   ├── Yellow/Double/
│   └── Extra/           (shared icons, cursor, misc)
├── Font/                (2 TTF fonts)
├── Sounds/              (6 UI sound effects)
├── Vector/              (SVG source files)
├── Preview.png
└── Sample.png
```

**Key sprites for NineSliceDrawable demos:**
- `button_rectangle_flat.png`, `button_rectangle_depth_flat.png` — button backgrounds
- `button_rectangle_border.png` — outlined button
- `slide_horizontal_color.png`, `slide_hangle.png` — slider track and thumb
- `check_square_color.png`, `check_square_color_checkmark.png` — checkbox
- `check_round_color.png` — radio button
- 5 color variants (Blue, Green, Grey, Red, Yellow) for theming demos

### Additional packs (not included)
- **[Fantasy UI Borders](https://kenney-assets.itch.io/fantasy-ui-borders)** — 9-slice borders for RPG/fantasy UIs
- **[UI Pack: Sci-Fi](https://kenney.nl/assets/ui-pack-sci-fi)** — Sci-fi themed panels and buttons

---

## Workflow

### Per-Phase Process

1. Implement all checklist items for the phase.
2. Write unit tests in `Sedulous.UI.Tests`.
3. Update the Sandbox demo to showcase new features.
4. Build with `BeefBuild` — must compile with 0 errors.
5. Run Sandbox — manually verify rendering and interaction.
6. Update this file: tick off completed checklist items.
7. Output a commit message covering the phase work.
8. Wait for user to prompt before proceeding to next phase.

### Commit Message Format

```
Phase N: <short description>

- Item 1
- Item 2
- ...

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
```
