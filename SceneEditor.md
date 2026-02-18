# Scene Editor - Phased Implementation Plan

## Context

Designing scenes by code is tedious. We need a WYSIWYG scene editor tool at `Code/Tools/SceneEditor/` alongside ModelViewer. The editor operates on live Framework `Scene` objects with full 3D rendering via the Framework's Context/Subsystem pipeline (SceneSubsystem + RenderSubsystem), using OpenDDL serialization for scene files.

Shared code (camera, gizmo, viewport blit) moves from ModelViewer into a new `Tools.Common` library. The existing `Editor/` code is preliminary and not used here.

### Architecture

```
SceneEditorApp : AppFramework.Application
├── Context (Framework)
│   ├── SceneSubsystem (manages scenes via SceneManager)
│   └── RenderSubsystem (auto-creates RenderWorld per scene via ISceneAware)
├── RenderSystem (initialized manually, injected into RenderSubsystem)
├── Render Features: DepthPrepass, GPUSkinning, ForwardOpaque, Sky, Overlay, ViewportOutput
├── List<SceneTab> (per-tab: Scene, OrbitCamera, selection, UI refs)
└── GUI: Menu bar + SplitPanel → [Hierarchy | Viewport+Tabs | Inspector]
```

The editor camera is NOT a scene entity -- it drives the RenderView directly (same as ModelViewer). Each scene tab has its own Scene (managed by SceneSubsystem), RenderWorld (created automatically by RenderSubsystem), and OrbitCamera.

### Key references
- `Code/Tools/ModelViewer/src/Program.bf` - App architecture, render setup, tab pattern, camera input, viewport rendering
- `Code/Tools/ModelViewer/src/TranslateGizmo.bf` - Gizmo system to extract
- `Code/Tools/ModelViewer/src/ViewportOutputFeature.bf` - Viewport blit feature to extract
- `Code/Tools/ModelViewer/src/ModelTab.bf` - Per-tab state isolation pattern
- `Code/Sedulous/Sedulous.Framework.Scenes/src/Scene.bf` - Entity/transform/component APIs
- `Code/Sedulous/Sedulous.Framework.Scenes/src/SceneSubsystem.bf` - Scene lifecycle management
- `Code/Sedulous/Sedulous.Framework.Scenes/src/SceneResource.bf` - Scene file I/O (OpenDDL)
- `Code/Sedulous/Sedulous.Framework.Render/src/RenderSubsystem.bf` - Auto-syncs components to RenderWorld
- `Code/Sedulous/Sedulous.AppFramework/src/Controls/ViewportControl.bf` - Existing viewport widget (manages render target, resize, image display)
- `Code/Sedulous/Sedulous.GUI/src/Controls/TreeView.bf` - For hierarchy panel
- `Code/Sedulous/Sedulous.GUI/src/Controls/PropertyGrid/PropertyGrid.bf` - For inspector panel

---

## Phase 0: Tools.Common Extraction

**Goal**: Move reusable code from ModelViewer into a shared library.

### What moves

| Class | Source File | Notes |
|-------|-----------|-------|
| `OrbitCamera` | ModelViewer/Program.bf (lines 26-117) | Pure math, no deps beyond Mathematics |
| `TranslateGizmo` + `GizmoAxis` | ModelViewer/TranslateGizmo.bf (320 lines) | Ray picking, axis drag, overlay drawing |
| `ViewportOutputFeature` | ModelViewer/ViewportOutputFeature.bf (313 lines) | Blit scene to external texture |

### Checklist

- [x] Create `Code/Tools/Tools.Common/BeefProj.toml` (Library, namespace `Tools.Common`, deps: `Sedulous.Mathematics`, `Sedulous.Render`, `Sedulous.RHI`)
- [x] Create `src/OrbitCamera.bf` - move class, change namespace
- [x] Create `src/TranslateGizmo.bf` - move class + enum, change namespace
- [x] Create `src/ViewportOutputFeature.bf` - move class, change namespace
- [x] Update `ModelViewer/BeefProj.toml` - add `Tools.Common` dependency
- [x] Update `ModelViewer/src/Program.bf` - add `using Tools.Common;`, remove inlined OrbitCamera
- [x] Update `ModelViewer/src/ModelTab.bf` - add `using Tools.Common;`
- [x] Register in `BeefSpace.toml`: add to Projects + WorkspaceFolders.Tools
- [x] Verify ModelViewer still builds and runs

### Files
- **Create**: `Code/Tools/Tools.Common/BeefProj.toml`, `src/OrbitCamera.bf`, `src/TranslateGizmo.bf`, `src/ViewportOutputFeature.bf`
- **Modify**: `Code/Tools/ModelViewer/BeefProj.toml`, `src/Program.bf`, `src/ModelTab.bf`, `Code/BeefSpace.toml`

