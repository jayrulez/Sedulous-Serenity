namespace Sedulous.RendererNext;

using System;
using Sedulous.Mathematics;

/// Camera uniform data for shaders.
/// Matches the layout expected by standard shaders.
[CRepr]
struct CameraData
{
	/// View matrix.
	public Matrix View;

	/// Projection matrix.
	public Matrix Projection;

	/// Combined view-projection matrix.
	public Matrix ViewProjection;

	/// Inverse view matrix.
	public Matrix InverseView;

	/// Inverse projection matrix.
	public Matrix InverseProjection;

	/// Inverse view-projection matrix.
	public Matrix InverseViewProjection;

	/// Camera position in world space.
	public Vector3 Position;
	private float _pad0;

	/// Camera forward direction.
	public Vector3 Forward;
	private float _pad1;

	/// Near plane distance.
	public float NearPlane;

	/// Far plane distance.
	public float FarPlane;

	/// Viewport width.
	public float ViewportWidth;

	/// Viewport height.
	public float ViewportHeight;

	/// Current time in seconds.
	public float Time;

	/// Delta time since last frame.
	public float DeltaTime;

	/// Frame index.
	public uint32 FrameIndex;

	private float _pad2;

	/// Creates camera data from a Camera struct.
	public static Self FromCamera(Camera camera, uint32 viewportWidth, uint32 viewportHeight, float time, float deltaTime, uint32 frameIndex)
	{
		let view = camera.GetViewMatrix();
		let projection = camera.GetProjectionMatrix();
		let viewProjection = view * projection;

		return .()
		{
			View = view,
			Projection = projection,
			ViewProjection = viewProjection,
			InverseView = Matrix.Invert(view),
			InverseProjection = Matrix.Invert(projection),
			InverseViewProjection = Matrix.Invert(viewProjection),
			Position = camera.Position,
			Forward = camera.Forward,
			NearPlane = camera.NearPlane,
			FarPlane = camera.FarPlane,
			ViewportWidth = (float)viewportWidth,
			ViewportHeight = (float)viewportHeight,
			Time = time,
			DeltaTime = deltaTime,
			FrameIndex = frameIndex
		};
	}

	/// Size in bytes.
	public static int32 SizeInBytes => sizeof(Self);
}

/// Per-object uniform data for shaders.
[CRepr]
struct ObjectData
{
	/// World transform matrix.
	public Matrix World;

	/// Inverse transpose of world matrix (for normals).
	public Matrix WorldInverseTranspose;

	/// Object ID for picking/identification.
	public uint32 ObjectId;

	/// Material index.
	public uint32 MaterialIndex;

	private uint32 _pad0;
	private uint32 _pad1;

	/// Creates object data from a transform.
	public static Self FromTransform(Matrix transform, uint32 objectId = 0, uint32 materialIndex = 0)
	{
		return .()
		{
			World = transform,
			WorldInverseTranspose = Matrix.Transpose(Matrix.Invert(transform)),
			ObjectId = objectId,
			MaterialIndex = materialIndex
		};
	}

	/// Size in bytes.
	public static int32 SizeInBytes => sizeof(Self);
}
