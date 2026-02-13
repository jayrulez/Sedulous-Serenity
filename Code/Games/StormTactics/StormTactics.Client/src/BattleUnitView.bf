namespace StormTactics.Client;

using System;
using Sedulous.Mathematics;
using Sedulous.Geometry.Resources;
using Sedulous.Materials;
using Sedulous.Render;
using Sedulous.Framework.Scenes;
using Sedulous.Framework.Render;
using Sedulous.Resources;
using StormTactics.Battle;
using StormTactics.Core;

enum UnitAnimState
{
	Idle,
	Moving,
	Attacking,
	TakingDamage,
	Dying,
	Dead
}

/// Visual representation of a single battle unit.
/// Uses placeholder geometry (cylinder) until real assets are available.
class BattleUnitView
{
	public int32 mUnitIndex;
	public Force mForce;
	public EntityId mEntityId;
	public bool mVisible = true;

	// World position
	public Vector3 mWorldPos;
	private Vector3 mTargetPos;
	private Vector3 mMoveStartPos;

	// Animation
	public UnitAnimState mAnimState = .Idle;
	private float mAnimTimer;
	private float mAnimDuration;

	// Visual flash
	private float mFlashTimer;
	private Color mFlashColor;
	private bool mFlashing;

	// Attack animation
	private Vector3 mAttackTargetPos;
	private Vector3 mAttackOriginPos;

	// Facing
	private Quaternion mFacingRotation = .Identity;

	// Constants
	private const float MOVE_SPEED = 4.0f; // hexes per second (tunable)
	private const float ATTACK_DURATION = 0.4f;
	private const float DAMAGE_FLASH_DURATION = 0.25f;
	private const float DEATH_DURATION = 0.6f;
	private const float UNIT_HEIGHT = 0.6f;
	private const float UNIT_RADIUS = 0.25f;

	public bool IsAnimating => mAnimState != .Idle && mAnimState != .Dead;

	/// Create the unit entity in the scene with placeholder mesh.
	public void Initialize(
		Scene scene,
		int32 unitIndex,
		Force force,
		HexCoord hex,
		float hexSize,
		StaticMeshResource meshResource,
		MaterialInstance material)
	{
		mUnitIndex = unitIndex;
		mForce = force;

		let (wx, wz) = hex.ToWorld(hexSize);
		mWorldPos = .(wx, UNIT_HEIGHT * 0.5f, wz);
		mTargetPos = mWorldPos;

		mEntityId = scene.CreateEntity();

		// Position + initial facing
		let initialAngle = (force == .Attacker) ? Math.PI_f * 0.5f : -Math.PI_f * 0.5f;
		mFacingRotation = Quaternion.CreateFromAxisAngle(.(0, 1, 0), initialAngle);

		var transform = scene.GetTransform(mEntityId);
		transform.Position = mWorldPos;
		transform.Rotation = mFacingRotation;
		scene.SetTransform(mEntityId, transform);

		// Mesh
		scene.SetComponent<MeshRendererComponent>(mEntityId, .Default);
		var comp = scene.GetComponent<MeshRendererComponent>(mEntityId);
		comp.Mesh = ResourceHandle<StaticMeshResource>(meshResource);

		if (material != null)
		{
			comp.MaterialInstances[0] = material;
			comp.MaterialInstances[0].AddRef();
			comp.MaterialCount = 1;
		}
	}

	/// Start moving the unit to a new hex position.
	public void StartMove(HexCoord targetHex, float hexSize)
	{
		let (wx, wz) = targetHex.ToWorld(hexSize);
		mTargetPos = .(wx, UNIT_HEIGHT * 0.5f, wz);
		mMoveStartPos = mWorldPos;

		UpdateFacing(mTargetPos);

		let dist = Vector3.Distance(mWorldPos, mTargetPos);
		mAnimDuration = dist / MOVE_SPEED;
		if (mAnimDuration < 0.1f) mAnimDuration = 0.1f;

		mAnimTimer = 0;
		mAnimState = .Moving;
	}

