using System;
using System.Collections;
using Sedulous.Serialization;

namespace Sedulous.Framework.Core;

/// Factory delegate for creating component instances.
delegate IEntityComponent ComponentFactory();

/// Registry for entity component types.
/// Enables polymorphic component serialization by mapping type names to factories.
class ComponentRegistry : ISerializableFactory
{
	private Dictionary<String, ComponentFactory> mFactories = new .() ~ DeleteDictionaryAndKeysAndValues!(_);
	private Dictionary<Type, String> mTypeNames = new .() ~ delete _;

	/// Registers a component type with the given type name.
	public void Register<T>(StringView typeName) where T : IEntityComponent, class, new, delete
	{
		let typeNameStr = new String(typeName);
		delegate IEntityComponent() factory = new () => (IEntityComponent)new T();
		mFactories[typeNameStr] = factory;
		mTypeNames[typeof(T)] = typeNameStr;
	}

	/// Creates a component instance by type name.
	/// Returns null if the type name is not registered.
	public IEntityComponent Create(StringView typeName)
	{
		if (mFactories.TryGetValue(scope String(typeName), let factory))
			return factory();
		return null;
	}

	/// Gets the type name for a component type.
	/// Returns null if the type is not registered.
	public StringView GetTypeName<T>() where T : IEntityComponent
	{
		if (mTypeNames.TryGetValue(typeof(T), let name))
			return name;
		return default;
	}

	/// Gets the type name for a component instance.
	/// Returns null if the type is not registered.
	public StringView GetTypeName(IEntityComponent component)
	{
		if (mTypeNames.TryGetValue(component.GetType(), let name))
			return name;
		return default;
	}

	/// Checks if a type name is registered.
	public bool IsRegistered(StringView typeName)
	{
		return mFactories.ContainsKey(scope String(typeName));
	}

	/// Checks if a component type is registered.
	public bool IsRegistered<T>() where T : IEntityComponent
	{
		return mTypeNames.ContainsKey(typeof(T));
	}

	// ISerializableFactory implementation

	/// Creates a serializable instance from a type identifier.
	public ISerializable CreateInstance(StringView typeId)
	{
		return Create(typeId);
	}

	/// Gets the type identifier for a serializable object.
	public void GetTypeId(ISerializable obj, String typeId)
	{
		if (let component = obj as IEntityComponent)
		{
			let name = GetTypeName(component);
			if (name != default)
				typeId.Append(name);
		}
	}
}
