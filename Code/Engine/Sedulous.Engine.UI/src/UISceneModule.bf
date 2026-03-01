namespace Sedulous.Engine.UI;

using System;
using System.Collections;
using Sedulous.Engine.Scenes;
using Sedulous.Engine.Render;
using Sedulous.Render;
using Sedulous.RHI;
using Sedulous.Core.Mathematics;
using Sedulous.Shell.Input;
using Sedulous.GUI;
using Sedulous.GUI.Shell;
using Sedulous.Serialization;

/// Deferred panel creation data (from deserialization).
struct DeferredPanelData
{
	public EntityId Entity;
	public uint32 PixelWidth;
	public uint32 PixelHeight;
	public float PanelWidth;
	public float PanelHeight;
	public bool IsInteractive;
}

/// Scene module that manages world-space UI panels for a scene.
/// Created automatically by UISubsystem for each scene.
/// Panels are rendered to textures and displayed as sprites in 3D.
///
/// All UI panel data is owned by this module.
/// Components are thin handles.
class UISceneModule : SceneModule
{
	private UISubsystem mSubsystem;
	private Scene mScene;
	private List<WorldUIPanel> mPanels = new .() ~ delete _;
	private List<DeferredPanelData> mDeferredPanels = new .() ~ delete _;
	private float mTotalTime;
	private WorldUIPanel mHoveredPanel;

	/// Creates a UISceneModule linked to the given subsystem.
	public this(UISubsystem subsystem)
	{
		mSubsystem = subsystem;
	}

	/// Gets the UI subsystem.
	public UISubsystem Subsystem => mSubsystem;

	/// Gets the panels managed by this module.
	public List<WorldUIPanel> Panels => mPanels;

	/// Gets the currently hovered world panel (if any).
	public WorldUIPanel HoveredPanel => mHoveredPanel;

	/// Creates a world-space UI panel attached to an entity.
	/// The sprite proxy is created lazily during PostUpdate when the RenderWorld is available.
	/// Returns the panel, or null if resources aren't available.
	public WorldUIPanel CreateWorldUI(EntityId entity, uint32 pixelWidth, uint32 pixelHeight, float worldWidth, float worldHeight)
	{
		let device = mSubsystem.Device;
		let fontService = mSubsystem.FontService;
		let feature = mSubsystem.WorldSpaceUIFeature;

		if (device == null || fontService == null || feature == null)
			return null;

		let panel = new WorldUIPanel(device, fontService, pixelWidth, pixelHeight, worldWidth, worldHeight, mSubsystem.FrameCount, mSubsystem.RenderSystem?.ShaderSystem);
		panel.Entity = entity;
		mPanels.Add(panel);
		feature.AddPanel(panel);

		// Set thin handle on entity
		if (mScene != null)
		{
			var comp = mScene.GetComponent<WorldUIComponent>(entity);
			if (comp == null)
			{
				mScene.SetComponent<WorldUIComponent>(entity, .());
				comp = mScene.GetComponent<WorldUIComponent>(entity);
			}
			comp.InternalHandle = (int32)(mPanels.Count - 1);
		}

		// Set initial position from entity transform
		if (mScene != null && mScene.IsValid(entity))
		{
			let worldMatrix = mScene.GetWorldMatrix(entity);
			panel.UpdateTransform(worldMatrix.Translation, Quaternion.CreateFromRotationMatrix(worldMatrix));
		}

		return panel;
	}

	/// Creates a panel from serialization data (deferred — created lazily during PostUpdate).
	public void CreateWorldUIFromData(EntityId entity, WorldUIComponentData data)
	{
		if (mScene == null || !data.Enabled || data.PixelWidth == 0 || data.PixelHeight == 0)
			return;

		mDeferredPanels.Add(.() {
			Entity = entity,
			PixelWidth = data.PixelWidth,
			PixelHeight = data.PixelHeight,
			PanelWidth = data.PanelWidth,
			PanelHeight = data.PanelHeight,
			IsInteractive = data.IsInteractive
		});

		// Set thin handle on entity (will be updated when panel is actually created)
		var comp = mScene.GetComponent<WorldUIComponent>(entity);
		if (comp == null)
		{
			mScene.SetComponent<WorldUIComponent>(entity, .());
			comp = mScene.GetComponent<WorldUIComponent>(entity);
		}
	}

	/// Gets the world UI panel attached to an entity, or null if none.
	public WorldUIPanel GetPanel(EntityId entity)
	{
		for (let panel in mPanels)
		{
			if (panel.Entity == entity)
				return panel;
		}
		return null;
	}

