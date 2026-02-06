namespace Sedulous.Framework.Scenes;

using System.Collections;
using Sedulous.Serialization;
using System;

/// Type-erased interface for serializing a specific component type.
/// Each registered serializer handles one component type (e.g., TestComponent).
interface IComponentSerializer
{
	/// The type name used as key in serialized data.
	StringView TypeName { get; }

	/// Creates a new instance of this serializer (same component type).
	/// WORKAROUND: Beef compiler bug - generic constraints don't propagate into
	/// lambdas across project boundaries. SceneResource uses this instead of a
	/// lambda calling scene.RegisterComponentSerializer<T>().
	/// See BeefBugs/GenericLambdaCrossProject/ for repro.
	/// When fixed, remove CreateNew() and use lambda approach in SceneResource.
	IComponentSerializer CreateNew();

	/// Writes all components of this type for active entities.
	SerializationResult Write(Scene scene, Serializer s, Dictionary<uint32, int32> entityIndexMap);

	/// Reads components from serialized data and assigns them to entities.
	SerializationResult Read(Scene scene, Serializer s, List<EntityId> loadedEntities);
}
