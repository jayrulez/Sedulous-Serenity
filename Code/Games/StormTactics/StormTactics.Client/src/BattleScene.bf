namespace StormTactics.Client;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.Geometry.Resources;
using Sedulous.Materials;
using Sedulous.Render;
using Sedulous.Framework.Scenes;
using Sedulous.Framework.Render;
using Sedulous.Resources;
using StormTactics.Battle;
using StormTactics.Core;

struct FloatingNumber
{
	public Vector3 mPosition;
	public float mTimer;
	public float mDuration;
	public int32 mValue;
	public bool mIsHeal;
	public bool mIsCritical;
}

enum BattleVFXType
{
	SkillCast,
	BuffApply,
	BuffRemove,
	BattleResult
}

struct BattleVFX
{
	public BattleVFXType mType;
	public Vector3 mPosition;
	public float mTimer;
	public float mDuration;
	public Color mColor;
	public String mText;
}

/// Orchestrates the visual representation of a battle.
/// Bridges BattleSimulation (pure logic) to the 3D scene.
class BattleScene
{
	// References (not owned)
	private Scene mScene;
	private RenderSystem mRenderSystem;
	private DebugRenderFeature mDebugFeature;
	private BattleSimulation mSimulation;

	// Owned sub-systems
	private HexGridRenderer mGridRenderer;
	private BattleCamera mCamera;
	private BattleAnimationSequencer mSequencer;

	// Unit views
	private List<BattleUnitView> mUnitViews = new .();

	// Shared mesh resources for placeholders
	private StaticMeshResource mAttackerMesh;
	private StaticMeshResource mDefenderMesh;

	// Materials
	private MaterialInstance mAttackerMaterial;
	private MaterialInstance mDefenderMaterial;

	// Scene entities
	private EntityId mSunEntity;
	private EntityId mCameraEntity;

	// Battle state
	private float mHexSize;
	private bool mAutoPlay;
	private float mAutoStepTimer;
	private float mAutoStepDelay = 0.1f; // Seconds between auto-steps
	private float mSpeedMultiplier = 1.0f;
	private bool mBattleStarted;
	private List<BattleEvent> mStepEvents = new .();

	// Floating numbers & VFX
	private List<FloatingNumber> mFloatingNumbers = new .();
	private List<BattleVFX> mActiveEffects = new .();

	// Hex hover detection
	private HexCoord mHoveredHex;
	private bool mHasHoveredHex;
	private int32 mHoveredUnitIndex = -1;

	public BattleCamera Camera => mCamera;
	public bool IsAutoPlaying => mAutoPlay;
	public BattleSimulation Simulation => mSimulation;
	public HexCoord HoveredHex => mHoveredHex;
	public bool HasHoveredHex => mHasHoveredHex;
	public int32 HoveredUnitIndex => mHoveredUnitIndex;

	/// Initialize the battle scene with a simulation.
	public void Initialize(
		Scene scene,
		RenderSceneModule renderModule,
		RenderSystem renderSystem,
		DebugRenderFeature debugFeature,
		BattleSimulation simulation,
		float hexSize)
	{
		mScene = scene;
		mRenderSystem = renderSystem;
		mDebugFeature = debugFeature;
		mSimulation = simulation;
		mHexSize = hexSize;

		// Create placeholder meshes — sphere for attackers, cube for defenders
		mAttackerMesh = StaticMeshResource.CreateSphere(0.3f, 12);
		mAttackerMesh.AddRef();
		mDefenderMesh = StaticMeshResource.CreateCube(0.45f);
		mDefenderMesh.AddRef();
		Console.WriteLine("[BattleScene] Using placeholder meshes: sphere=attackers, cube=defenders");

		// Create materials
		CreateMaterials();

		// Create hex grid renderer
		mGridRenderer = new HexGridRenderer(scene, renderSystem, debugFeature);
		mGridRenderer.Initialize(simulation.Grid, hexSize, simulation.Grid.Columns / 3);

		// Create camera
		mCamera = new BattleCamera();
		float cx, cz, extent;
		mGridRenderer.GetGridBounds(out cx, out cz, out extent);
		mCamera.SetGridCenter(cx, cz, extent);

		// Create camera entity for the scene
		mCameraEntity = scene.CreateEntity();
		if (renderModule != null)
		{
			let aspect = 1600.0f / 900.0f; // Will be updated each frame
			renderModule.CreatePerspectiveCamera(mCameraEntity, Math.PI_f / 4.0f, aspect, 0.1f, 100.0f);
			renderModule.SetMainCamera(mCameraEntity);
		}

		// Create sun light
		mSunEntity = scene.CreateEntity();
		{
			var transform = scene.GetTransform(mSunEntity);
			transform.Rotation = Quaternion.CreateFromAxisAngle(.(1, 0, 0), -0.8f) *
				Quaternion.CreateFromAxisAngle(.(0, 1, 0), 0.3f);
			scene.SetTransform(mSunEntity, transform);

			if (renderModule != null)
				renderModule.CreateDirectionalLight(mSunEntity, .(1.0f, 0.95f, 0.9f), 2.0f);
		}

		// Set ambient
		if (renderModule != null)
		{
			if (let world = renderModule.World)
			{
				world.AmbientColor = .(0.15f, 0.15f, 0.2f);
				world.AmbientIntensity = 1.0f;
			}
		}

		// Create unit views
		CreateUnitViews();

		// Create sequencer
		mSequencer = new BattleAnimationSequencer(mUnitViews, scene, hexSize);
		mSequencer.OnEventStarted = new => OnSequencerEvent;

		mBattleStarted = true;
	}

