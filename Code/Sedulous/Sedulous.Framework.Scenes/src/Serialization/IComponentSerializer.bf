namespace Sedulous.Framework.Scenes;

using System.Collections;
using Sedulous.Serialization;
using System;

/// Type-erased interface for serializing a specific component type.
/// Each registered serializer handles one component type (e.g., LightComponent).
interface IComponentSerializer
{
	/// The type name used as key in serialized data.
	StringView TypeName { get; }

	/// Writes all components of this type for active entities.
	SerializationResult Write(Scene scene, Serializer s, Dictionary<uint32, int32> entityIndexMap);

	/// Reads components from serialized data and assigns them to entities.
	SerializationResult Read(Scene scene, Serializer s, List<EntityId> loadedEntities);
}