---

## Phase 1: SceneEditor Skeleton

**Goal**: Running app with empty tabbed viewport, menu bar, side panels, Framework Context initialized.

### SceneTab (per-tab state)

```
class SceneTab
    Scene mScene                    // owned by SceneSubsystem.SceneManager
    String mName, mFilePath         // null filePath = unsaved
    OrbitCamera mCamera
    Grid mContentPanel              // per-tab UI container
    ViewportControl mViewport
    List<EntityId> mSelectedEntities
    bool mIsDirty
```

### Checklist

- [x] Create `Code/Tools/SceneEditor/BeefProj.toml`
  - Deps: `Tools.Common`, `Sedulous.AppFramework`, `Sedulous.RHI`, `Sedulous.RHI.Vulkan`, `Sedulous.Shell.SDL3`, `Sedulous.Mathematics`, `Sedulous.Render`, `Sedulous.Materials`, `Sedulous.Materials.Resources`, `Sedulous.Geometry.Resources`, `Sedulous.Textures.Resources`, `Sedulous.Framework.Core`, `Sedulous.Framework.Scenes`, `Sedulous.Framework.Render`, `Sedulous.Framework.Animation`, `Sedulous.Imaging`, `Sedulous.Imaging.SDL`, `Sedulous.Serialization`, `Sedulous.Serialization.OpenDDL`, `Sedulous.OpenDDL`, `Sedulous.Profiler`, `Sedulous.GUI`
  - StartupObject: `SceneEditor.Program`
- [x] Create `src/SceneTab.bf` - per-tab state class
- [x] Create `src/Program.bf` - `SceneEditorApp : Application` with:
  - `OnInitialize()`: Init RenderSystem, register features (DepthPrepass, GPUSkinning, ForwardOpaque, Sky, Overlay, ViewportOutput), create Context, register SceneSubsystem + RenderSubsystem, call `mContext.Startup()`
  - `OnUISetup()`: Menu bar (File: New, Open, Save, Save As, Close, Exit) + three-panel layout via SplitPanel (left hierarchy placeholder | center viewport + TabControl | right inspector placeholder)
  - `OnUpdate()`: Call `mContext.BeginFrame()`, `Update()`, `PostUpdate()`, `EndFrame()`, handle camera input on active tab
  - `OnRender()`: Set active RenderWorld, set ViewportOutputFeature output target from active tab's ViewportControl, build+execute render graph, draw overlay grid, render UI
  - `OnCleanup()`: Shutdown context, destroy tabs, shutdown render system
- [x] Register in `BeefSpace.toml`: Projects + WorkspaceFolders.Tools
- [x] Verify app launches with empty window and menu bar

### Files
- **Create**: `Code/Tools/SceneEditor/BeefProj.toml`, `src/Program.bf`, `src/SceneTab.bf`
- **Modify**: `Code/BeefSpace.toml`

---

## Phase 2: Scene Creation, Loading, Saving

**Goal**: New Scene / Open / Save working. Multiple tabs with tab switching.

### Scene lifecycle
- `SceneSubsystem.CreateScene(name)` → fires ISceneAware → RenderSubsystem auto-creates RenderWorld + RenderSceneModule
- `SceneResource.LoadFromFile(path)` → load from OpenDDL, add to SceneSubsystem
- `SceneResource.SaveToFile(path)` → write with registered component serializers

### Checklist

- [x] `NewScene()`: Create SceneTab, call `mSceneSubsystem.CreateScene(name)`, add default directional light entity + camera entity, add tab to TabControl, switch to it
- [x] `OpenScene(path)`: Create SceneResource, register component serializers (MeshRenderer, SkinnedMeshRenderer, Camera, Light, Sprite, ParticleEmitter, Decal, Trail), load from file, take scene into SceneSubsystem, create tab
- [x] `SaveScene(tab)`: Create SceneResource wrapping tab's scene, register serializers, call SaveToFile. If no filePath, prompt (text input dialog or hardcoded test path initially)
- [x] `SaveSceneAs(tab)`: Always prompts for path
- [x] `CloseTab(index)`: Prompt if dirty, unload scene from SceneSubsystem, remove tab, adjust active index
- [x] Tab switching: Set `mRenderSystem.SetActiveWorld(mRenderSubsystem.GetWorld(tab.Scene))`
- [x] File menu wiring: New → `NewScene()`, Save → `SaveScene()`, Save As → `SaveSceneAs()`, Close → `CloseTab()`
- [x] File drop support: `OnFileDrop()` opens .scene files
- [x] Tab close button on each TabItem
- [x] Dirty tracking: Mark dirty on any entity/component modification

