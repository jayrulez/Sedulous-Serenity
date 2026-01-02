using System;
using Sedulous.Mathematics;

namespace Sedulous.Framework.Core;

/// Represents a 3D transformation with position, rotation, and scale.
/// Supports parent-child hierarchy for transform propagation.
struct Transform
{
	/// Local position relative to parent (or world if no parent).
	public Vector3 Position = .Zero;

	/// Local rotation relative to parent.
	public Quaternion Rotation = .Identity;

	/// Local scale.
	public Vector3 Scale = .(1, 1, 1);

	/// Cached local matrix (needs recalculation when TRS changes).
	private Matrix4x4 mLocalMatrix = .Identity;

	/// Cached world matrix (needs recalculation when local or parent changes).
	private Matrix4x4 mWorldMatrix = .Identity;

	/// Dirty flags for lazy matrix computation.
	private bool mLocalDirty = true;
	private bool mWorldDirty = true;

	/// Creates an identity transform.
	public static Transform Identity => .();

	/// Gets the local transformation matrix (Scale * Rotation * Translation).
	public Matrix4x4 LocalMatrix
	{
		get mut
		{
			if (mLocalDirty)
			{
				let s = Matrix4x4.CreateScale(Scale);
				let r = Matrix4x4.CreateFromQuaternion(Rotation);
				let t = Matrix4x4.CreateTranslation(Position);
				mLocalMatrix = s * r * t;
				mLocalDirty = false;
			}
			return mLocalMatrix;
		}
	}

	/// Gets the cached world matrix.
	public Matrix4x4 WorldMatrix => mWorldMatrix;

	/// Gets the world position from the world matrix.
	public Vector3 WorldPosition => mWorldMatrix.Translation;

	/// Forward direction in local space.
	public Vector3 Forward => Vector3(0, 0, -1).Transform(Matrix4x4.CreateFromQuaternion(Rotation));

	/// Right direction in local space.
	public Vector3 Right => Vector3(1, 0, 0).Transform(Matrix4x4.CreateFromQuaternion(Rotation));

	/// Up direction in local space.
	public Vector3 Up => Vector3(0, 1, 0).Transform(Matrix4x4.CreateFromQuaternion(Rotation));

	/// Marks the local matrix as needing recalculation.
	public void SetLocalDirty() mut
	{
		mLocalDirty = true;
		mWorldDirty = true;
	}

	/// Computes the world matrix given a parent's world matrix.
	public void UpdateWorldMatrix(Matrix4x4 parentWorld) mut
	{
		if (mLocalDirty || mWorldDirty)
		{
			mWorldMatrix = LocalMatrix * parentWorld;
			mWorldDirty = false;
		}
	}

	/// Sets position and marks dirty.
	public void SetPosition(Vector3 position) mut
	{
		Position = position;
		SetLocalDirty();
	}

	/// Sets rotation and marks dirty.
	public void SetRotation(Quaternion rotation) mut
	{
		Rotation = rotation;
		SetLocalDirty();
	}

	/// Sets scale and marks dirty.
	public void SetScale(Vector3 scale) mut
	{
		Scale = scale;
		SetLocalDirty();
	}

	/// Translates by an offset.
	public void Translate(Vector3 offset) mut
	{
		Position = Position + offset;
		SetLocalDirty();
	}

	/// Rotates by a quaternion.
	public void Rotate(Quaternion rotation) mut
	{
		Rotation = rotation * Rotation;
		SetLocalDirty();
	}

	/// Looks at a target position.
	/// Note: Uses approximation via yaw/pitch from forward direction.
	public void LookAt(Vector3 target, Vector3 up = .(0, 1, 0)) mut
	{
		let direction = Vector3.Normalize(target - Position);
		// Compute yaw and pitch from direction
		let yaw = Math.Atan2(direction.X, direction.Z);
		let pitch = Math.Asin(-direction.Y);
		Rotation = Quaternion.CreateFromYawPitchRoll(yaw, pitch, 0);
		SetLocalDirty();
	}
}
