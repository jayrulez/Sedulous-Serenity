namespace Sedulous.Engine.Render;

using System;
using Sedulous.Engine.Scenes;
using Sedulous.Render;
using Sedulous.Serialization;

/// Component for camera entities.
/// Stores the full camera configuration needed to create and update a render proxy.
[Component]
struct CameraComponent : ISerializableComponent
{
	/// Projection type (Perspective or Orthographic).
	[Property] public ProjectionType Projection;
	/// Field of view in radians (for perspective).
	[Property] public float FieldOfView;
	/// Aspect ratio (width / height).
	[Property] public float AspectRatio;
	/// Near clipping plane distance.
	[Property] public float NearPlane;
	/// Far clipping plane distance.
	[Property] public float FarPlane;
	/// Orthographic width (for orthographic projection).
	[Property] public float OrthoWidth;
	/// Orthographic height (for orthographic projection).
	[Property] public float OrthoHeight;
	/// Render priority (higher = rendered first for multi-camera setups).
	[Property] public int32 Priority;
	/// Whether this camera is active.
	[Property] public bool Active;
	/// Whether this is the main camera.
	[Property] public bool IsMainCamera;

	public void Dispose() mut { }

	public int32 SerializationVersion => 2;

	public SerializationResult Serialize(Serializer s) mut
	{
		var version = SerializationVersion;
		s.Version(ref version);
		if (version >= 2)
		{
			s.Enum<ProjectionType>("projection", ref Projection);
			s.Float("fieldOfView", ref FieldOfView);
			s.Float("aspectRatio", ref AspectRatio);
			s.Float("nearPlane", ref NearPlane);
			s.Float("farPlane", ref FarPlane);
			s.Float("orthoWidth", ref OrthoWidth);
			s.Float("orthoHeight", ref OrthoHeight);
			s.Int32("priority", ref Priority);
		}
		s.Bool("active", ref Active);
		s.Bool("isMainCamera", ref IsMainCamera);
		return .Ok;
	}

	public static CameraComponent Default => .() {
		Projection = .Perspective,
		FieldOfView = Math.PI_f / 4.0f,
		AspectRatio = 16.0f / 9.0f,
		NearPlane = 0.1f,
		FarPlane = 1000.0f,
		OrthoWidth = 10.0f,
		OrthoHeight = 10.0f,
		Priority = 0,
		Active = true,
		IsMainCamera = false
	};
}
