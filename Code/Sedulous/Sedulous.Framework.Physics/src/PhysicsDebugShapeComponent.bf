namespace Sedulous.Framework.Physics;

using Sedulous.Framework.Scenes;
using Sedulous.Mathematics;
using Sedulous.Serialization;

/// Shape type for debug drawing.
enum DebugShapeType
{
	None,
	Box,
	Sphere,
	Capsule,
	Cylinder
}

/// Component storing shape info for debug drawing.
struct PhysicsDebugShapeComponent : ISerializableComponent
{
	public DebugShapeType ShapeType;
	public Vector3 HalfExtents;  // Box: half extents, Sphere: (radius, 0, 0), Capsule/Cylinder: (radius, halfHeight, 0)

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer s) mut
	{
		var version = SerializationVersion;
		s.Version(ref version);
		s.Enum<DebugShapeType>("shapeType", ref ShapeType);
		s.FixedFloatArray("halfExtents", &HalfExtents.X, 3);
		return .Ok;
	}

	public static PhysicsDebugShapeComponent Default => .() {
		ShapeType = .None,
		HalfExtents = .Zero
	};
}
