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

enum PlayerTurnPhase
{
	Idle,                // No active player input needed
	ChoosingAction,      // Action buttons shown (Move/Attack/Skill/Wait)
	SelectingMoveTarget, // Reachable cells highlighted, waiting for hex click
	PostMove,            // Unit has tentatively moved; choose Attack/Skill/Wait/Undo
	SelectingAttackTarget, // Attackable enemies highlighted, waiting for unit click
	SelectingSkill,      // Skill list shown, waiting for skill button click
	SelectingSkillTarget // Skill targets highlighted, waiting for unit click
}

/// Orchestrates the visual representation of a battle.
/// Bridges BattleSimulation (pure logic) to the 3D scene.
class BattleScene
{
	// References (not owned)
	private Scene mScene;
	private RenderSystem mRenderSystem;
	private OverlayRenderFeature mOverlayFeature;
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
	private bool mAutoStep = true;
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

	// Player turn state
	private PlayerTurnPhase mPlayerPhase = .Idle;
	private int32 mPlayerUnitIndex = -1;
	private Force mPlayerForce = .Attacker;
	private List<HexCoord> mReachableCells = new .();
	private List<int32> mAttackableUnits = new .();
	private List<int32> mUsableSkills = new .();
	private int32 mSelectedSkillId = -1;
	private List<int32> mSkillTargetUnits = new .();

	// Tentative move (PostMove state)
	private bool mHasTentativeMove;
	private HexCoord mTentativeMoveHex;
	private HexCoord mPreMovePosition;   // Original position before tentative move
	private Vector3 mPreMoveWorldPos;     // Original world position for visual undo

	// Deployment mode
	private bool mDeploymentMode;
	private int32 mDeploySelectedUnit = -1;

	public BattleCamera Camera => mCamera;
	public bool IsAutoPlaying => mAutoPlay;
	public bool IsAutoStepping => mAutoStep;

	/// Apply user settings as defaults for this battle.
	public void ApplySettings(bool autoStep, float speedMultiplier, bool invertCameraPan)
	{
		mAutoStep = autoStep;
		mSpeedMultiplier = speedMultiplier;
		if (mCamera != null)
			mCamera.InvertPan = invertCameraPan;
	}
	public bool IsDeploymentMode => mDeploymentMode;
	public BattleSimulation Simulation => mSimulation;
	public HexCoord HoveredHex => mHoveredHex;
	public bool HasHoveredHex => mHasHoveredHex;
	public int32 HoveredUnitIndex => mHoveredUnitIndex;
	public PlayerTurnPhase PlayerPhase => mPlayerPhase;
	public int32 PlayerUnitIndex => mPlayerUnitIndex;
	public bool IsPlayerTurn => mPlayerPhase != .Idle;
	public List<HexCoord> ReachableCells => mReachableCells;
	public List<int32> AttackableUnits => mAttackableUnits;
	public List<int32> UsableSkills => mUsableSkills;