	/// Create materials for attacker and defender units.
	private void CreateMaterials()
	{
		if (let baseMaterial = mRenderSystem.MaterialSystem?.DefaultMaterial)
		{
			mAttackerMaterial = new MaterialInstance(baseMaterial);
			mAttackerMaterial.SetColor("BaseColor", .(0.85f, 0.25f, 0.2f, 1.0f));
			mAttackerMaterial.SetFloat("Roughness", 0.5f);

			mDefenderMaterial = new MaterialInstance(baseMaterial);
			mDefenderMaterial.SetColor("BaseColor", .(0.2f, 0.35f, 0.85f, 1.0f));
			mDefenderMaterial.SetFloat("Roughness", 0.5f);
		}
	}

	/// Create a BattleUnitView for each unit in the simulation.
	private void CreateUnitViews()
	{
		for (int32 i = 0; i < mSimulation.UnitCount; i++)
		{
			let unit = mSimulation.GetUnit(i);
			if (unit == null) continue;

			let view = new BattleUnitView();
			let material = unit.mForce == .Attacker ? mAttackerMaterial : mDefenderMaterial;

			// TODO: Try to load real model from unit.mConfig.mModelName
			// For now, use placeholder mesh with warning
			if (unit.mConfig.mModelName.Length > 0)
				Console.WriteLine("[BattleScene] Unit '{}' has model '{}' — using placeholder", unit.mConfig.mName, unit.mConfig.mModelName);

			let mesh = unit.mForce == .Attacker ? mAttackerMesh : mDefenderMesh;
			view.Initialize(mScene, i, unit.mForce, unit.mPosition, mHexSize, mesh, material);
			mUnitViews.Add(view);
		}
	}

	/// Step the simulation once and queue events for animation.
	public void StepBattle()
	{
		if (mSimulation.IsFinished) return;
		if (mSequencer.IsPlaying) return; // Wait for current animations to finish

		// Clean previous events
		for (let e in mStepEvents) delete e;
		mStepEvents.Clear();

		mSimulation.Step(mStepEvents);
		mSequencer.QueueEvents(mStepEvents);
	}

	/// Toggle auto-play mode.
	public void ToggleAutoPlay()
	{
		mAutoPlay = !mAutoPlay;
		mAutoStepTimer = 0;
	}

	/// Skip all remaining animations.
	public void SkipAnimations()
	{
		mSequencer.SkipAll();
	}

	/// Set animation speed multiplier.
	public void SetSpeed(float mult)
	{
		mSpeedMultiplier = mult;
		mSequencer.SpeedMultiplier = mult;
	}

	/// Handle input (camera + keyboard shortcuts not handled by HUD).
	public void HandleInput(Sedulous.Shell.Input.IKeyboard keyboard, Sedulous.Shell.Input.IMouse mouse, float dt)
	{
		mCamera.HandleInput(keyboard, mouse, dt);

		// Space = step once (keep as keyboard shortcut)
		if (keyboard.IsKeyPressed(.Space) && !mAutoPlay)
			StepBattle();
	}

