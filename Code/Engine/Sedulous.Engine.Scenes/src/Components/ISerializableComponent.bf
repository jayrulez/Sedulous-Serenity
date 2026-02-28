using Sedulous.Serialization;
namespace Sedulous.Engine.Scenes;

/// Interface for struct components that can be serialized and deserialized.
/// Like ISerializable, but with `mut` on Serialize so struct fields can be
/// modified during deserialization.
interface ISerializableComponent : IComponent
{
	/// Gets the serialization version for this component type.
	int32 SerializationVersion { get; }

	/// Serializes or deserializes this component's data.
	SerializationResult Serialize(Serializer s) mut;
}
