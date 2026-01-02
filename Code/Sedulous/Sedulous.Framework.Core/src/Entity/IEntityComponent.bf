using Sedulous.Serialization;

namespace Sedulous.Framework.Core;

/// Interface for components that can be attached to entities.
/// Components add behavior and data to entities.
interface IEntityComponent : ISerializable
{
	/// Called when the component is attached to an entity.
	void OnAttach(Entity entity);

	/// Called when the component is detached from an entity.
	void OnDetach();

	/// Called each frame to update the component.
	void OnUpdate(float deltaTime);
}