	/// Update animations and auto-play.
	public void Update(float dt)
	{
		if (!mBattleStarted) return;

		let scaledDt = dt * mSpeedMultiplier;

		// Update camera (unscaled — camera should feel consistent)
		mCamera.Update(dt);

		// Update unit animations (scaled)
		for (let view in mUnitViews)
		{
			if (view != null)
				view.Update(mScene, scaledDt);
		}

		// Update sequencer (applies its own multiplier internally, pass raw dt)
		mSequencer.Update(dt);

		// Update floating numbers (scaled)
		for (int i = mFloatingNumbers.Count - 1; i >= 0; i--)
		{
			var num = mFloatingNumbers[i];
			num.mTimer += scaledDt;
			mFloatingNumbers[i] = num;
			if (num.mTimer >= num.mDuration)
				mFloatingNumbers.RemoveAt(i);
		}

		// Update VFX (scaled)
		for (int i = mActiveEffects.Count - 1; i >= 0; i--)
		{
			var vfx = mActiveEffects[i];
			vfx.mTimer += scaledDt;
			mActiveEffects[i] = vfx;
			if (vfx.mTimer >= vfx.mDuration)
			{
				if (vfx.mText != null)
					delete vfx.mText;
				mActiveEffects.RemoveAt(i);
			}
		}

		// Auto-play: step when animations are done (scaled)
		if (mAutoPlay && !mSimulation.IsFinished)
		{
			if (!mSequencer.IsPlaying)
			{
				mAutoStepTimer += scaledDt;
				if (mAutoStepTimer >= mAutoStepDelay)
				{
					mAutoStepTimer = 0;
					StepBattle();
				}
			}
		}

		// Auto-stop when battle ends
		if (mAutoPlay && mSimulation.IsFinished && !mSequencer.IsPlaying)
		{
			mAutoPlay = false;
		}

		// Focus camera on current active unit
		if (mSequencer.IsPlaying)
		{
			let curIdx = mSimulation.CurrentUnitIndex;
			if (curIdx >= 0 && curIdx < mUnitViews.Count)
			{
				let view = mUnitViews[curIdx];
				if (view != null && view.mVisible)
					mCamera.FocusOnWorldPos(view.mWorldPos.X, view.mWorldPos.Z);
			}
		}
	}

	/// Draw debug overlay (health bars, world-space VFX).
	public void DrawOverlay()
	{
		if (mDebugFeature == null) return;

		// Draw unit overlays (health bars, soldier counts)
		for (int32 i = 0; i < mUnitViews.Count; i++)
		{
			let view = mUnitViews[i];
			if (view == null || !view.mVisible) continue;

			let unit = mSimulation.GetUnit(i);
			view.DrawOverlay(mDebugFeature, unit);
		}

		// Draw grid overlays
		mGridRenderer.DrawOverlays();

		// Highlight current unit's hex and hovered hex
		mGridRenderer.ClearHighlights();
		if (!mSimulation.IsFinished)
		{
			let curIdx = mSimulation.CurrentUnitIndex;
			if (curIdx >= 0)
			{
				let unit = mSimulation.GetUnit(curIdx);
				if (unit != null && unit.mAlive)
					mGridRenderer.SetHighlight(unit.mPosition, .(255, 255, 100, 80));
			}
		}

		// Hovered hex highlight (cyan/white)
		if (mHasHoveredHex)
			mGridRenderer.SetHighlight(mHoveredHex, .(100, 220, 255, 60));

		// Draw floating damage/heal numbers
		DrawFloatingNumbers();

		// Draw VFX
		DrawVFX();
	}

	// --- Event callback ---

