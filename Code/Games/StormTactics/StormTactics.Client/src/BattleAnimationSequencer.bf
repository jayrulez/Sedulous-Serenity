namespace StormTactics.Client;

using System;
using System.Collections;
using Sedulous.Mathematics;
using StormTactics.Battle;
using StormTactics.Core;
using Sedulous.Framework.Scenes;

enum SequencerState
{
	Idle,         // No events to play
	Processing,   // Playing an event animation
	WaitingForAnim // Waiting for unit animation to finish
}

/// Consumes BattleEvent queues and drives visual animations on BattleUnitViews.
/// Events are played sequentially with appropriate timing.
class BattleAnimationSequencer
{
	private List<BattleEvent> mEventQueue = new .() ~ DeleteContainerAndItems!(_);
	private SequencerState mState = .Idle;
	private float mWaitTimer;
	private float mSpeedMultiplier = 1.0f;
	private bool mSkipAll;

	// References
	private List<BattleUnitView> mUnitViews;
	private Scene mScene;
	private float mHexSize;

	// Current event being processed
	private int32 mCurrentEventIndex;

	// Callback for when all events are done
	public bool IsPlaying => mState != .Idle || mEventQueue.Count > 0;

	public float SpeedMultiplier { get => mSpeedMultiplier; set => mSpeedMultiplier = Math.Max(0.5f, value); }

	public this(List<BattleUnitView> unitViews, Scene scene, float hexSize)
	{
		mUnitViews = unitViews;
		mScene = scene;
		mHexSize = hexSize;
	}

	/// Queue new events for playback. Takes ownership of the event objects.
	public void QueueEvents(List<BattleEvent> events)
	{
		for (let e in events)
		{
			let copy = new BattleEvent();
			copy.mType = e.mType;
			copy.mSourceUnit = e.mSourceUnit;
			copy.mTargetUnit = e.mTargetUnit;
			copy.mValue = e.mValue;
			copy.mSkillId = e.mSkillId;
			copy.mBuffId = e.mBuffId;
			copy.mFromHex = e.mFromHex;
			copy.mToHex = e.mToHex;
			copy.mWinner = e.mWinner;
			copy.mDamageType = e.mDamageType;
			copy.mIsCritical = e.mIsCritical;
			mEventQueue.Add(copy);
		}
	}

	/// Skip all remaining events instantly.
	public void SkipAll()
	{
		mSkipAll = true;
	}

	/// Update the sequencer. Returns true if an event was just completed.
	public bool Update(float dt)
	{
		let effectiveDt = dt * mSpeedMultiplier;
		bool eventCompleted = false;

		// Skip mode: process all events instantly
		if (mSkipAll)
		{
			while (mEventQueue.Count > 0)
			{
				let ev = mEventQueue[0];
				ApplyEventInstantly(ev);
				delete ev;
				mEventQueue.RemoveAt(0);
				eventCompleted = true;
			}
			mSkipAll = false;
			mState = .Idle;
			return eventCompleted;
		}

		switch (mState)
		{
		case .Idle:
			if (mEventQueue.Count > 0)
			{
				let ev = mEventQueue[0];
				StartEvent(ev);
			}

		case .Processing:
			mWaitTimer -= effectiveDt;
			if (mWaitTimer <= 0)
			{
				FinishCurrentEvent();
				eventCompleted = true;
			}

		case .WaitingForAnim:
			// Check if any unit is still animating
			bool anyAnimating = false;
			for (let view in mUnitViews)
			{
				if (view != null && view.IsAnimating)
				{
					anyAnimating = true;
					break;
				}
			}

			if (!anyAnimating)
			{
				FinishCurrentEvent();
				eventCompleted = true;
			}
		}

		return eventCompleted;
	}

