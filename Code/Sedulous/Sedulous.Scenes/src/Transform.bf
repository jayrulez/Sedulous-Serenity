namespace Sedulous.Scenes;

using Sedulous.Mathematics;

/// Local transform data containing position, rotation, and scale.
/// This is the user-facing transform struct for getting/setting entity transforms.
/// The scene internally manages additional data like cached matrices and hierarchy.
public struct Transform
{
	/// Local position relative to parent (or world position if no parent).
	public Vector3 Position = .Zero;

	/// Local rotation relative to parent.
	public Quaternion Rotation = .Identity;

	/// Local scale.
	public Vector3 Scale = .(1, 1, 1);

	/// Creates a default identity transform.
	public this()
	{
	}

	/// Creates a transform with the specified position.
	public this(Vector3 position)
	{
		Position = position;
	}

	/// Creates a transform with the specified position and rotation.
	public this(Vector3 position, Quaternion rotation)
	{
		Position = position;
		Rotation = rotation;
	}

	/// Creates a transform with the specified position, rotation, and scale.
	public this(Vector3 position, Quaternion rotation, Vector3 scale)
	{
		Position = position;
		Rotation = rotation;
		Scale = scale;
	}

	/// Returns an identity transform (position=0, rotation=identity, scale=1).
	public static Transform Identity => .();

	/// Computes the local matrix from position, rotation, and scale.
	/// Matrix order: Scale * Rotation * Translation (SRT)
	public Matrix ToMatrix()
	{
		let s = Matrix.CreateScale(Scale);
		let r = Matrix.CreateFromQuaternion(Rotation);
		let t = Matrix.CreateTranslation(Position);
		return s * r * t;
	}
}
