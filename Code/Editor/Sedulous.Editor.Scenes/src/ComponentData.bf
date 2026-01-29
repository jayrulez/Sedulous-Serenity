namespace Sedulous.Editor.Scenes;

using System;
using System.Collections;

/// Serializable component representation for scene assets.
public class ComponentData
{
	/// Component type name (e.g., "MeshRendererComponent", "DirectionalLightComponent").
	public String TypeName = new .() ~ delete _;

	/// Serialized component properties as key-value pairs.
	/// Values are stored as strings for serialization simplicity.
	public Dictionary<String, String> Properties = new .() ~ DeleteDictionaryAndValues!(_);

	public this()
	{
	}

	public this(StringView typeName)
	{
		TypeName.Set(typeName);
	}

	/// Set a property value.
	public void SetProperty(StringView name, StringView value)
	{
		// Find existing key or create new one
		String existingKey = null;
		for (let key in Properties.Keys)
		{
			if (key.Equals(name, .OrdinalIgnoreCase))
			{
				existingKey = key;
				break;
			}
		}

		if (existingKey != null)
		{
			// Update existing
			if (Properties.GetValue(existingKey) case .Ok(let existingValue))
			{
				existingValue.Set(value);
			}
		}
		else
		{
			// Add new
			Properties[new String(name)] = new String(value);
		}
	}

	/// Get a property value.
	public bool TryGetProperty(StringView name, String outValue)
	{
		for (let (key, val) in Properties)
		{
			if (key.Equals(name, .OrdinalIgnoreCase))
			{
				outValue.Set(val);
				return true;
			}
		}
		return false;
	}

	/// Creates a deep copy of this component data.
	public ComponentData Clone()
	{
		let clone = new ComponentData();
		clone.TypeName.Set(TypeName);

		for (let (key, val) in Properties)
			clone.Properties[new String(key)] = new String(val);

		return clone;
	}
}
