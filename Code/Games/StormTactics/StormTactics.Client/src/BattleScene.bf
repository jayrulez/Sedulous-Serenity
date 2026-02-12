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
	private HexGridRenderer mGridRenderer ~ delete _;
	private BattleCamera mCamera ~ delete _;
	private BattleAnimationSequencer mSequencer ~ delete _;

	// Unit views
	private List<BattleUnitView> mUnitViews = new .() ~ DeleteContainerAndItems!(_);

	// Shared mesh resources for placeholders
	private StaticMeshResource mAttackerMesh ~ _?.ReleaseRef();
	private StaticMeshResource mDefenderMesh ~ _?.ReleaseRef();

	// Materials
	private MaterialInstance mAttackerMaterial ~ _?.ReleaseRef();
	private MaterialInstance mDefenderMaterial ~ _?.ReleaseRef();

	// Scene entities
	private EntityId mSunEntity;
	private EntityId mCameraEntity;

	// Battle state
	private float mHexSize;
	private bool mAutoPlay;
	private float mAutoStepTimer;
	private float mAutoStepDelay = 0.1f; // Seconds between auto-steps
	private bool mBattleStarted;
	private List<BattleEvent> mStepEvents = new .() ~ { for (let e in _) delete e; delete _; };

	// HUD
	private String mStatusText = new .() ~ delete _;

	public BattleCamera Camera => mCamera;
	public bool IsAutoPlaying => mAutoPlay;

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

		mBattleStarted = true;
		mStatusText.Set("Battle ready. Space=Step, A=Auto, S=Skip");
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

		// Update status
		UpdateStatusText();
	}

	/// Toggle auto-play mode.
	public void ToggleAutoPlay()
	{
		mAutoPlay = !mAutoPlay;
		mAutoStepTimer = 0;
		UpdateStatusText();
	}

	/// Skip all remaining animations.
	public void SkipAnimations()
	{
		mSequencer.SkipAll();
	}

	/// Set animation speed multiplier.
	public void SetSpeed(float mult)
	{
		mSequencer.SpeedMultiplier = mult;
	}

	/// Handle input.
	public void HandleInput(Sedulous.Shell.Input.IKeyboard keyboard, Sedulous.Shell.Input.IMouse mouse, float dt)
	{
		mCamera.HandleInput(keyboard, mouse, dt);

		// Space = step once
		if (keyboard.IsKeyPressed(.Space) && !mAutoPlay)
			StepBattle();

		// A = toggle auto-play
		if (keyboard.IsKeyPressed(.F))
			ToggleAutoPlay();

		// S = skip animations
		if (keyboard.IsKeyPressed(.G))
			SkipAnimations();

		// 1/2/3 = speed control
		if (keyboard.IsKeyPressed(.Num1)) SetSpeed(1.0f);
		if (keyboard.IsKeyPressed(.Num2)) SetSpeed(2.0f);
		if (keyboard.IsKeyPressed(.Num3)) SetSpeed(4.0f);
	}

	/// Update animations and auto-play.
	public void Update(float dt)
	{
		if (!mBattleStarted) return;

		// Update camera
		mCamera.Update(dt);

		// Update unit animations
		for (let view in mUnitViews)
		{
			if (view != null)
				view.Update(mScene, dt);
		}

		// Update sequencer
		mSequencer.Update(dt);

		// Auto-play: step when animations are done
		if (mAutoPlay && !mSimulation.IsFinished)
		{
			if (!mSequencer.IsPlaying)
			{
				mAutoStepTimer += dt;
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
			UpdateStatusText();
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

	/// Draw debug overlay (HUD, health bars).
	public void DrawOverlay(uint32 viewWidth, uint32 viewHeight)
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

		// Highlight current unit's hex
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

		// Draw HUD
		DrawHUD(viewWidth, viewHeight);
	}

	/// Draw the battle HUD.
	private void DrawHUD(uint32 viewWidth, uint32 viewHeight)
	{
		let bgColor = Color(0, 0, 0, 180);
		let white = Color(255, 255, 255, 255);
		let yellow = Color(255, 255, 100, 255);
		let cyan = Color(100, 255, 255, 255);
		let green = Color(100, 255, 100, 255);
		let red = Color(255, 100, 100, 255);

		// Top-left: controls
		mDebugFeature.AddRect2D(5, 5, 350, 90, bgColor);
		mDebugFeature.AddText2D("STORM TACTICS - BATTLE", 15, 12, yellow, 1.3f);
		mDebugFeature.AddText2D("Space:Step  F:Auto  G:Skip  1/2/3:Speed", 15, 32, white, 0.9f);
		mDebugFeature.AddText2D("WASD:Pan  QE:Zoom  MMB:Rotate  Esc:Quit", 15, 48, white, 0.9f);
		mDebugFeature.AddText2D(mStatusText, 15, 68, cyan, 1.0f);

		// Top-right: battle stats
		float panelX = (float)viewWidth - 200;
		mDebugFeature.AddRect2D(panelX, 5, 195, 90, bgColor);

		let turnText = scope String();
		turnText.AppendF("Turn: {}", mSimulation.TurnCount);
		mDebugFeature.AddText2D(turnText, panelX + 10, 12, white, 1.0f);

		// Count alive units per side
		int32 attackersAlive = 0, defendersAlive = 0;
		for (int32 i = 0; i < mSimulation.UnitCount; i++)
		{
			let unit = mSimulation.GetUnit(i);
			if (unit != null && unit.mAlive)
			{
				if (unit.mForce == .Attacker) attackersAlive++;
				else defendersAlive++;
			}
		}

		let attackerText = scope String();
		attackerText.AppendF("Attackers: {}", attackersAlive);
		mDebugFeature.AddText2D(attackerText, panelX + 10, 32, red, 1.0f);

		let defenderText = scope String();
		defenderText.AppendF("Defenders: {}", defendersAlive);
		mDebugFeature.AddText2D(defenderText, panelX + 10, 52, .(100, 150, 255, 255), 1.0f);

		// Battle state
		if (mSimulation.IsFinished)
		{
			let resultText = scope String();
			switch (mSimulation.State)
			{
			case .AttackerWins: resultText.Set("ATTACKERS WIN!");
			case .DefenderWins: resultText.Set("DEFENDERS WIN!");
			case .Draw: resultText.Set("DRAW!");
			default: resultText.Set("Battle Over");
			}
			mDebugFeature.AddText2D(resultText, panelX + 10, 72, green, 1.2f);
		}
		else if (mAutoPlay)
		{
			mDebugFeature.AddText2D("AUTO-PLAYING...", panelX + 10, 72, yellow, 1.0f);
		}
	}

	/// Update the status text.
	private void UpdateStatusText()
	{
		mStatusText.Clear();
		if (mSimulation.IsFinished)
		{
			switch (mSimulation.State)
			{
			case .AttackerWins: mStatusText.Set("Battle complete: Attackers win!");
			case .DefenderWins: mStatusText.Set("Battle complete: Defenders win!");
			case .Draw: mStatusText.Set("Battle complete: Draw!");
			default: mStatusText.Set("Battle complete");
			}
		}
		else if (mAutoPlay)
		{
			mStatusText.AppendF("Auto-playing (x{})", mSequencer.SpeedMultiplier);
		}
		else
		{
			mStatusText.AppendF("Turn {} — Space to step", mSimulation.TurnCount);
		}
	}

	/// Clean up resources.
	public void Shutdown()
	{
		mGridRenderer?.Shutdown();
	}
}
