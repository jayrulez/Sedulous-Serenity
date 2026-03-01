namespace Sedulous.Engine.Scenes;

using System;
using System.Collections;

/// Interface for scene modules to expose component data for the editor inspector.
/// Modules implement this via inner helper classes (one per component type),
/// and the editor uses reflection on the data structs to build property UI.
interface IComponentDataProvider
{
	/// Display name for the inspector category (e.g., "Light", "Camera").
	void GetDisplayName(String outName);

	/// The Type of the thin-handle component struct (e.g., typeof(LightComponent)).
	Type ComponentType { get; }

	/// The Type of the data struct (e.g., typeof(LightComponentData)).
	Type DataType { get; }

	/// Returns true if this entity has this component.
	bool HasComponent(EntityId entity);

	/// Fills outData (pointer to a stack-allocated data struct) with current values.
	/// Returns true if the entity has this component.
	bool GetComponentData(EntityId entity, void* outData);

	/// Applies values from inData (pointer to the data struct) back to the module.
	void SetComponentData(EntityId entity, void* inData);

	/// Creates a default instance of this component on the entity.
	/// Returns true if successfully created.
	bool CreateDefault(EntityId entity);

	/// Destroys this component on the entity.
	void Destroy(EntityId entity);
}
