using Sedulous.Mathematics;
using Sedulous.Framework.Audio;

namespace Sedulous.Framework.Audio.SDL3;

/// SDL3_mixer implementation of IAudioListener.
/// Handles 3D listener positioning and coordinate transformation.
class SDL3AudioListener : IAudioListener
{
	private Vector3 mPosition = .Zero;
	private Vector3 mForward = .(0, 0, -1);  // Looking down negative Z
	private Vector3 mUp = .(0, 1, 0);

	public Vector3 Position
	{
		get => mPosition;
		set => mPosition = value;
	}

	public Vector3 Forward
	{
		get => mForward;
		set => mForward = Vector3.Normalize(value);
	}

	public Vector3 Up
	{
		get => mUp;
		set => mUp = Vector3.Normalize(value);
	}

	/// Transforms a world position to listener-local coordinates.
	/// SDL_mixer expects positions relative to listener at origin, with:
	/// - Positive X = right
	/// - Positive Y = up
	/// - Positive Z = backward (away from listener's forward)
	public Vector3 WorldToLocal(Vector3 worldPos)
	{
		// Calculate relative position from listener
		let relativePos = worldPos - mPosition;

		// Calculate right vector (cross product of forward and up)
		let right = Vector3.Normalize(Vector3.Cross(mForward, mUp));

		// Transform to listener-local space using dot products
		// Note: SDL_mixer's Z is positive backward, but our forward is negative Z,
		// so we negate the Z component
		return .(
			Vector3.Dot(relativePos, right),
			Vector3.Dot(relativePos, mUp),
			-Vector3.Dot(relativePos, mForward)
		);
	}
}