	/// Start playing the visual for an event.
	private void StartEvent(BattleEvent ev)
	{
		switch (ev.mType)
		{
		case .BattleStarted:
			// Brief pause
			mState = .Processing;
			mWaitTimer = 0.5f;

		case .TurnStarted:
			// Brief pause, could highlight current unit
			mState = .Processing;
			mWaitTimer = 0.2f;

		case .UnitMoved:
			let view = GetView(ev.mSourceUnit);
			if (view != null)
			{
				view.StartMove(ev.mToHex, mHexSize);
				mState = .WaitingForAnim;
			}
			else
			{
				mState = .Processing;
				mWaitTimer = 0;
			}

		case .UnitAttacked:
			let attackerView = GetView(ev.mSourceUnit);
			let targetView = GetView(ev.mTargetUnit);
			if (attackerView != null && targetView != null)
			{
				attackerView.StartAttack(targetView.mWorldPos);
				mState = .WaitingForAnim;
			}
			else
			{
				mState = .Processing;
				mWaitTimer = 0;
			}

		case .DamageDealt:
			let dmgView = GetView(ev.mTargetUnit);
			if (dmgView != null)
			{
				dmgView.StartDamageFlash();
				mState = .WaitingForAnim;
			}
			else
			{
				mState = .Processing;
				mWaitTimer = 0;
			}

		case .HealApplied:
			let healView = GetView(ev.mTargetUnit);
			if (healView != null)
				healView.StartHealFlash();
			mState = .Processing;
			mWaitTimer = 0.2f;

		case .UnitDied:
			// The dying unit is the source (EmitEvent(.UnitDied, targetIdx) sets mSourceUnit)
			let deadView = GetView(ev.mSourceUnit);
			if (deadView != null)
			{
				deadView.StartDeath();
				mState = .WaitingForAnim;
			}
			else
			{
				mState = .Processing;
				mWaitTimer = 0;
			}

		case .BuffApplied, .BuffRemoved, .BuffTicked:
			// Brief visual indicator (skip for now)
			mState = .Processing;
			mWaitTimer = 0.1f;

		case .SkillUsed:
			// Brief flash on caster
			mState = .Processing;
			mWaitTimer = 0.3f;

		case .CounterAttack:
			let counterView = GetView(ev.mSourceUnit);
			let counterTarget = GetView(ev.mTargetUnit);
			if (counterView != null && counterTarget != null)
			{
				counterView.StartAttack(counterTarget.mWorldPos);
				mState = .WaitingForAnim;
			}
			else
			{
				mState = .Processing;
				mWaitTimer = 0;
			}

		case .UnitSummoned:
			mState = .Processing;
			mWaitTimer = 0.3f;

		case .BattleEnded:
			mState = .Processing;
			mWaitTimer = 1.0f;
		}
	}

	/// Apply an event instantly (skip mode).
	private void ApplyEventInstantly(BattleEvent ev)
	{
		switch (ev.mType)
		{
		case .UnitMoved:
			let view = GetView(ev.mSourceUnit);
			if (view != null)
			{
				let (wx, wz) = ev.mToHex.ToWorld(mHexSize);
				view.mWorldPos = .(wx, 0.3f, wz);
				view.mAnimState = .Idle;

				var transform = mScene.GetTransform(view.mEntityId);
				transform.Position = view.mWorldPos;
				mScene.SetTransform(view.mEntityId, transform);
			}

		case .UnitDied:
			// The dying unit is the source (EmitEvent(.UnitDied, targetIdx) sets mSourceUnit)
			let deadView2 = GetView(ev.mSourceUnit);
			if (deadView2 != null)
			{
				deadView2.mAnimState = .Dead;
				deadView2.mVisible = false;
				// Hide entity by moving far away
				var transform = mScene.GetTransform(deadView2.mEntityId);
				transform.Position = .(0, -100, 0);
				mScene.SetTransform(deadView2.mEntityId, transform);
			}

		default:
			// Most events don't need instant visual changes
		}
	}

	/// Finish processing the current event and move to the next.
	private void FinishCurrentEvent()
	{
		if (mEventQueue.Count > 0)
		{
			let ev = mEventQueue[0];
			delete ev;
			mEventQueue.RemoveAt(0);
		}

		mState = .Idle;
	}

	/// Get the unit view for a given unit index, or null.
	private BattleUnitView GetView(int32 unitIdx)
	{
		if (unitIdx < 0 || unitIdx >= mUnitViews.Count) return null;
		return mUnitViews[unitIdx];
	}
}