	private void OnSequencerEvent(BattleEvent ev)
	{
		switch (ev.mType)
		{
		case .DamageDealt:
			let dmgView = GetUnitView(ev.mTargetUnit);
			if (dmgView != null)
			{
				var num = FloatingNumber();
				num.mPosition = dmgView.mWorldPos + Vector3(0, 0.6f, 0);
				num.mDuration = 1.2f;
				num.mValue = ev.mValue;
				num.mIsHeal = false;
				num.mIsCritical = ev.mIsCritical;
				mFloatingNumbers.Add(num);
			}

		case .HealApplied:
			let healView = GetUnitView(ev.mTargetUnit);
			if (healView != null)
			{
				var num = FloatingNumber();
				num.mPosition = healView.mWorldPos + Vector3(0, 0.6f, 0);
				num.mDuration = 1.2f;
				num.mValue = ev.mValue;
				num.mIsHeal = true;
				mFloatingNumbers.Add(num);
			}

		case .SkillUsed:
			let casterView = GetUnitView(ev.mSourceUnit);
			if (casterView != null)
			{
				var vfx = BattleVFX();
				vfx.mType = .SkillCast;
				vfx.mPosition = casterView.mWorldPos;
				vfx.mDuration = 0.5f;
				vfx.mColor = .(255, 255, 100, 255);
				mActiveEffects.Add(vfx);
			}

		case .BuffApplied:
			let buffView = GetUnitView(ev.mTargetUnit >= 0 ? ev.mTargetUnit : ev.mSourceUnit);
			if (buffView != null)
			{
				var vfx = BattleVFX();
				vfx.mType = .BuffApply;
				vfx.mPosition = buffView.mWorldPos;
				vfx.mDuration = 0.4f;
				// Green for positive buffs, red for negative (check via buff config if available)
				vfx.mColor = .(50, 255, 100, 255);
				mActiveEffects.Add(vfx);
			}

		case .BuffRemoved:
			let debuffView = GetUnitView(ev.mSourceUnit);
			if (debuffView != null)
			{
				var vfx = BattleVFX();
				vfx.mType = .BuffRemove;
				vfx.mPosition = debuffView.mWorldPos;
				vfx.mDuration = 0.3f;
				vfx.mColor = .(200, 200, 200, 255);
				mActiveEffects.Add(vfx);
			}

		default:
		}
	}

	// --- Drawing helpers ---

	private void DrawFloatingNumbers()
	{
		let right = Vector3(1, 0, 0);
		let up = Vector3(0, 1, 0);

		for (let num in mFloatingNumbers)
		{
			let t = num.mTimer / num.mDuration;
			let alpha = (uint8)(255 * (1.0f - t));
			let yOffset = 0.5f + t * 1.5f;
			let pos = num.mPosition + Vector3(0, yOffset, 0);

			Color color;
			if (num.mIsHeal)
				color = .(50, 255, 50, alpha);
			else
				color = .(255, 50, 50, alpha);

			let scale = num.mIsCritical ? 0.012f : 0.008f;

			let text = scope String();
			if (num.mIsHeal)
				text.Append("+");
			num.mValue.ToString(text);
			if (num.mIsCritical)
				text.Append("!");

			mDebugFeature.AddTextCentered(text, pos, color, scale, right, up, .Overlay);
		}
	}

	private void DrawVFX()
	{
		for (let vfx in mActiveEffects)
		{
			let t = vfx.mTimer / vfx.mDuration;

			switch (vfx.mType)
			{
			case .SkillCast:
				let radius = 0.2f + t * 0.6f;
				let alpha = (uint8)(255 * (1.0f - t));
				let color = Color(vfx.mColor.R, vfx.mColor.G, vfx.mColor.B, alpha);
				mDebugFeature.AddCircle(vfx.mPosition, radius, .(0, 1, 0), color, 16, .DepthTest);

			case .BuffApply:
				let ringY = vfx.mPosition.Y + t * 0.8f;
				let ringAlpha = (uint8)(255 * (1.0f - t));
				let ringPos = Vector3(vfx.mPosition.X, ringY, vfx.mPosition.Z);
				let ringColor = Color(vfx.mColor.R, vfx.mColor.G, vfx.mColor.B, ringAlpha);
				mDebugFeature.AddCircle(ringPos, 0.4f, .(0, 1, 0), ringColor, 16, .DepthTest);

			case .BuffRemove:
				let shrinkRadius = 0.4f * (1.0f - t);
				let shrinkAlpha = (uint8)(255 * (1.0f - t));
				let shrinkColor = Color(vfx.mColor.R, vfx.mColor.G, vfx.mColor.B, shrinkAlpha);
				mDebugFeature.AddCircle(vfx.mPosition, shrinkRadius, .(0, 1, 0), shrinkColor, 12, .DepthTest);

			case .BattleResult:
				// Handled by BattleHUD overlay
			}
		}
	}

