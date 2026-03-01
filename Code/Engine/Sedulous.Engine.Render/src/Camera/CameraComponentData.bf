namespace Sedulous.Engine.Render;

using System;
using Sedulous.Engine.Scenes;
using Sedulous.Render;
using Sedulous.Serialization;

/// Transient data struct for CameraComponent serialization/deserialization.
/// Not stored on entities — only used by CameraComponentSerializer during save/load.
struct CameraComponentData : ISerializableComponentData
{
	[Property]
	public ProjectionType Projection;
	[Property]
	public float FieldOfView;
	[Property]
	public float AspectRatio;
	[Property]
	public float NearPlane;
	[Property]
	public float FarPlane;
	[Property]
	public float OrthoWidth;
	[Property]
	public float OrthoHeight;
	[Property]
	public int32 Priority;
	[Property]
	public bool Active;
	[Property]
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