	/// Initialize the battle scene with a simulation.
	public void Initialize(
		Scene scene,
		RenderSceneModule renderModule,
		RenderSystem renderSystem,
		OverlayRenderFeature overlayFeature,
		BattleSimulation simulation,
		float hexSize)
	{
		mScene = scene;
		mRenderSystem = renderSystem;
		mOverlayFeature = overlayFeature;
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
		mGridRenderer = new HexGridRenderer(scene, renderSystem, overlayFeature);
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

	/// Enter deployment mode — player can rearrange units before battle starts.
	public void EnterDeploymentMode()
	{
		mDeploymentMode = true;
		mDeploySelectedUnit = -1;

		// Zoom out slightly to show the full grid during deployment
		if (mCamera != null)
			mCamera.ZoomTo(mCamera.Distance + 5.0f);
	}

	/// Start the battle (exit deployment mode).
	public void StartBattle()
	{
		mDeploymentMode = false;
		mDeploySelectedUnit = -1;

		// Zoom back in for battle
		if (mCamera != null)
			mCamera.ZoomTo(mCamera.Distance - 5.0f);
	}

	/// Handle a hex click during deployment mode.
	/// Returns true if a swap/move occurred (views need updating).
	public bool DeploymentClickHex(HexCoord hex)
	{
		if (!mDeploymentMode) return false;

		let deployColumns = mSimulation.DeployColumns;

		// Check which unit is at the clicked hex
		int32 clickedUnit = -1;
		for (int32 i = 0; i < mSimulation.UnitCount; i++)
		{
			let unit = mSimulation.GetUnit(i);
			if (unit != null && unit.mAlive && unit.mPosition == hex)
			{
				clickedUnit = i;
				break;
			}
		}

		// No unit selected yet
		if (mDeploySelectedUnit < 0)
		{
			// Select an attacker unit
			if (clickedUnit >= 0)
			{
				let unit = mSimulation.GetUnit(clickedUnit);
				if (unit.mForce == .Attacker)
					mDeploySelectedUnit = clickedUnit;
			}
			return false;
		}

		// Already have a selection — act on click
		if (clickedUnit == mDeploySelectedUnit)
		{
			// Clicked same unit: deselect
			mDeploySelectedUnit = -1;
			return false;
		}

		// Check if target hex is in deployment zone
		let (col, _) = hex.ToOffset();
		let inDeployZone = col < deployColumns;

		if (clickedUnit >= 0)
		{
			let target = mSimulation.GetUnit(clickedUnit);
			if (target.mForce == .Attacker)
			{
				// Swap two attacker units
				if (mSimulation.SwapUnitPositions(mDeploySelectedUnit, clickedUnit))
				{
					UpdateUnitViewPosition(mDeploySelectedUnit);
					UpdateUnitViewPosition(clickedUnit);
					mDeploySelectedUnit = -1;
					return true;
				}
			}
		}
		else if (inDeployZone && mSimulation.Grid.InBounds(hex))
		{
			// Move to empty hex in deployment zone
			if (mSimulation.MoveUnitToEmpty(mDeploySelectedUnit, hex))
			{
				UpdateUnitViewPosition(mDeploySelectedUnit);
				mDeploySelectedUnit = -1;
				return true;
			}
		}

		mDeploySelectedUnit = -1;
		return false;
	}

	public int32 DeploySelectedUnit => mDeploySelectedUnit;

	/// Rebuild all unit views after RedeployAttackers() changed the unit list.
	/// Destroys existing views/entities, recreates from simulation, rebuilds sequencer.
	public void RebuildUnitViews()
	{
		// 1. Destroy all existing views (entities + view objects)
		if (mUnitViews != null && mScene != null)
		{
			for (let view in mUnitViews)
			{
				if (view != null)
					mScene.DestroyEntity(view.mEntityId);
			}
		}
		DeleteContainerAndItems!(mUnitViews);
		mUnitViews = new List<BattleUnitView>();

		// 2. Recreate unit views from current simulation state
		CreateUnitViews();

		// 3. Rebuild sequencer — transfer OnEventStarted delegate
		let existingDelegate = mSequencer.OnEventStarted;
		mSequencer.OnEventStarted = null; // Prevent delete in destructor
		delete mSequencer;
		mSequencer = new BattleAnimationSequencer(mUnitViews, mScene, mHexSize);
		mSequencer.OnEventStarted = existingDelegate;
		mSequencer.SpeedMultiplier = mSpeedMultiplier;

		// 4. Reset deployment selection
		mDeploySelectedUnit = -1;
	}

	/// Update a unit view's world position to match its simulation position.
	private void UpdateUnitViewPosition(int32 unitIdx)
	{
		let unit = mSimulation.GetUnit(unitIdx);
		let view = GetUnitView(unitIdx);
		if (unit == null || view == null) return;

		let (wx, wz) = unit.mPosition.ToWorld(mHexSize);
		view.mWorldPos = .(wx, view.mWorldPos.Y, wz);
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
	/// If it's a player unit's turn (and auto-play is off), enters player input mode.
	public void StepBattle()
	{
		if (mDeploymentMode) return; // Don't step during deployment
		if (mSimulation.IsFinished) return;
		if (mSequencer.IsPlaying) return; // Wait for current animations to finish
		if (mPlayerPhase != .Idle) return; // Don't step during player input

		// Clean previous events
		for (let e in mStepEvents) delete e;
		mStepEvents.Clear();

		let unitIdx = mSimulation.BeginTurn(mStepEvents);
		mSequencer.QueueEvents(mStepEvents);

		if (unitIdx < 0) return; // Stun skip, draw, or finished

		let unit = mSimulation.GetUnit(unitIdx);

		// Player's turn (and auto-play is off)?
		if (!mAutoPlay && unit.mForce == mPlayerForce)
		{
			mPlayerUnitIndex = unitIdx;
			mPlayerPhase = .ChoosingAction;
			ComputePlayerOptions();
			// Focus camera on the player's unit
			let view = GetUnitView(unitIdx);
			if (view != null)
				mCamera.FocusOnWorldPos(view.mWorldPos.X, view.mWorldPos.Z);
			return; // Wait for player input
		}

		// AI turn — decide and execute immediately
		for (let e in mStepEvents) delete e;
		mStepEvents.Clear();
		let action = BattleAI.DecideAction(mSimulation, unitIdx, mSimulation.Difficulty);
		mSimulation.SubmitAction(action, mStepEvents);
		mSequencer.QueueEvents(mStepEvents);
	}

	/// Toggle auto-play mode.
	public void ToggleAutoPlay()
	{
		mAutoPlay = !mAutoPlay;
		mAutoStepTimer = 0;

		// If toggling auto ON during player's turn, let AI take over
		if (mAutoPlay && mPlayerPhase != .Idle)
		{
			if (mHasTentativeMove)
				ResetTentativeMove();
			mHasTentativeMove = false;
			let action = BattleAI.DecideAction(mSimulation, mPlayerUnitIndex, mSimulation.Difficulty);
			SubmitPlayerAction(action);
		}
	}

	/// Toggle auto-step mode (auto-advances turns but player still controls their units).
	public void ToggleAutoStep()
	{
		mAutoStep = !mAutoStep;
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

		// Space = step once (keep as keyboard shortcut, only when not in player turn)
		if (keyboard.IsKeyPressed(.Space) && !mAutoPlay && mPlayerPhase == .Idle)
			StepBattle();
	}

	// --- Player turn actions ---

	/// Compute what the player's unit can do this turn.
	private void ComputePlayerOptions()
	{
		mSimulation.GetReachableCells(mPlayerUnitIndex, mReachableCells);
		mSimulation.GetAttackableUnits(mPlayerUnitIndex, mAttackableUnits);
		mSimulation.GetUsableSkills(mPlayerUnitIndex, mUsableSkills);
	}

	/// Player chose "Move" — enter move target selection.
	public void PlayerSelectMove()
	{
		if (mPlayerPhase != .ChoosingAction) return;
		mPlayerPhase = .SelectingMoveTarget;
	}

	/// Player chose "Attack" — enter attack target selection.
	public void PlayerSelectAttack()
	{
		if (mPlayerPhase != .ChoosingAction && mPlayerPhase != .PostMove) return;
		mPlayerPhase = .SelectingAttackTarget;
	}

	/// Player chose "Skill" — enter skill list selection.
	public void PlayerSelectSkill()
	{
		if (mPlayerPhase != .ChoosingAction && mPlayerPhase != .PostMove) return;
		mPlayerPhase = .SelectingSkill;
	}

	/// Player picked a specific skill — compute targets and enter target selection.
	public void PlayerChooseSkill(int32 skillId)
	{
		if (mPlayerPhase != .SelectingSkill) return;
		mSelectedSkillId = skillId;
		mSimulation.GetSkillTargets(mPlayerUnitIndex, skillId, mSkillTargetUnits);
		mPlayerPhase = .SelectingSkillTarget;
	}

	/// Player chose "Wait" — end turn (with optional pre-move).
	public void PlayerWait()
	{
		if (mPlayerPhase == .PostMove)
		{
			// Committed move + wait: submit compound action
			ResetTentativeMove();
			SubmitPlayerAction(BattleAction.MakeMoveAndWait(mPlayerUnitIndex, mTentativeMoveHex));
		}
		else if (mPlayerPhase == .ChoosingAction)
		{
			SubmitPlayerAction(BattleAction.MakeWait(mPlayerUnitIndex));
		}
	}

	/// Player clicked "Undo" — revert tentative move and go back to ChoosingAction.
	public void PlayerUndoMove()
	{
		if (!mHasTentativeMove) return;
		ResetTentativeMove();
		mHasTentativeMove = false;
		mPlayerPhase = .ChoosingAction;
		ComputePlayerOptions(); // Recompute from original position
	}

	/// Player clicked "Cancel" — go back one phase.
	public void PlayerCancelAction()
	{
		if (mPlayerPhase == .SelectingSkillTarget)
			mPlayerPhase = .SelectingSkill;
		else if (mPlayerPhase == .SelectingSkill || mPlayerPhase == .SelectingAttackTarget)
			mPlayerPhase = mHasTentativeMove ? .PostMove : .ChoosingAction;
		else if (mPlayerPhase == .SelectingMoveTarget)
			mPlayerPhase = .ChoosingAction;
	}

	/// Reset the unit view back to its pre-move position.
	private void ResetTentativeMove()
	{
		if (!mHasTentativeMove) return;
		let view = GetUnitView(mPlayerUnitIndex);
		if (view != null)
		{
			view.mWorldPos = mPreMoveWorldPos;
			view.mAnimState = .Idle;
		}
	}

	/// Player clicked a hex on the grid during a selection phase.
	public void PlayerClickHex(HexCoord hex)
	{
		switch (mPlayerPhase)
		{
		case .SelectingMoveTarget:
			if (mReachableCells.Contains(hex))
			{
				// Tentative move — don't submit yet, enter PostMove phase
				let unit = mSimulation.GetUnit(mPlayerUnitIndex);
				mPreMovePosition = unit.mPosition;
				mTentativeMoveHex = hex;
				mHasTentativeMove = true;

				// Snap unit view to tentative position
				let view = GetUnitView(mPlayerUnitIndex);
				if (view != null)
				{
					mPreMoveWorldPos = view.mWorldPos;
					let (wx, wz) = hex.ToWorld(mHexSize);
					view.mWorldPos = .(wx, mPreMoveWorldPos.Y, wz);
				}

				// Recompute targets from tentative position
				mSimulation.GetAttackableUnitsFrom(mPlayerUnitIndex, hex, mAttackableUnits);
				mSimulation.GetUsableSkills(mPlayerUnitIndex, mUsableSkills);

				mPlayerPhase = .PostMove;
			}

		case .SelectingAttackTarget:
			for (let idx in mAttackableUnits)
			{
				let target = mSimulation.GetUnit(idx);
				if (target != null && target.mPosition == hex)
				{
					if (mHasTentativeMove)
					{
						ResetTentativeMove();
						SubmitPlayerAction(BattleAction.MakeMoveAndAttack(mPlayerUnitIndex, mTentativeMoveHex, idx));
					}
					else
					{
						SubmitPlayerAction(BattleAction.MakeAttack(mPlayerUnitIndex, idx));
					}
					break;
				}
			}

		case .SelectingSkillTarget:
			for (let idx in mSkillTargetUnits)
			{
				let target = mSimulation.GetUnit(idx);
				if (target != null && target.mPosition == hex)
				{
					if (mHasTentativeMove)
					{
						ResetTentativeMove();
						SubmitPlayerAction(BattleAction.MakeMoveAndSkill(mPlayerUnitIndex, mTentativeMoveHex, mSelectedSkillId, idx));
					}
					else
					{
						SubmitPlayerAction(BattleAction.MakeSkill(mPlayerUnitIndex, mSelectedSkillId, idx));
					}
					break;
				}
			}

		default:
		}
	}

	/// Submit the player's chosen action and return to idle.
	private void SubmitPlayerAction(BattleAction action)
	{
		for (let e in mStepEvents) delete e;
		mStepEvents.Clear();
		mSimulation.SubmitAction(action, mStepEvents);
		mSequencer.QueueEvents(mStepEvents);
		mPlayerPhase = .Idle;
		mPlayerUnitIndex = -1;
		mSelectedSkillId = -1;
		mHasTentativeMove = false;
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
		if ((mAutoPlay || mAutoStep) && !mSimulation.IsFinished)
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
		if ((mAutoPlay || mAutoStep) && mSimulation.IsFinished && !mSequencer.IsPlaying)
		{
			mAutoPlay = false;
			mAutoStep = false;
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
		if (mOverlayFeature == null) return;

		// Billboard axes — text and bars always face the camera
		let camForward = mCamera.Forward;
		let crossRight = Vector3.Cross(camForward, Vector3(0, 1, 0));
		let billboardRight = (crossRight.LengthSquared() > 0.001f) ? Vector3.Normalize(crossRight) : Vector3(1, 0, 0);

		// Draw unit overlays (health bars, soldier counts)
		for (int32 i = 0; i < mUnitViews.Count; i++)
		{
			let view = mUnitViews[i];
			if (view == null || !view.mVisible) continue;

			let unit = mSimulation.GetUnit(i);
			view.DrawOverlay(mOverlayFeature, unit, billboardRight);
		}

		// Draw grid overlays
		mGridRenderer.DrawOverlays();

		// Highlight current unit's hex and hovered hex
		mGridRenderer.ClearHighlights();

		// Deployment mode highlights
		if (mDeploymentMode)
		{
			let deployColumns = mSimulation.DeployColumns;
			let grid = mSimulation.Grid;

			// Highlight deployment zone (attacker side)
			for (int32 row = 0; row < grid.Rows; row++)
			{
				for (int32 col = 0; col < deployColumns; col++)
				{
					let hex = HexCoord.FromOffset(col, row);
					if (grid.InBounds(hex))
						mGridRenderer.SetHighlight(hex, .(50, 150, 255, 30)); // Soft blue
				}
			}

			// Highlight enemy (defender) positions with red
			for (int32 i = 0; i < mSimulation.UnitCount; i++)
			{
				let unit = mSimulation.GetUnit(i);
				if (unit != null && unit.mAlive && unit.mForce == .Defender)
					mGridRenderer.SetHighlight(unit.mPosition, .(255, 80, 80, 50)); // Soft red
			}

			// Highlight selected unit
			if (mDeploySelectedUnit >= 0)
			{
				let selUnit = mSimulation.GetUnit(mDeploySelectedUnit);
				if (selUnit != null)
					mGridRenderer.SetHighlight(selUnit.mPosition, .(255, 215, 80, 120)); // Gold
			}

			// Hovered hex highlight during deployment
			if (mHasHoveredHex)
				mGridRenderer.SetHighlight(mHoveredHex, .(100, 220, 255, 60));
		}

		if (!mDeploymentMode && !mSimulation.IsFinished)
		{
			let curIdx = mSimulation.CurrentUnitIndex;
			if (curIdx >= 0)
			{
				let unit = mSimulation.GetUnit(curIdx);
				if (unit != null && unit.mAlive)
					mGridRenderer.SetHighlight(unit.mPosition, .(255, 255, 100, 80));
			}
		}

		// Player turn phase highlights
		switch (mPlayerPhase)
		{
		case .SelectingMoveTarget:
			for (let hex in mReachableCells)
				mGridRenderer.SetHighlight(hex, .(50, 200, 100, 60)); // Green
		case .PostMove:
			// Highlight tentative position
			if (mHasTentativeMove)
				mGridRenderer.SetHighlight(mTentativeMoveHex, .(200, 200, 100, 80)); // Yellow
			// Show attackable targets from tentative position
			for (let idx in mAttackableUnits)
			{
				let target = mSimulation.GetUnit(idx);
				if (target != null)
					mGridRenderer.SetHighlight(target.mPosition, .(255, 80, 80, 60)); // Red
			}
		case .SelectingAttackTarget:
			for (let idx in mAttackableUnits)
			{
				let target = mSimulation.GetUnit(idx);
				if (target != null)
					mGridRenderer.SetHighlight(target.mPosition, .(255, 80, 80, 80)); // Red
			}
		case .SelectingSkillTarget:
			for (let idx in mSkillTargetUnits)
			{
				let target = mSimulation.GetUnit(idx);
				if (target != null)
					mGridRenderer.SetHighlight(target.mPosition, .(100, 150, 255, 80)); // Blue
			}
		default:
		}

		// Hovered hex highlight (cyan/white)
		if (mHasHoveredHex)
			mGridRenderer.SetHighlight(mHoveredHex, .(100, 220, 255, 60));

		// Draw floating damage/heal numbers
		DrawFloatingNumbers(billboardRight);

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
			// Show VFX on target too (if different from caster)
			if (ev.mTargetUnit >= 0 && ev.mTargetUnit != ev.mSourceUnit)
			{
				let targetView = GetUnitView(ev.mTargetUnit);
				if (targetView != null)
				{
					var targetVfx = BattleVFX();
					targetVfx.mType = .SkillCast;
					targetVfx.mPosition = targetView.mWorldPos;
					targetVfx.mDuration = 0.5f;
					targetVfx.mColor = .(100, 255, 150, 255); // Green-ish for receiving end
					mActiveEffects.Add(targetVfx);
				}
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

	private void DrawFloatingNumbers(Vector3 billboardRight)
	{
		let right = billboardRight;
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

			let scale = num.mIsCritical ? 1.2f : 0.8f;

			let text = scope String();
			if (num.mIsHeal)
				text.Append("+");
			num.mValue.ToString(text);
			if (num.mIsCritical)
				text.Append("!");

			mOverlayFeature.AddTextCentered(text, pos, color, scale, right, up, .Overlay);
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
				mOverlayFeature.AddCircle(vfx.mPosition, radius, .(0, 1, 0), color, 16, .DepthTest);

			case .BuffApply:
				let ringY = vfx.mPosition.Y + t * 0.8f;
				let ringAlpha = (uint8)(255 * (1.0f - t));
				let ringPos = Vector3(vfx.mPosition.X, ringY, vfx.mPosition.Z);
				let ringColor = Color(vfx.mColor.R, vfx.mColor.G, vfx.mColor.B, ringAlpha);
				mOverlayFeature.AddCircle(ringPos, 0.4f, .(0, 1, 0), ringColor, 16, .DepthTest);

			case .BuffRemove:
				let shrinkRadius = 0.4f * (1.0f - t);
				let shrinkAlpha = (uint8)(255 * (1.0f - t));
				let shrinkColor = Color(vfx.mColor.R, vfx.mColor.G, vfx.mColor.B, shrinkAlpha);
				mOverlayFeature.AddCircle(vfx.mPosition, shrinkRadius, .(0, 1, 0), shrinkColor, 12, .DepthTest);

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

		// 2. Unit views — destroy entities from scene, then delete views
		if (mUnitViews != null && mScene != null)
		{
			for (let view in mUnitViews)
			{
				if (view != null)
					mScene.DestroyEntity(view.mEntityId);
			}
		}
		DeleteContainerAndItems!(mUnitViews);
		mUnitViews = null;

		// 3. Grid renderer — destroy tile entities from scene
		mGridRenderer?.Shutdown();
		delete mGridRenderer;
		mGridRenderer = null;

		// 4. Destroy scene-level entities (sun, camera)
		if (mScene != null)
		{
			mScene.DestroyEntity(mSunEntity);
			mScene.DestroyEntity(mCameraEntity);
		}

		// 5. Camera — standalone
		delete mCamera;
		mCamera = null;

		// 6. Data lists
		for (let e in mStepEvents) delete e;
		delete mStepEvents;
		mStepEvents = null;

		delete mFloatingNumbers;
		mFloatingNumbers = null;

		for (let e in mActiveEffects)
			if (e.mText != null) delete e.mText;
		delete mActiveEffects;
		mActiveEffects = null;

		delete mReachableCells;
		mReachableCells = null;
		delete mAttackableUnits;
		mAttackableUnits = null;
		delete mUsableSkills;
		mUsableSkills = null;
		delete mSkillTargetUnits;
		mSkillTargetUnits = null;

		// 7. Materials — ReleaseRef before mesh resources
		mAttackerMaterial?.ReleaseRef();
		mAttackerMaterial = null;
		mDefenderMaterial?.ReleaseRef();
		mDefenderMaterial = null;

		// 8. Mesh resources — ReleaseRef
		mAttackerMesh?.ReleaseRef();
		mAttackerMesh = null;
		mDefenderMesh?.ReleaseRef();
		mDefenderMesh = null;

		mScene = null;
	}
}
