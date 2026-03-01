namespace Sedulous.Engine.Physics;

using System;
using Sedulous.Core.Mathematics;
using Sedulous.Physics;
using Sedulous.Serialization;

/// Transient serialization data for RigidBodyComponent.
/// Only exists during save/load — not stored at runtime.
struct RigidBodyComponentData
{
	public BodyType BodyType;
	public float Mass;
	public float LinearDamping;
	public float AngularDamping;
	public float Friction;
	public float Restitution;
	public float GravityFactor;
	public bool Enabled;
	public DebugShapeType ShapeType;
	public Vector3 HalfExtents;

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
		s.Enum<DebugShapeType>("shapeType", ref ShapeType);
		s.FixedFloatArray("halfExtents", &HalfExtents.X, 3);
		return .Ok;
	}

	public void Dispose() mut { }

	public static RigidBodyComponentData Default => .() {
		BodyType = .Dynamic,
		Mass = 1.0f,
		LinearDamping = 0.0f,
		AngularDamping = 0.05f,
		Friction = 0.2f,
		Restitution = 0.0f,
		GravityFactor = 1.0f,
		Enabled = true,
		ShapeType = .None,
		HalfExtents = .Zero
	};
}