	/// Destroys a world-space UI panel.
	public void DestroyPanel(WorldUIPanel panel)
	{
		let feature = mSubsystem.WorldSpaceUIFeature;
		if (feature != null)
			feature.RemovePanel(panel);

		// Destroy sprite proxy
		if (panel.SpriteHandle.IsValid)
		{
			let renderModule = mScene?.GetModule<RenderSceneModule>();
			let world = renderModule?.World;
			if (world != null)
				world.DestroySprite(panel.SpriteHandle);
		}

		// Reset thin handle
		if (mScene != null && mScene.IsValid(panel.Entity))
		{
			if (let comp = mScene.GetComponent<WorldUIComponent>(panel.Entity))
				comp.InternalHandle = -1;
		}

		mPanels.Remove(panel);
		panel.Dispose();
		delete panel;
	}

	public override void OnSceneCreate(Scene scene)
	{
		mScene = scene;

		// Register custom serializer
		scene.RegisterComponentSerializer(new WorldUIComponentSerializer());
	}

	public override void Update(Scene scene, float deltaTime)
	{
		mTotalTime += deltaTime;

		// Update all panel GUIContexts
		for (let panel in mPanels)
		{
			panel.GUIContext.Update(deltaTime, (double)mTotalTime);
		}
	}

	public override void PostUpdate(Scene scene, float deltaTime)
	{
		// Process deferred panel creation from deserialization
		if (mDeferredPanels.Count > 0)
		{
			for (let deferred in mDeferredPanels)
			{
				// Check if panel already exists for this entity
				bool hasPanel = false;
				for (let panel in mPanels)
				{
					if (panel.Entity == deferred.Entity)
					{
						hasPanel = true;
						break;
					}
				}

				if (!hasPanel)
				{
					let panel = CreateWorldUI(deferred.Entity, deferred.PixelWidth, deferred.PixelHeight, deferred.PanelWidth, deferred.PanelHeight);
					if (panel != null)
						panel.IsInteractive = deferred.IsInteractive;
				}
			}
			mDeferredPanels.Clear();
		}

		let renderModule = scene.GetModule<RenderSceneModule>();
		let world = renderModule?.World;

		// Sync transforms and lazily create sprite proxies
		for (let panel in mPanels)
		{
			if (!scene.IsValid(panel.Entity))
				continue;

			let worldMatrix = scene.GetWorldMatrix(panel.Entity);
			let position = worldMatrix.Translation;
			let rotation = Quaternion.CreateFromRotationMatrix(worldMatrix);
			panel.UpdateTransform(position, rotation);

			// Lazily create sprite proxy when RenderWorld becomes available
			if (world != null && !panel.SpriteHandle.IsValid && panel.TextureView != null)
			{
				let spriteHandle = world.CreateSprite();
				var sprite = world.GetSprite(spriteHandle);
				if (sprite != null)
				{
					sprite.Texture = panel.TextureView;
					sprite.Size = .(panel.PanelWidth, panel.PanelHeight);
					sprite.UVRect = .(0, 0, 1, 1);
					sprite.Color = .(1.0f, 1.0f, 1.0f, 1.0f);
					sprite.IsActive = true;
					sprite.Position = position;
				}
				panel.SpriteHandle = spriteHandle;
			}

			// Update sprite proxy position
			if (world != null && panel.SpriteHandle.IsValid)
			{
				var sprite = world.GetSprite(panel.SpriteHandle);
				if (sprite != null)
					sprite.Position = position;
			}
		}
	}

	// ==================== World Input Raycasting ====================

	/// Processes mouse input for world-space UI panels via raycasting.
	/// Called by UISubsystem when screen-space UI hasn't consumed input.
	public void ProcessWorldInput(IMouse mouse, IKeyboard keyboard, uint32 viewportWidth, uint32 viewportHeight)
	{
		if (mPanels.Count == 0 || mScene == null)
			return;

		let renderModule = mScene.GetModule<RenderSceneModule>();
		let world = renderModule?.World;
		if (world == null)
			return;

		let cameraHandle = world.MainCamera;
		if (!cameraHandle.IsValid)
			return;
		let camera = world.GetCamera(cameraHandle);
		if (camera == null)
			return;

		let ray = ScreenPointToRay(mouse.X, mouse.Y, camera, viewportWidth, viewportHeight);

		let camRight = camera.Right;
		let camUp = camera.Up;
		let camForward = camera.Forward;
		let billboardNormal = Vector3(0, 0, 0) - camForward;

		WorldUIPanel closestPanel = null;
		float closestDist = float.MaxValue;
		float closestLocalX = 0;
		float closestLocalY = 0;

		for (let panel in mPanels)
		{
			if (!panel.IsInteractive)
				continue;

			let panelD = -Vector3.Dot(billboardNormal, panel.WorldPosition);
			let plane = Plane(billboardNormal, panelD);

			let hitDist = ray.Intersects(plane);
			if (hitDist == null || hitDist.Value <= 0)
				continue;

			if (hitDist.Value >= closestDist)
				continue;

			let hitPoint = ray.Position + ray.Direction * hitDist.Value;
			let relative = hitPoint - panel.WorldPosition;
			let hitX = Vector3.Dot(relative, camRight);
			let hitY = Vector3.Dot(relative, camUp);

			let pixelX = (hitX / panel.PanelWidth + 0.5f) * (float)panel.PixelWidth;
			let pixelY = (-hitY / panel.PanelHeight + 0.5f) * (float)panel.PixelHeight;

			if (pixelX < 0 || pixelX >= (float)panel.PixelWidth || pixelY < 0 || pixelY >= (float)panel.PixelHeight)
				continue;

			closestDist = hitDist.Value;
			closestPanel = panel;
			closestLocalX = pixelX;
			closestLocalY = pixelY;
		}

		if (mHoveredPanel != null && mHoveredPanel != closestPanel)
		{
			mHoveredPanel.GUIContext.ProcessMouseMove(-1, -1);
			mHoveredPanel.MarkDirty();
		}
		mHoveredPanel = closestPanel;

		if (closestPanel != null)
		{
			let mods = keyboard != null ? InputMapping.MapModifiers(keyboard.Modifiers) : Sedulous.GUI.KeyModifiers.None;

			closestPanel.GUIContext.ProcessMouseMove(closestLocalX, closestLocalY);

			RouteWorldMouseButton(closestPanel, mouse, .Left, closestLocalX, closestLocalY, mods);
			RouteWorldMouseButton(closestPanel, mouse, .Right, closestLocalX, closestLocalY, mods);
			RouteWorldMouseButton(closestPanel, mouse, .Middle, closestLocalX, closestLocalY, mods);

			if (mouse.ScrollX != 0 || mouse.ScrollY != 0)
				closestPanel.GUIContext.ProcessMouseWheel(closestLocalX, closestLocalY, mouse.ScrollY, mods);

			closestPanel.MarkDirty();
		}
	}

