# Sedulous Editor Roadmap

## Goal

A modular, professional game engine editor built on Sedulous.GUI. Asset-first workflow: browse, create, import, inspect, and edit assets before anything else. Multiple scenes open simultaneously, 3D viewport with gizmos, property inspection — all driven by pluggable editor modules registered at the entry point.

## Current State

### What Exists

**Editor/ (4 projects, ~60% skeleton)**
- `Sedulous.Editor.Core` — `IEditorModule`, `AssetRegistry` (editor-side, maps type→handler), `DocumentManager`, `CommandHistory`, `EditorProject` (`.sedproj`), `AssetDatabase` (scans folders, tracks `AssetEntry` by Guid+path), `RecentProjectsManager`, `EditorLogger`. Solid foundation.
- `Sedulous.Editor.App` — `EditorApplication` extends `Tools.AppFramework.Application`. Project manager view, docking layout (Project/Properties/Console panels), document tab strip. Shortcuts (Ctrl+S/Z/Y). Project open/close lifecycle. Properties and Console panels are stubs.
- `Sedulous.Editor.Scenes` — `SceneEditorModule` implements `IEditorModule`. `SceneAssetHandler` for `.scene`/`.scn` files. `SceneHierarchyPanel`, `SceneEditorView`, `EditorCamera`. Partially implemented.
- `Sedulous.Editor.Runner` — Entry point. Creates `EditorApplication`, registers `SceneEditorModule`, calls `Run()`.

**Tools/ (standalone tools, more complete)**
- `Tools.AppFramework` — Full application lifecycle (RHI + GUI integration, input, swap chain, DPI). 1200 lines, production-ready.
- `Tools.Core` — `TranslateGizmo`, `RotateGizmo`, `ScaleGizmo`, `OrbitCamera`, `ViewportOutputFeature`. Reusable.
- `Tools.SceneEditor` — Full standalone scene editor: `HierarchyPanel`, `InspectorPanel` (with Vector/Enum/Color/ResourceRef property editors), `AssetBrowserPanel`, gizmos (G/R/S keys), orbit/fly camera, multi-scene tabs, undo/redo, status bar. ~1500 lines.
- `Tools.ModelViewer` — Multi-tab model viewer with animation controls, skeleton viz. ~1000 lines.

**Sedulous.GUI (production-ready)**
- 132 files, 35k+ LOC. Docking system, PropertyGrid, TreeView, DataGrid, menus, toolbars, theming (dark/light/game), animation, drag-drop, undo stack, services. Everything needed for editor UI.

**Runtime Resource System (Foundation/Sedulous.Resources/)**
- `ResourceRegistry` — GUID↔path bidirectional mapping, thread-safe, text file format (`guid=path` per line). Multiple registries per ResourceSystem.
- `ResourceSystem` — Multi-tier loading (cache by GUID → cache by path → registry lookup → file load). Hot-reload via FileWatcher polling. 9 resource managers registered by subsystems.
- `ResourceRef` — struct with `Guid Id` + `String Path`. Used everywhere in components for resource references.
- `ResourceHandle<T>` — RAII ref-counted wrapper for safe resource passing.
- Resource managers: StaticMesh, SkinnedMesh, Skeleton, AnimationClip, PropertyAnimationClip, Material, Texture, Font, AudioClip.

### Key Problems

1. **Two separate registry systems** — Editor `AssetDatabase` (tracks files by Guid+path+type) and runtime `ResourceRegistry` (GUID↔path mapping for loading). No integration between them.
2. **Import doesn't auto-register** — `ResourceSerializer.SaveImportResult()` writes files but doesn't create registry entries. FrameworkSerialization sample manually builds registry entries after import.
3. **Re-import breaks references** — `Resource()` constructor generates fresh GUIDs. Re-importing same FBX produces new GUIDs; all scene refs to old GUIDs break.
4. **No "create asset" flow** — No way to create a blank material/scene/etc from editor. `IAssetHandler.CreateNew()` exists but isn't wired.
5. **Asset browser is file-tree only** — No thumbnails, no context menu, no create/delete/rename, no type filtering.
6. **No asset inspection** — Double-clicking an asset has no editor view for most types.

## Architecture