	/// Start attack animation (lunge toward target and back).
	public void StartAttack(Vector3 targetWorldPos)
	{
		mAttackOriginPos = mWorldPos;
		mAttackTargetPos = targetWorldPos;
		UpdateFacing(targetWorldPos);
		mAnimTimer = 0;
		mAnimDuration = ATTACK_DURATION;
		mAnimState = .Attacking;
	}

	/// Flash the unit to indicate damage taken.
	public void StartDamageFlash()
	{
		mFlashTimer = DAMAGE_FLASH_DURATION;
		mFlashColor = .(255, 50, 50, 255);
		mFlashing = true;
		mAnimState = .TakingDamage;
		mAnimTimer = 0;
		mAnimDuration = DAMAGE_FLASH_DURATION;
	}

	/// Flash the unit to indicate healing.
	public void StartHealFlash()
	{
		mFlashTimer = DAMAGE_FLASH_DURATION;
		mFlashColor = .(50, 255, 50, 255);
		mFlashing = true;
	}

	/// Start death animation (sink into ground).
	public void StartDeath()
	{
		mAnimTimer = 0;
		mAnimDuration = DEATH_DURATION;
		mAnimState = .Dying;
	}

	/// Update animation state. Returns true when an animation just completed.
	public bool Update(Scene scene, float dt)
	{
		bool animCompleted = false;

		// Update flash
		if (mFlashing)
		{
			mFlashTimer -= dt;
			if (mFlashTimer <= 0)
				mFlashing = false;
		}

		switch (mAnimState)
		{
		case .Moving:
			mAnimTimer += dt;
			let t = Math.Min(mAnimTimer / mAnimDuration, 1.0f);
			// Smooth ease in-out
			let smooth = t * t * (3.0f - 2.0f * t);
			mWorldPos = Vector3.Lerp(mMoveStartPos, mTargetPos, smooth);

			if (t >= 1.0f)
			{
				mWorldPos = mTargetPos;
				mAnimState = .Idle;
				animCompleted = true;
			}

		case .Attacking:
			mAnimTimer += dt;
			let t = Math.Min(mAnimTimer / mAnimDuration, 1.0f);

			// Lunge forward then back (triangle wave: 0→1→0)
			let lunge = t < 0.5f ? t * 2.0f : (1.0f - t) * 2.0f;
			let lungeDir = Vector3.Normalize(mAttackTargetPos - mAttackOriginPos);
			let lungeAmount = lunge * 0.5f; // Move halfway toward target
			mWorldPos = mAttackOriginPos + lungeDir * lungeAmount;

			if (t >= 1.0f)
			{
				mWorldPos = mAttackOriginPos;
				mAnimState = .Idle;
				animCompleted = true;
			}

		case .TakingDamage:
			mAnimTimer += dt;
			if (mAnimTimer >= mAnimDuration)
			{
				mAnimState = .Idle;
				animCompleted = true;
			}

		case .Dying:
			mAnimTimer += dt;
			let t = Math.Min(mAnimTimer / mAnimDuration, 1.0f);
			// Sink into ground
			mWorldPos.Y = UNIT_HEIGHT * 0.5f * (1.0f - t);

			if (t >= 1.0f)
			{
				mAnimState = .Dead;
				mVisible = false;
				animCompleted = true;
			}

		case .Idle, .Dead:
			// Nothing to do
		}

		// Apply position + rotation to entity
		var transform = scene.GetTransform(mEntityId);
		transform.Position = mWorldPos;
		transform.Rotation = mFacingRotation;

		// Scale down during death
		if (mAnimState == .Dying)
		{
			let t = Math.Min(mAnimTimer / mAnimDuration, 1.0f);
			let scale = 1.0f - t * 0.5f;
			transform.Scale = .(scale, scale, scale);
		}

		scene.SetTransform(mEntityId, transform);

		return animCompleted;
	}

