using System;
using Sedulous.Mathematics;

namespace Sedulous.Engine.Core;

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
	private Matrix mLocalMatrix = .Identity;

	/// Cached world matrix (needs recalculation when local or parent changes).
	private Matrix mWorldMatrix = .Identity;

	/// Dirty flags for lazy matrix computation.
	private bool mLocalDirty = true;
	private bool mWorldDirty = true;

	/// True if this transform has a parent (set during UpdateWorldMatrix).
	private bool mHasParent = false;

	/// Creates an identity transform.
	public static Transform Identity => .();

	/// Gets the local transformation matrix (Scale * Rotation * Translation).
	public Matrix LocalMatrix
	{
		get mut
		{
			if (mLocalDirty)
			{
				let s = Matrix.CreateScale(Scale);
				let r = Matrix.CreateFromQuaternion(Rotation);
				let t = Matrix.CreateTranslation(Position);
				mLocalMatrix = s * r * t;
				mLocalDirty = false;
			}
			return mLocalMatrix;
		}
	}

	/// Gets the cached world matrix.
	public Matrix WorldMatrix => mWorldMatrix;

	/// Gets the world position.
	/// For root entities (no parent), returns Position directly when dirty (before sync).
	/// For child entities, returns cached world matrix translation (may be stale before sync).
	public Vector3 WorldPosition
	{
		get
		{
			// If world matrix hasn't been synced yet and this is a root entity,
			// return local position directly (which IS the world position for roots).
			// For child entities, we must return cached value since we need parent's matrix.
			if (mWorldDirty && !mHasParent)
				return Position;
			return mWorldMatrix.Translation;
		}
	}

	/// Forward direction in local space.
	public Vector3 Forward => Vector3.Transform(.(0, 0, -1), Matrix.CreateFromQuaternion(Rotation));

	/// Right direction in local space.
	public Vector3 Right => Vector3.Transform(.(1, 0, 0), Matrix.CreateFromQuaternion(Rotation));

	/// Up direction in local space.
	public Vector3 Up => Vector3.Transform(.(0, 1, 0), Matrix.CreateFromQuaternion(Rotation));

	/// Marks the local matrix as needing recalculation.
	public void SetLocalDirty() mut
	{
		mLocalDirty = true;
		mWorldDirty = true;
	}

	/// Computes the world matrix for a root entity (no parent).
	/// For root entities, world matrix equals local matrix.
	public void UpdateWorldMatrix() mut
	{
		if (mLocalDirty || mWorldDirty)
		{
			mWorldMatrix = LocalMatrix;
			mWorldDirty = false;
			mHasParent = false;
		}
	}

	/// Computes the world matrix given a parent's world matrix.
	/// Use this for child entities in a hierarchy.
	public void UpdateWorldMatrix(Matrix parentWorld) mut
	{
		if (mLocalDirty || mWorldDirty)
		{
			mWorldMatrix = LocalMatrix * parentWorld;
			mWorldDirty = false;
			mHasParent = true;
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
	/// Note: Uses yaw/pitch from forward direction with -Z forward convention.
	public void LookAt(Vector3 target, Vector3 up = .(0, 1, 0)) mut
	{
		let direction = Vector3.Normalize(target - Position);
		// Compute yaw and pitch from direction
		// Negate X and Z because Forward uses -Z as base direction
		let yaw = Math.Atan2(-direction.X, -direction.Z);
		let pitch = Math.Asin(direction.Y);  // Negative Y = looking down = negative pitch
		Rotation = Quaternion.CreateFromYawPitchRoll(yaw, pitch, 0);
		SetLocalDirty();
	}
}