### Two Registries, One Truth

The editor maintains an `AssetDatabase` that IS the project's asset catalog. On build/export, it produces a runtime `ResourceRegistry` text file. During editor sessions, the `ResourceSystem` uses the `AssetDatabase` as a registry (via adapter or by populating a `ResourceRegistry` from it).

```
AssetDatabase (editor, authoritative)
  ├── Guid → AssetEntry (path, type, name, metadata)
  ├── Scan project folders for files
  ├── Stable GUIDs: import creates entry, re-import preserves existing GUID
  ├── Create/delete/rename assets
  └── Export → ResourceRegistry (text file for runtime)
         └── Stripped to just Guid=Path pairs
```

### Stable Import Identity

When importing a model:
1. Check if `AssetDatabase` already has an entry for this source path
2. If yes, reuse existing GUIDs for all derived resources (mesh, skeleton, materials, etc.)
3. If no, generate new GUIDs and register all in `AssetDatabase`
4. Store source→derived mapping so re-import preserves identity

### Module System

The entry point registers editor modules that provide functionality:

```
Editor.Runner (entry point)
  app.RegisterModule(new SceneEditorModule())    // scenes
  app.RegisterModule(new MaterialEditorModule()) // materials (future)
  app.RegisterModule(new AnimationEditorModule()) // animation (future)
  app.Run()
```

Each module implements `IEditorModule` which gets `Initialize(AssetRegistry)` to register:
- **Asset handlers** — file types the module can open/edit (+ create new)
- **Panel factories** — UI panels the module contributes
- **Gizmo plugins** — 3D viewport tools
- **Component inspectors** — custom property editors for component types
- **Menu items** — module-specific menu entries

### Asset Creation Flow

Modules register `IAssetHandler` instances that define what asset types can be created:

```
User: Right-click in Asset Browser → "Create New" → submenu shows:
  Scene     (from SceneEditorModule)
  Material  (from MaterialEditorModule, future)
  ...

Handler.CreateNew(name) → creates default resource file → registers in AssetDatabase
```

## Phases

### Phase 1: Asset Foundation

**Goal**: Working editor with project management and a functional asset browser. Create, delete, navigate, and inspect assets.

#### 1A. Project & Editor Shell

Get the editor running with a real project workflow:

1. **Verify EditorApplication starts** — project manager view, create/open project, switch to editor layout with docking.
2. **Menu bar** (minimal): File (New/Open/Save Project, Recent, Exit), Edit (Undo/Redo), View (toggle panels).
3. **Console panel** — wire `EditorLogger` messages to a scrollable log view (replace stub).
4. **Status bar** — project name, asset count.

#### 1B. Asset Browser

Make the asset browser the central hub:

1. **Tree+list view** — folder tree on left, file list on right. Navigate project's asset folders.
2. **Type icons** — per-extension icon (colored dot or letter initially: S=scene, M=material, T=texture, etc.).
3. **Context menu**:
   - **Create New** → submenu populated from registered `IAssetHandler`s that support `CreateNew()`
   - **Import** → file dialog, run `ModelImporter`, register results in `AssetDatabase`
   - **Delete** → confirm dialog, remove file + `AssetDatabase` entry
   - **Rename** → inline rename, update `AssetDatabase` path + all referencing assets (or warn)
   - **Show in Explorer** → open containing folder
4. **Search/filter** — text filter by name, type filter dropdown.
5. **Selection** — single-click selects, shows asset info in Properties panel. Double-click opens (Phase 2+).

#### 1C. AssetDatabase ↔ ResourceRegistry Integration

Bridge the editor and runtime worlds:

1. **`AssetDatabaseRegistry` adapter** — implements `IResourceRegistry`, backed by `AssetDatabase`. Register with `ResourceSystem` so runtime loading works in-editor.
2. **Stable import GUIDs** — `AssetDatabase` stores source→derived mapping. `ModelImporter` integration checks for existing entries before generating new GUIDs.
3. **Export to runtime registry** — `AssetDatabase.ExportRegistry(path)` writes a `ResourceRegistry`-format text file for standalone runtime use.

#### 1D. Asset Creation

Modules contribute creatable asset types:

