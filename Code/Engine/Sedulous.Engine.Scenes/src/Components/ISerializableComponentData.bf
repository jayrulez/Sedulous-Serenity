using Sedulous.Serialization;
namespace Sedulous.Engine.Scenes;

/// Interface for component data structs that can be serialized and deserialized.
/// Unlike IComponent (which marks thin runtime handles on entities), this is for
/// transient data payloads used during save/load. Like ISerializable, but with
/// `mut` on Serialize so struct fields can be modified during deserialization.
interface ISerializableComponentData
{
	/// Gets the serialization version for this component type.
	int32 SerializationVersion { get; }

	/// Serializes or deserializes this component's data.
	SerializationResult Serialize(Serializer s) mut;
}
