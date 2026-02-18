namespace Sedulous.Framework.Physics;

using System;
using Sedulous.Framework.Scenes;
using Sedulous.Physics;
using Sedulous.Serialization;

/// Component for entities with physics bodies.
/// Exposes serializable physics properties that sync with the physics world.
/// The actual body handle is managed internally by PhysicsSceneModule.
struct RigidBodyComponent : ISerializableComponent
{
	/// Body type (Dynamic, Kinematic, Static).
	public BodyType BodyType;
	/// Mass of the body (only applies to dynamic bodies).
	public float Mass;
	/// Linear damping coefficient.
	public float LinearDamping;
	/// Angular damping coefficient.
	public float AngularDamping;
	/// Friction coefficient.
	public float Friction;
	/// Restitution (bounciness) coefficient.
	public float Restitution;
	/// Gravity multiplier (0 = no gravity, 1 = normal gravity).
	public float GravityFactor;
	/// Whether the body is enabled in the simulation.
	public bool Enabled;

	public void Dispose() mut { }

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer s) mut
	{
		var version = SerializationVersion;
		s.Version(ref version);
		s.Enum<BodyType>("bodyType", ref BodyType);
		s.Float("mass", ref Mass);
		s.Float("linearDamping", ref LinearDamping);
		s.Float("angularDamping", ref AngularDamping);
		s.Float("friction", ref Friction);
		s.Float("restitution", ref Restitution);
		s.Float("gravityFactor", ref GravityFactor);
		s.Bool("enabled", ref Enabled);
		return .Ok;
	}

	public static RigidBodyComponent Default => .() {
		BodyType = .Dynamic,
		Mass = 1.0f,
		LinearDamping = 0.0f,
		AngularDamping = 0.05f,
		Friction = 0.2f,
		Restitution = 0.0f,
		GravityFactor = 1.0f,
		Enabled = true
	};
}