1. **Expand `IAssetHandler`** (or verify existing) — `CreateNew(name, directory)` creates a default resource file on disk and returns the `IAsset`.
2. **SceneEditorModule** registers handler that creates empty `.scene` files via `SceneResource`.
3. **Future modules** register handlers for `.material`, `.animation`, etc.
4. Asset browser "Create New" context menu queries all handlers.

#### 1E. Asset Properties Panel

When an asset is selected in the browser (not opened as document):

1. **Read-only info** — GUID, path, type, file size, last modified.
2. **Resource preview** — for textures: thumbnail image. For meshes: vertex/face count. For materials: parameter summary. Basic text display initially.
3. **References** — list of assets that reference this asset (scan `AssetDatabase` for matching GUIDs). "Used by" list.

**Validation**: Create a project, see empty asset browser. Right-click → Create New → Scene → scene file appears. Import a GLTF model → meshes/textures/materials appear in browser. Delete an asset. Select asset → see properties. Close and reopen project → everything persists.

### Phase 2: Scene Editing — Merge Tools.SceneEditor

**Goal**: Open scenes from the asset browser and edit them.

1. **Move panel code** from Tools.SceneEditor into Editor.Scenes:
   - `HierarchyPanel` → `Editor.Scenes` (adapt to use DocumentManager selection)
   - `InspectorPanel` + all property editors → `Editor.Scenes`
   - Viewport rendering logic → `Editor.Scenes.SceneEditorView`
   - Gizmo integration → `Editor.Scenes`

2. **Expand IEditorModule** to support panel contribution:
   ```beef
   interface IEditorModule
   {
       StringView Name { get; }
       void Initialize(AssetRegistry registry);
       void Shutdown();
       void GetPanels(List<DockablePanel> outPanels);    // NEW
       void OnActiveDocumentChanged(IAssetDocument doc);  // NEW
       void Update(float deltaTime);                      // NEW
   }
   ```

3. **Wire SceneEditorModule** to create Hierarchy/Inspector/Viewport panels, register them with the dock manager.

4. **Engine integration** in EditorApplication — create `Context`, register subsystems (Scene, Render, Animation, Physics, Audio, Navigation). SceneEditorModule gets the Context.

5. **Double-click scene in asset browser** → opens in viewport with hierarchy/inspector.

6. **Keep Tools.SceneEditor working** as a lightweight standalone tool.

**Validation**: Open project, double-click `.scene`, see it in viewport. Select entity, edit properties, see changes. Save scene.

### Phase 3: Core Editor Infrastructure

**Goal**: Professional editor baseline.

1. **Action system** (inspired by Lumix):
   - `EditorAction` — name, shortcut, callback, category
   - Global action registry on EditorApplication
   - CommonActions: Save, Undo, Redo, Delete, Duplicate, SelectAll, transform modes

2. **Settings system** — workspace (project folder) + user (`.sedulous/`), typed get/set, settings panel.

3. **Undo/redo for scene operations** — entity CRUD, transform changes, component add/remove, property edits, command merging for gizmo drags.

4. **Entity operations** — Duplicate, Copy/Paste, Multi-select, Parent/unparent (hierarchy drag), Rename.

### Phase 4: Scene Editing Polish

**Goal**: Productive scene editing workflow.

1. **Multi-scene tabs** — multiple scenes open simultaneously, tab switching.

2. **Viewport improvements** — grid overlay, axis indicator, snap to grid, focus selection (F key), view modes.

3. **Component editing** — Add Component menu (from IComponentDataProvider), Remove Component, reset to defaults.

4. **Drag-drop from browser** — drag mesh onto viewport to create entity, drag material onto entity to assign.

### Phase 5: Asset Editors

**Goal**: Edit resources directly, not just scenes.

1. **Material editor module** — property grid for parameters, texture slot assignment, live preview.
2. **Texture viewer** — display image, mip levels, channels.
3. **Animation preview** — integrate ModelViewer's animation controls.
4. **Asset browser thumbnails** — rendered previews (meshes as 3D thumbnails, textures as images).

### Phase 6: Advanced Features

