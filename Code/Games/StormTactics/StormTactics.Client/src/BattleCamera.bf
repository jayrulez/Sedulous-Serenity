namespace StormTactics.Client;

using System;
using Sedulous.Mathematics;
using Sedulous.Shell.Input;

/// Camera controller for the battle view.
/// Provides an isometric/orbital view of the hex grid with pan, zoom, and smooth transitions.
class BattleCamera
{
	// Current camera state
	private Vector3 mTarget;
	private float mDistance;
	private float mYaw;
	private float mPitch;

	// Smooth transition
	private Vector3 mSmoothTarget;
	private float mSmoothDistance;
	private bool mIsTransitioning;
	private float mTransitionSpeed = 5.0f;

	// Limits
	private float mMinDistance = 5.0f;
	private float mMaxDistance = 40.0f;
	private float mMinPitch = 0.3f;  // ~17 degrees (not too flat)
	private float mMaxPitch = 1.4f;  // ~80 degrees (nearly top-down)

	// Control speeds
	private float mPanSpeed = 10.0f;
	private float mZoomSpeed = 5.0f;
	private float mRotateSpeed = 2.0f;

	// Settings
	private bool mInvertPan;

	// Computed camera vectors
	private Vector3 mPosition;
	private Vector3 mForward;

	public Vector3 Position => mPosition;
	public Vector3 Forward => mForward;
	public Vector3 Target => mTarget;
	public float Distance => mDistance;
	public bool InvertPan { get => mInvertPan; set mut => mInvertPan = value; }

	public this()
	{
		// Default isometric-like view
		mYaw = -0.3f;
		mPitch = 0.8f; // ~45 degrees from horizon
		mDistance = 15.0f;
		mTarget = .(0, 0, 0);
		mSmoothTarget = mTarget;
		mSmoothDistance = mDistance;
		Update(0);
	}

	/// Set up the camera to view a grid centered at the given world position.
	public void SetGridCenter(float centerX, float centerZ, float gridExtent)
	{
		mTarget = .(centerX, 0, centerZ);
		mSmoothTarget = mTarget;
		mDistance = Math.Clamp(gridExtent * 1.5f, mMinDistance, mMaxDistance);
		mSmoothDistance = mDistance;
		Update(0);
	}

	/// Smoothly focus on a hex coordinate.
	public void FocusOnWorldPos(float x, float z)
	{
		mSmoothTarget = .(x, 0, z);
		mIsTransitioning = true;
	}

	/// Smoothly zoom to a target distance.
	public void ZoomTo(float distance)
	{
		mSmoothDistance = Math.Clamp(distance, mMinDistance, mMaxDistance);
		mIsTransitioning = true;
	}

	/// Handle input for camera control.
	public void HandleInput(IKeyboard keyboard, IMouse mouse, float dt)
	{
		// Pan with WASD
		float panX = 0, panZ = 0;
		float sign = mInvertPan ? -1.0f : 1.0f;
		if (keyboard.IsKeyDown(.W)) panZ += sign;
		if (keyboard.IsKeyDown(.S)) panZ -= sign;
		if (keyboard.IsKeyDown(.A)) panX += sign;
		if (keyboard.IsKeyDown(.D)) panX -= sign;

		if (panX != 0 || panZ != 0)
		{
			// Pan relative to camera orientation (only yaw)
			let sinYaw = Math.Sin(mYaw);
			let cosYaw = Math.Cos(mYaw);
			let worldX = panX * cosYaw - panZ * sinYaw;
			let worldZ = panX * sinYaw + panZ * cosYaw;

			let speed = mPanSpeed * (mDistance / 15.0f); // Scale pan speed with zoom
			mTarget.X += worldX * speed * dt;
			mTarget.Z += worldZ * speed * dt;
			mSmoothTarget = mTarget;
			mIsTransitioning = false;
		}

		// Zoom with Q/E or mouse wheel
		float zoom = 0;
		if (keyboard.IsKeyDown(.Q)) zoom -= 1;
		if (keyboard.IsKeyDown(.E)) zoom += 1;
		zoom -= mouse.ScrollY * 3.0f;

		if (zoom != 0)
		{
			mDistance = Math.Clamp(mDistance + zoom * mZoomSpeed * dt, mMinDistance, mMaxDistance);
			mSmoothDistance = mDistance;
		}

		// Rotate with middle mouse drag
		if (mouse.IsButtonDown(.Middle))
		{
			mYaw -= mouse.DeltaX * mRotateSpeed * dt;
			mPitch = Math.Clamp(mPitch + mouse.DeltaY * mRotateSpeed * dt, mMinPitch, mMaxPitch);
		}
	}

	/// Update camera position from current state.
	public void Update(float dt)
	{
		// Smooth interpolation for transitions
		if (mIsTransitioning && dt > 0)
		{
			let alpha = 1.0f - Math.Exp(-mTransitionSpeed * dt);
			mTarget = Vector3.Lerp(mTarget, mSmoothTarget, alpha);
			mDistance = mDistance + (mSmoothDistance - mDistance) * alpha;

			if (Vector3.Distance(mTarget, mSmoothTarget) < 0.01f &&
				Math.Abs(mDistance - mSmoothDistance) < 0.01f)
			{
				mTarget = mSmoothTarget;
				mDistance = mSmoothDistance;
				mIsTransitioning = false;
			}
		}

		// Compute camera position from spherical coordinates
		let cosPitch = Math.Cos(mPitch);
		let sinPitch = Math.Sin(mPitch);
		let cosYaw = Math.Cos(mYaw);
		let sinYaw = Math.Sin(mYaw);

		mPosition = mTarget + Vector3(
			sinYaw * cosPitch * mDistance,
			sinPitch * mDistance,
			cosYaw * cosPitch * mDistance
		);

		mForward = Vector3.Normalize(mTarget - mPosition);
	}
}