	/// Draw debug overlays for this unit (health bar, etc.).
	public void DrawOverlay(DebugRenderFeature debugFeature, BattleUnit unit, Vector3 billboardRight)
	{
		if (!mVisible || debugFeature == null || unit == null || !unit.mAlive) return;

		// Health bar above unit (in 3D space)
		let barPos = mWorldPos + Vector3(0, UNIT_HEIGHT * 0.7f, 0);
		let right = billboardRight;
		let up = Vector3(0, 1, 0);

		// HP ratio
		let hpRatio = (float)unit.mCurrentHP / (float)unit.mMaxHP;
		let barWidth = 0.6f;
		let barHeight = 0.08f;
		let barLines = 5; // Number of lines to fill the bar height

		// Background bar (dark) — filled
		let bgLeft = barPos - right * (barWidth * 0.5f);
		let bgRight = barPos + right * (barWidth * 0.5f);
		for (int j = 0; j < barLines; j++)
		{
			let yOff = up * (barHeight * (float)j / (float)(barLines - 1));
			debugFeature.AddLine(bgLeft + yOff, bgRight + yOff, .(40, 40, 40, 200));
		}

		// HP bar (green to red based on HP) — filled
		let hpColor = Color(
			(uint8)(255 * (1.0f - hpRatio)),
			(uint8)(255 * hpRatio),
			0, 255);
		let hpRight = bgLeft + right * (barWidth * hpRatio);
		for (int j = 0; j < barLines; j++)
		{
			let yOff = up * (barHeight * (float)j / (float)(barLines - 1));
			debugFeature.AddLine(bgLeft + yOff, hpRight + yOff, hpColor);
		}

		// Flash effect
		if (mFlashing)
		{
			debugFeature.AddSphere(mWorldPos, UNIT_RADIUS * 1.5f, mFlashColor, 8);
		}

		// Soldier count text
		let countText = scope String();
		unit.SoldierCount.ToString(countText);
		let textPos = mWorldPos + Vector3(0, UNIT_HEIGHT + 0.15f, 0);
		debugFeature.AddTextCentered(countText, textPos, .(255, 255, 255, 255), 0.6f, right, up);

		// Buff/debuff icons
		let buffCount = Math.Min((int32)unit.mBuffs.Count, 5);
		if (buffCount > 0)
		{
			let buffY = mWorldPos.Y + UNIT_HEIGHT * 0.45f;
			let buffSpacing = 0.12f;
			let buffStartX = mWorldPos.X - (float)(buffCount - 1) * buffSpacing * 0.5f;

			for (int32 b = 0; b < buffCount; b++)
			{
				let buff = unit.mBuffs[b];
				let buffColor = GetBuffColor(buff.mConfig.mTag);
				let buffPos = Vector3(buffStartX + (float)b * buffSpacing, buffY, mWorldPos.Z);
				debugFeature.AddCircle(buffPos, 0.05f, .(0, 1, 0), buffColor, 8, .Overlay);
			}
		}
	}

	// --- Helpers ---

	private void UpdateFacing(Vector3 targetWorldPos)
	{
		let dir = targetWorldPos - mWorldPos;
		let lenSq = dir.X * dir.X + dir.Z * dir.Z;
		if (lenSq > 0.001f)
		{
			let angle = Math.Atan2(dir.X, dir.Z);
			mFacingRotation = Quaternion.CreateFromAxisAngle(.(0, 1, 0), angle);
		}
	}

	private static Color GetBuffColor(BuffTag tag)
	{
		switch (tag)
		{
		case .Stun:        return .(255, 255, 0, 255);
		case .Slow:        return .(0, 200, 255, 255);
		case .Poison:      return .(160, 0, 200, 255);
		case .Burn:        return .(255, 140, 0, 255);
		case .Freeze:      return .(100, 180, 255, 255);
		case .Silence:     return .(150, 150, 150, 255);
		case .Charm:       return .(255, 100, 200, 255);
		case .Shield:      return .(220, 220, 255, 255);
		case .Regen:       return .(50, 255, 50, 255);
		case .AttackUp:    return .(255, 80, 80, 255);
		case .AttackDown:  return .(180, 50, 50, 255);
		case .DefenseUp:   return .(80, 80, 255, 255);
		case .DefenseDown: return .(50, 50, 180, 255);
		case .SpeedUp:     return .(200, 255, 50, 255);
		case .SpeedDown:   return .(120, 100, 50, 255);
		case .Immune:      return .(255, 215, 0, 255);
		default:           return .(200, 200, 200, 255);
		}
	}
}