	private BattleUnitView GetUnitView(int32 unitIdx)
	{
		if (unitIdx < 0 || unitIdx >= mUnitViews.Count) return null;
		return mUnitViews[unitIdx];
	}

	// --- Hex hover detection ---

	/// Update hover state from mouse position using the view-projection matrix.
	public void UpdateHover(float mouseX, float mouseY, uint32 viewWidth, uint32 viewHeight, Matrix viewProjectionMatrix)
	{
		mHasHoveredHex = false;
		mHoveredUnitIndex = -1;

		if (viewWidth == 0 || viewHeight == 0) return;

		// Convert screen position to NDC (-1..1)
		// Vulkan projection (FlipProjectionRequired) already negates clip Y,
		// so NDC Y matches screen space: -1 at top, +1 at bottom.
		let ndcX = (mouseX / (float)viewWidth) * 2.0f - 1.0f;
		let ndcY = (mouseY / (float)viewHeight) * 2.0f - 1.0f;

		// Compute inverse view-projection
		Matrix invVP;
		if (!Matrix.TryInvert(viewProjectionMatrix, out invVP))
			return;

		// Unproject near and far points
		let nearPoint = Vector4(ndcX, ndcY, 0.0f, 1.0f);
		let farPoint = Vector4(ndcX, ndcY, 1.0f, 1.0f);

		var nearWorld = Vector4.Transform(nearPoint, invVP);
		var farWorld = Vector4.Transform(farPoint, invVP);

		if (Math.Abs(nearWorld.W) < 0.0001f || Math.Abs(farWorld.W) < 0.0001f)
			return;

		// Perspective divide
		let near3 = Vector3(nearWorld.X / nearWorld.W, nearWorld.Y / nearWorld.W, nearWorld.Z / nearWorld.W);
		let far3 = Vector3(farWorld.X / farWorld.W, farWorld.Y / farWorld.W, farWorld.Z / farWorld.W);

		// Ray-plane intersection with Y=0
		let rayDir = far3 - near3;
		if (Math.Abs(rayDir.Y) < 0.0001f)
			return; // Ray parallel to ground

		let t = -near3.Y / rayDir.Y;
		if (t < 0) return; // Behind camera

		let worldX = near3.X + rayDir.X * t;
		let worldZ = near3.Z + rayDir.Z * t;

		// Convert to hex coordinate
		let hex = HexCoord.FromWorld(worldX, worldZ, mHexSize);

		// Validate bounds
		if (mSimulation.Grid.InBounds(hex))
		{
			mHoveredHex = hex;
			mHasHoveredHex = true;

			// Find unit at this hex
			for (int32 i = 0; i < mSimulation.UnitCount; i++)
			{
				let unit = mSimulation.GetUnit(i);
				if (unit != null && unit.mAlive && unit.mPosition.Equals(hex))
				{
					mHoveredUnitIndex = i;
					break;
				}
			}
		}
	}

	/// Clean up resources in dependency order.
	public void Shutdown()
	{
		// 1. Sequencer — references mUnitViews
		delete mSequencer;
		mSequencer = null;

		// 2. Unit views — hold scene entity references
		DeleteContainerAndItems!(mUnitViews);
		mUnitViews = null;

		// 3. Grid renderer — has scene entities and render system refs
		mGridRenderer?.Shutdown();
		delete mGridRenderer;
		mGridRenderer = null;

		// 4. Camera — standalone
		delete mCamera;
		mCamera = null;

		// 5. Data lists
		for (let e in mStepEvents) delete e;
		delete mStepEvents;
		mStepEvents = null;

		delete mFloatingNumbers;
		mFloatingNumbers = null;

		for (let e in mActiveEffects)
			if (e.mText != null) delete e.mText;
		delete mActiveEffects;
		mActiveEffects = null;

		// 6. Materials — ReleaseRef before mesh resources
		mAttackerMaterial?.ReleaseRef();
		mAttackerMaterial = null;
		mDefenderMaterial?.ReleaseRef();
		mDefenderMaterial = null;

		// 7. Mesh resources — ReleaseRef
		mAttackerMesh?.ReleaseRef();
		mAttackerMesh = null;
		mDefenderMesh?.ReleaseRef();
		mDefenderMesh = null;
	}
}