### Files
- **Modify**: `src/Program.bf`, `src/SceneTab.bf`

---

## Phase 3: Hierarchy Panel

**Goal**: TreeView showing entity tree per tab. Add, delete, rename entities.

### Design
Hierarchy rebuilds from Scene data. Root entities (parent == Invalid) are top-level items, children nested recursively. EntityId stored on TreeViewItem via tag/custom data.

### Checklist

- [x] Create `src/HierarchyPanel.bf` - encapsulates TreeView + toolbar
  - `RebuildHierarchy(SceneTab)`: Clear tree, iterate root entities, recursively add children as nested TreeViewItems, show entity name (or "Entity_N" if unnamed)
  - Toolbar: "+" button → Add Entity submenu (Empty, Directional Light, Point Light, Spot Light, Camera)
  - Delete key → destroy selected entity + children, rebuild tree
  - Selection sync: TreeView.SelectionChanged → update `tab.SelectedEntities`
  - Right-click context menu: Add Child, Delete, Duplicate, Rename
  - Rename: F2 or context menu → inline TextBox on TreeViewItem, Enter commits, Escape cancels
  - Duplicate: Copy entity + transform + all components + children recursively to new entity
- [x] "Add Entity" creates entity with appropriate default components:
  - Empty: Just transform
  - Directional Light: Transform + LightComponent(.Directional)
  - Point Light: Transform + LightComponent(.Point)
  - Spot Light: Transform + LightComponent(.Spot)
  - Camera: Transform + CameraComponent
- [x] Hierarchy refreshes on tab switch
- [x] Hierarchy auto-rebuilds after any structural change (add/delete/reparent)
- [x] Integrate into left panel of SceneEditorApp

### Files
- **Create**: `src/HierarchyPanel.bf`
- **Modify**: `src/Program.bf`, `src/SceneTab.bf`

---

## Phase 4: Inspector Panel (Transform + Entity Name)

**Goal**: PropertyGrid showing selected entity's name and transform, editable in real-time.

### Design
PropertyGrid uses getter/setter delegates. Transform shows Position (X/Y/Z), Rotation (Euler degrees X/Y/Z), Scale (X/Y/Z). Rotation converts Quaternion <-> Euler for display.

### Checklist

- [ ] Create `src/InspectorPanel.bf` - encapsulates PropertyGrid + component sections
  - `RefreshForSelection(SceneTab)`: If no selection → clear, show "No Selection". If entity selected → build property items
  - Entity name: Editable string field at top
  - "Transform" category: Position X/Y/Z (Float), Rotation X/Y/Z as degrees (Float), Scale X/Y/Z (Float)
  - Getters read from `scene.GetTransform(entity)`
  - Setters call `scene.SetPosition()` / `scene.SetRotation()` / `scene.SetScale()`
  - Rotation: `Quaternion.ToEulerAngles()` → degrees for display, `Quaternion.CreateFromYawPitchRoll()` on set
- [ ] Selection change triggers inspector rebuild
- [ ] Inspector clears when selection empty
- [ ] Inspector reflects gizmo manipulation in real-time (reads live scene data)
- [ ] Integrate into right panel of SceneEditorApp

### Files
- **Create**: `src/InspectorPanel.bf`
- **Modify**: `src/Program.bf`

---

## Phase 5: 3D Viewport Interaction

**Goal**: Camera controls, entity picking, translate gizmo on selected entity.

### Camera controls (matching ModelViewer)
- Ctrl+LMB: Orbit rotate
- RMB: Fly mode (WASD + mouse look, Shift = sprint)
- MMB: Pan
- Scroll: Zoom
- F: Focus on selected entity

### Entity picking
1. `TranslateGizmo.CreatePickRay()` from mouse position
2. For each entity with MeshRendererComponent, compute world-space AABB from mesh bounds * world matrix
3. Ray-AABB intersection, select closest hit
4. For light/camera entities without meshes, use small proxy sphere at entity position

### Checklist

- [ ] Port camera input handling from ModelViewer's OnUpdate, operating on `tab.Camera`
- [ ] Entity picking on LMB click (without Ctrl):
  - Build pick ray from mouse pos + camera matrices
  - Test against mesh entities' world-space bounds
  - Test against light/camera entities using proxy spheres
  - Select closest hit, update selection, refresh hierarchy + inspector
- [ ] Click on empty space deselects
- [ ] TranslateGizmo integration:
  - Position at selected entity's world position
  - Gizmo hover/drag checks before entity picking
  - On drag delta → update entity position via `scene.SetPosition()`
  - RenderSceneModule auto-syncs to render proxy
