namespace Sedulous.Editor.Scenes;

using System;
using System.Collections;
using Sedulous.Mathematics;

/// Serializable entity representation for scene assets.
public class EntityData
{
	/// Entity name (for editor display).
	public String Name = new .() ~ delete _;

	/// Unique ID within scene.
	public Guid EntityId;

	/// Local transform position.
	public Vector3 Position = .Zero;

	/// Local transform rotation (euler angles in degrees).
	public Vector3 Rotation = .Zero;

	/// Local transform scale.
	public Vector3 Scale = .One;

	/// Parent entity ID (Guid.Empty for root).
	public Guid ParentId;

	/// Components attached to this entity.
	public List<ComponentData> Components = new .() ~ DeleteContainerAndItems!(_);

	/// Child entity IDs (for hierarchy).
	public List<Guid> ChildIds = new .() ~ delete _;

	public this()
	{
		EntityId = Guid.Create();
	}

	public this(StringView name) : this()
	{
		Name.Set(name);
	}

	/// Creates a deep copy of this entity data.
	public EntityData Clone()
	{
		let clone = new EntityData();
		clone.Name.Set(Name);
		clone.EntityId = Guid.Create(); // New ID for clone
		clone.Position = Position;
		clone.Rotation = Rotation;
		clone.Scale = Scale;
		clone.ParentId = ParentId;

		for (let component in Components)
			clone.Components.Add(component.Clone());

		for (let childId in ChildIds)
			clone.ChildIds.Add(childId);

		return clone;
	}
}
