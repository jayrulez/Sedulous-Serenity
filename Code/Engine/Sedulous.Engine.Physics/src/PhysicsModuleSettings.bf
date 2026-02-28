namespace Sedulous.Engine.Physics;

using Sedulous.Serialization;
using Sedulous.Engine.Scenes;
using System;

/// Persistent settings for the physics scene module.
/// Auto-discovered by Scene and serialized in .scene files.
[ModuleSettings("PhysicsSceneModule", "Physics")]
class PhysicsModuleSettings : ISerializable
{
	[Property] public int32 CollisionSteps = 1;

	public int32 SerializationVersion => 1;

	public this(){}

	public SerializationResult Serialize(Serializer s)
	{
		s.Int32("collisionSteps", ref CollisionSteps);
		return .Ok;
	}
}