- [ ] F key: Focus camera on selected entity
- [ ] Grid rendering via OverlayRenderFeature at Y=0
- [ ] Selection highlight: Wireframe box around selected entity bounds
- [ ] Gizmo drawing via OverlayRenderFeature

### Files
- **Modify**: `src/Program.bf`, `src/SceneTab.bf`

---

## Phase 6: Component Editing

**Goal**: Add/remove components on entities. Edit component properties in inspector.

### Component type registry
Maps component types to metadata: display name, category, has/add/remove delegates, and a `BuildProperties` delegate that populates PropertyGrid.

### Checklist

- [ ] Create `src/ComponentTypeRegistry.bf` with `ComponentTypeInfo` struct + registration for all known types
- [ ] "Add Component" button at bottom of inspector → dropdown of available types (excluding already-present ones)
- [ ] Remove component: Right-click on component category header → "Remove Component"
- [ ] Property builders per component:
  - **LightComponent**: Type (enum), Color (3 floats), Intensity, Range, InnerConeAngle, OuterConeAngle, CastsShadows, Enabled
  - **CameraComponent**: ProjectionType (enum), FieldOfView, NearPlane, FarPlane, Priority, Enabled
  - **MeshRendererComponent**: MeshRef path (read-only), MaterialCount, MaterialRef paths (read-only), Enabled
  - **SkinnedMeshRendererComponent**: Same as MeshRenderer + SkeletonRef
  - **SpriteComponent**: SpriteSize, Color, Enabled
- [ ] Inspector shows Transform first, then each component in collapsible category
- [ ] Component property changes auto-sync to render via RenderSceneModule

### Files
- **Create**: `src/ComponentTypeRegistry.bf`
- **Modify**: `src/InspectorPanel.bf`, `src/Program.bf`

---

## Phase 7: Scene Environment Settings

**Goal**: Edit scene-level settings when no entity selected.

### Checklist

- [ ] When selection empty, inspector shows "Scene Settings":
  - Scene name (editable)
  - Ambient Color (3 floats)
  - Ambient Intensity (float slider)
  - Exposure (float slider)
- [ ] Properties map to `mRenderSubsystem.GetWorld(tab.Scene).AmbientColor` / `.AmbientIntensity` / `.Exposure`
- [ ] Changes apply immediately to viewport

### Files
- **Modify**: `src/InspectorPanel.bf`

---

## Phase 8: Polish

**Goal**: Undo/redo, keyboard shortcuts, usability.

### Checklist

- [ ] Implement `ICommand` + `CommandHistory` (Execute/Undo with old/new value capture)
- [ ] Per-tab CommandHistory on SceneTab
- [ ] Command types: SetTransform, CreateEntity, DestroyEntity, SetComponent, AddComponent, RemoveComponent
- [ ] Wrap all modifications in commands
- [ ] Keyboard shortcuts:
  - Ctrl+Z / Ctrl+Y: Undo / Redo
  - Ctrl+S / Ctrl+Shift+S: Save / Save As
  - Ctrl+N: New Scene
  - Delete: Delete selected
  - Ctrl+D: Duplicate selected
  - F: Focus camera
- [ ] Multi-select: Ctrl+click toggle, Shift+click range in hierarchy
- [ ] Status bar: Entity count, selected count, dirty indicator
- [ ] Drag-and-drop reparenting in hierarchy (if TreeView supports it)
- [ ] W/E/R: Switch gizmo mode (Translate only initially; Rotate/Scale gizmos future work)

### Files
- **Create**: `src/Commands.bf`
- **Modify**: `src/Program.bf`, `src/SceneTab.bf`, `src/HierarchyPanel.bf`, `src/InspectorPanel.bf`

---

## BeefSpace.toml Registration

```toml
# In Projects:
"Tools.Common" = {Path = "Tools/Tools.Common"}
SceneEditor = {Path = "Tools/SceneEditor"}

# In WorkspaceFolders.Tools:
Tools = ["ModelViewer", "Tools.Common", "SceneEditor"]
```

## Verification

After each phase:
1. Build: `cd Code && BeefBuild`
2. Run SceneEditor, verify the phase's functionality
3. Run ModelViewer, verify it still works (especially after Phase 0)

End-to-end test after all phases:
1. Launch SceneEditor
2. File > New Scene → empty scene with default light
3. Add entities (empty, lights, camera) via hierarchy
4. Select entity, edit transform in inspector
5. Manipulate with gizmo in viewport
6. Add/remove components
7. Save scene, close tab, reopen → verify round-trip
8. Open multiple tabs, switch between them