1. **Play mode** — run game logic in editor, pause/step, return to edit state.
2. **Prefab system** — save entity hierarchies as prefab assets, instantiate, break link.
3. **Profiler panel** — frame time, draw calls, entity count, memory.
4. **Scene settings panel** — edit `[ModuleSettings]` when no entity selected.
5. **Multi-viewport** — split viewport for different camera angles.

## Resource System Assessment

### What's Solid

- **ResourceRegistry** — Thread-safe, simple text format, bidirectional lookup. Good for runtime.
- **ResourceSystem** — Multi-tier cache/registry/file loading. Hot-reload works. 9 resource types.
- **ResourceRef** — GUID+path pair, serializable. Works well in components.
- **ModelImporter** — Full FBX/GLTF pipeline producing individual resource files.
- **Resource file formats** — OpenDDL text (diffable, inspectable). Binary for textures/audio.

### What Needs Improvement

| Issue | Fix | Phase |
|-------|-----|-------|
| Import doesn't create registry entries | `AssetDatabase` auto-registers on import | 1C |
| Re-import generates new GUIDs (breaks refs) | Source→derived mapping in `AssetDatabase` | 1C |
| Editor AssetDatabase ≠ runtime ResourceRegistry | `AssetDatabaseRegistry` adapter for in-editor use | 1C |
| No "create new asset" UI flow | Wire `IAssetHandler.CreateNew()` to browser context menu | 1D |
| No asset deletion/rename | Asset browser CRUD operations | 1B |
| No reference tracking ("used by") | Scan AssetDatabase for GUID matches | 1E |
| ResourceSerializer.SaveImportResult doesn't register | Move registration into import flow | 1C |

### What Doesn't Need Changing

- `ResourceSystem` core loading logic — works fine
- `ResourceRef` struct — good as-is
- `ResourceHandle<T>` ref-counting — solid
- Individual resource managers — all functional
- File formats — text-based OpenDDL is the right call

## Inspiration from Lumix (What to Adopt)

| Lumix Pattern | Sedulous Equivalent | Notes |
|---|---|---|
| IPlugin (gizmos) | Expand IEditorModule | Phase 2 |
| GUIPlugin (panels) | DockablePanel factories | Phase 2 |
| MousePlugin (viewport) | Viewport input handlers | Phase 2 |
| IAddComponentPlugin | IComponentDataProvider | Already exists |
| Action system | EditorAction + registry | Phase 3 |
| Settings (workspace/user) | Settings class | Phase 3 |
| AssetCompiler pipeline | Not needed yet | Import pipeline sufficient |
| PropertyGrid::IPlugin | Custom property editors | Already in Tools.SceneEditor |
| RenderInterface bridge | EditorRenderBridge | Phase 2 |
| Asset browser with thumbnails | Phase 5 | Icons first, thumbnails later |

## What NOT to Port from Lumix

- **ImGui dependency** — we use Sedulous.GUI (retained mode, richer widgets)
- **DLL plugin loading** — Beef is statically compiled, modules register at entry point
- **Binary scene format** — keep text-based OpenDDL (diffable, inspectable)
- **Game mode in editor** — defer to Phase 6 (complex, needs engine state snapshot/restore)
- **Asset compiler with meta files** — premature complexity; direct file-based import is simpler

## File Structure (Target)

```
Code/Editor/
├── Sedulous.Editor.Core/          (foundation: modules, assets, documents, commands, settings)
├── Sedulous.Editor.App/           (main app: docking shell, menu, console, status bar, asset browser)
├── Sedulous.Editor.Scenes/        (scene editing: hierarchy, inspector, viewport, gizmos)
├── Sedulous.Editor.Materials/     (Phase 5: material editing)
├── Sedulous.Editor.Animation/     (Phase 5: animation preview)
├── Sedulous.Editor.Runner/        (entry point: registers modules)
└── EditorRoadmap.md               (this file)
```

## Dependencies

```
Editor.Runner → Editor.App → Editor.Core → Sedulous.GUI
                           → Tools.AppFramework (Application base)
                           → Sedulous.Resources (ResourceSystem, ResourceRegistry)
Editor.Scenes → Editor.Core
              → Engine.Scenes, Engine.Render, Engine.Animation, ...
              → Tools.Core (gizmos, camera, viewport)
              → Sedulous.Render (RenderSystem, features)
```
