namespace Sedulous.Tools.Core;

using System;
using Sedulous.Core.Mathematics;

/// Simple orbit camera with fly mode support.
class OrbitCamera
{
	public Vector3 Target = .Zero;
	public float Distance = 5.0f;
	public float Yaw = 0.0f;
	public float Pitch = 0.3f;
	public float MinDistance = 0.5f;
	public float MaxDistance = 100.0f;
	public float MinPitch = -Math.PI_f / 2.0f + 0.1f;
	public float MaxPitch = Math.PI_f / 2.0f - 0.1f;

	public Vector3 Position
	{
		get
		{
			float x = Distance * Math.Cos(Pitch) * Math.Sin(Yaw);
			float y = Distance * Math.Sin(Pitch);
			float z = Distance * Math.Cos(Pitch) * Math.Cos(Yaw);
			return Target + Vector3(x, y, z);
		}
	}

	public Vector3 Forward => Vector3.Normalize(Target - Position);

	public Matrix ViewMatrix => Matrix.CreateLookAt(Position, Target, Vector3.Up);

	public void Rotate(float deltaYaw, float deltaPitch)
	{
		Yaw += deltaYaw;
		Pitch = Math.Clamp(Pitch + deltaPitch, MinPitch, MaxPitch);
	}

	public void Zoom(float delta)
	{
		Distance = Math.Clamp(Distance - delta, MinDistance, MaxDistance);
	}

	public void Pan(float deltaX, float deltaY)
	{
		let forward = Vector3.Normalize(Target - Position);
		let right = Vector3.Normalize(Vector3.Cross(forward, Vector3.Up));
		let up = Vector3.Cross(right, forward);

		Target += right * deltaX * Distance * 0.01f;
		Target += up * deltaY * Distance * 0.01f;
	}

	public void FitToModel(BoundingBox bounds)
	{
		let center = (bounds.Min + bounds.Max) * 0.5f;
		let extents = (bounds.Max - bounds.Min) * 0.5f;
		Target = center;
		Distance = Math.Max(extents.Length() * 2.5f, 1.0f);
		Yaw = 0;
		Pitch = 0.3f;
	}

	/// Moves the camera target to focus on a point, keeping current orientation.
	public void FocusOn(Vector3 point)
	{
		Target = point;
	}

	/// Gets the right vector (perpendicular to forward and up).
	public Vector3 Right
	{
		get
		{
			let forward = Forward;
			return Vector3.Normalize(Vector3.Cross(forward, Vector3.Up));
		}
	}

	/// Gets the camera's local up vector.
	public Vector3 Up
	{
		get
		{
			let forward = Forward;
			let right = Vector3.Normalize(Vector3.Cross(forward, Vector3.Up));
			return Vector3.Cross(right, forward);
		}
	}

	/// Moves the camera in fly mode (WASD style).
	/// forward: +1 = forward (W), -1 = backward (S)
	/// right: +1 = right (D), -1 = left (A)
	/// up: +1 = up (E/Space), -1 = down (Q/Ctrl)
	public void Move(float forward, float right, float up, float speed)
	{
		let forwardDir = Forward;
		let rightDir = Right;

		// Move both camera and target together to preserve orbit distance
		let movement = forwardDir * forward * speed + rightDir * right * speed + Vector3.Up * up * speed;
		Target += movement;
	}
}
