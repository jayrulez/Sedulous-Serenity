namespace FrameworkSerialization;

using System;
using Sedulous.Serialization;
using Sedulous.Engine.Scenes;

[Component]
struct TestComponent : ISerializableComponent
{
	public float Speed;
	public int32 Health;
	public bool Active;

	public void Dispose() mut { }

	public int32 SerializationVersion => 1;

	public this()
	{
		Speed = default;
		Health = default;
		Active = default;
	}

	public SerializationResult Serialize(Serializer s) mut
	{
		var version = SerializationVersion;
		s.Version(ref version);
		s.Float("speed", ref Speed);
		s.Int32("health", ref Health);
		s.Bool("active", ref Active);
		return .Ok;
	}
}
