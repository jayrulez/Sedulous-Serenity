# Image-Based Styling for Game UI

## Overview
Add nine-slice image background support to the GUI styling system so controls can render
with textured backgrounds (ornate frames, parchment panels, etc.) instead of flat colors.

## Infrastructure (Phase 1 — Current)

- [x] Create `ImageBrush` struct in `Sedulous.Drawing` (Texture, NineSlice, Tint)
- [x] Add `BackgroundImage` field to `StateStyle`
- [x] Add `BackgroundImage` field + `GetBackgroundImage(state)` method to `ControlStyle`
- [x] Add auto-tint modulation in `GetBackgroundImage()` (lighten on hover, darken on press, fade on disable)
- [x] Add `DrawImageBrush()` convenience method to `DrawContext`
- [x] Add `BackgroundImage` property + `GetStateBackgroundImage()` method to `Control`
- [x] Modify `Control.RenderBackground()` to draw image when present (replaces color fill + border)
- [x] Modify `Button.RenderOverride()` to support image backgrounds

## Controls with Automatic Support (via RenderBackground)

These call `RenderBackground(ctx)` and get image support for free:

- [x] ContentControl (base class for Button, ToggleButton, etc.)
- [x] Decorator (Border wraps this)
- [x] Container (Panel, StackPanel, etc.)
- [x] TextBox
- [x] PasswordBox
- [x] NumericUpDown
- [x] ComboBox
- [x] Label
- [x] TextBlock
- [x] Breadcrumb
- [x] Menu
- [x] ToolBar
- [x] StatusBar
- [x] TabControl
- [x] ScrollViewer
- [x] Expander
- [x] ItemsControl (ListBox base)

## Controls Needing Manual Image Support (Deferred)

These have custom `RenderOverride()` that doesn't call `RenderBackground()`.
Each needs its own image integration:

### High Priority (common in game UI)
- [ ] ProgressBar — track background image + fill image (partial nine-slice for fill amount)
- [ ] Slider — track image + thumb image (per-state)
- [ ] ScrollBar — track image + thumb image (per-state)
- [ ] Dialog — frame/window image (nine-slice border)
- [ ] Popup — frame image
- [ ] Tooltip — frame image

### Medium Priority
- [ ] CheckBox — indicator box image (checked/unchecked/indeterminate states)
- [ ] RadioButton — indicator circle image (selected/unselected states)
- [ ] ToggleSwitch — track image + knob image (on/off states)
- [ ] ListBoxItem — selected/hover row background image
- [ ] TreeViewItem — selected/hover row background image + expander arrow image
- [ ] TileViewItem — tile background image
- [ ] TabItem (TabControl tabs) — active/inactive tab image
- [ ] ComboBox dropdown arrow — arrow image instead of drawn triangle

### Lower Priority (less visible in game UI)
- [ ] MenuItem — hover/selected row image
- [ ] MenuBarItem — hover image
- [ ] MenuSeparator — divider image
- [ ] ToolBarButton — button image (per-state)
- [ ] ToolBarToggleButton — toggle image (per-state)
- [ ] ToolBarSeparator — divider image
- [ ] Splitter — grip image
- [ ] GroupBox — frame image
- [ ] BreadcrumbItem — segment image
- [ ] StatusBarItem — item background image
- [ ] Separator — line image
- [ ] RepeatButton — same as Button (may already work via ContentControl)

### Docking System (Deferred — tooling-specific)
- [ ] DockablePanel — panel frame image
- [ ] DockablePanelHeader — title bar image
- [ ] DockTabGroup — tab strip image
- [ ] DockTab — tab image (active/inactive)
- [ ] FloatingWindow — window frame image
- [ ] DockTarget/DockSplit — overlay images

### Data Controls (Deferred — tooling-specific)
- [ ] DataGrid — grid background image
- [ ] DataGridHeader — header row image
- [ ] DataGridCell — cell background image
- [ ] PropertyGrid — grid background image
- [ ] PropertyGridCategory — category header image
- [ ] PropertyGridProperty — property row image

## Future Enhancements (Not Planned)

- [ ] Gradient brush support (linear/radial gradients as backgrounds)
- [ ] Border-only images (separate from background — e.g., glow border overlay)
- [ ] Fill images for ProgressBar (partial rendering of nine-slice)
- [ ] Animated image backgrounds (sprite sheet cycling)
- [ ] Image-based cursor themes
- [ ] Font/text shadow effects
- [ ] Control template system (full custom rendering via callbacks)