	private void RouteWorldMouseButton(WorldUIPanel panel, IMouse mouse, Sedulous.Shell.Input.MouseButton shellButton, float x, float y, Sedulous.GUI.KeyModifiers mods)
	{
		let uiButton = InputMapping.MapMouseButton(shellButton);
		if (mouse.IsButtonPressed(shellButton))
			panel.GUIContext.ProcessMouseDown(x, y, uiButton, mods);
		else if (mouse.IsButtonReleased(shellButton))
			panel.GUIContext.ProcessMouseUp(x, y, uiButton, mods);
	}

	private static Ray ScreenPointToRay(float screenX, float screenY, CameraProxy* camera, uint32 viewportWidth, uint32 viewportHeight)
	{
		float ndcX = (screenX / (float)viewportWidth) * 2.0f - 1.0f;
		float ndcY = 1.0f - (screenY / (float)viewportHeight) * 2.0f;

		Vector4 nearPoint = .(ndcX, ndcY, 0.0f, 1.0f);
		Vector4 farPoint = .(ndcX, ndcY, 1.0f, 1.0f);

		let viewMatrix = Matrix.CreateLookAt(camera.Position, camera.Position + camera.Forward, camera.Up);
		let projMatrix = Matrix.CreatePerspectiveFieldOfView(camera.FieldOfView, camera.AspectRatio, camera.NearPlane, camera.FarPlane);
		let vpMatrix = viewMatrix * projMatrix;
		let invViewProj = Matrix.Invert(vpMatrix);

		var nearWorld = Vector4.Transform(nearPoint, invViewProj);
		var farWorld = Vector4.Transform(farPoint, invViewProj);

		if (Math.Abs(nearWorld.W) > 0.0001f)
			nearWorld /= nearWorld.W;
		if (Math.Abs(farWorld.W) > 0.0001f)
			farWorld /= farWorld.W;

		let rayPos = Vector3(nearWorld.X, nearWorld.Y, nearWorld.Z);
		let rayDir = Vector3.Normalize(.(farWorld.X - nearWorld.X, farWorld.Y - nearWorld.Y, farWorld.Z - nearWorld.Z));
		return .(rayPos, rayDir);
	}

	public override void OnEntityDestroyed(Scene scene, EntityId entity)
	{
		for (int i = mPanels.Count - 1; i >= 0; i--)
		{
			if (mPanels[i].Entity == entity)
			{
				let panel = mPanels[i];
				let feature = mSubsystem.WorldSpaceUIFeature;
				if (feature != null)
					feature.RemovePanel(panel);

				if (panel.SpriteHandle.IsValid)
				{
					let renderModule = scene.GetModule<RenderSceneModule>();
					let world = renderModule?.World;
					if (world != null)
						world.DestroySprite(panel.SpriteHandle);
				}

				mPanels.RemoveAt(i);
				panel.Dispose();
				delete panel;
			}
		}
	}

	public override void OnSceneDestroy(Scene scene)
	{
		let feature = mSubsystem.WorldSpaceUIFeature;

		for (let panel in mPanels)
		{
			if (feature != null)
				feature.RemovePanel(panel);
			panel.Dispose();
			delete panel;
		}
		mPanels.Clear();
		mDeferredPanels.Clear();
		mScene = null;
	}
}
