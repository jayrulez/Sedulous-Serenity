namespace Sedulous.Engine.Render;

using System;
using Sedulous.Engine.Scenes;
using Sedulous.Render;
using Sedulous.Serialization;

/// Transient data struct for CameraComponent serialization/deserialization.
/// Not stored on entities — only used by CameraComponentSerializer during save/load.
struct CameraComponentData : ISerializableComponentData
{
	public ProjectionType Projection;
	public float FieldOfView;
	public float AspectRatio;
	public float NearPlane;
	public float FarPlane;
	public float OrthoWidth;
	public float OrthoHeight;
	public int32 Priority;
	public bool Active;
	public bool IsMainCamera;

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

	public void Dispose() mut { }
}
