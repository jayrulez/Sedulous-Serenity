namespace Sedulous.Engine.Input;

using System;
using System.Collections;
using Sedulous.Serialization;
using Sedulous.Shell.Input;

/// Binding type discriminator for serialization.
enum BindingType
{
	Key,
	MouseButton,
	MouseAxis,
	GamepadButton,
	GamepadAxis,
	GamepadStick,
	Composite
}

/// Serializable container for input bindings.
/// Used to save/load user-customized bindings.
class InputBindingsFile : ISerializable
{
	/// Entry for a single action's bindings.
	class ActionEntry : ISerializable
	{
		public String ContextName = new .() ~ delete _;
		public String ActionName = new .() ~ delete _;
		public List<InputBinding> Bindings = new .() ~ DeleteContainerAndItems!(_);

		public int32 SerializationVersion => 1;

		public SerializationResult Serialize(Serializer serializer)
		{
			var version = SerializationVersion;
			var result = serializer.Version(ref version);
			if (result != .Ok)
				return result;

			result = serializer.String("context", ContextName);
			if (result != .Ok)
				return result;

			result = serializer.String("action", ActionName);
			if (result != .Ok)
				return result;

			// Serialize binding count
			int32 count = (int32)Bindings.Count;
			result = serializer.Int32("bindingCount", ref count);
			if (result != .Ok)
				return result;

			if (serializer.IsReading)
			{
				// Read bindings
				for (int i = 0; i < count; i++)
				{
					int32 bindingType = 0;
					result = serializer.Int32(scope $"binding{i}_type", ref bindingType);
					if (result != .Ok)
						return result;

					let binding = CreateBinding((BindingType)bindingType);
					if (binding == null)
						continue;

					result = binding.Serialize(serializer);
					if (result != .Ok)
					{
						delete binding;
						return result;
					}
					Bindings.Add(binding);
				}
			}
			else
			{
				// Write bindings
				int i = 0;
				for (let binding in Bindings)
				{
					int32 bindingType = (int32)GetBindingType(binding);
					result = serializer.Int32(scope $"binding{i}_type", ref bindingType);
					if (result != .Ok)
						return result;

					result = binding.Serialize(serializer);
					if (result != .Ok)
						return result;
					i++;
				}
			}

			return .Ok;
		}
	}

	private List<ActionEntry> mEntries = new .() ~ DeleteContainerAndItems!(_);

	/// Adds an action's bindings to the file.
	public void AddAction(StringView contextName, InputAction action)
	{
		let entry = new ActionEntry();
		entry.ContextName.Set(contextName);
		entry.ActionName.Set(action.Name);
		for (int i = 0; i < action.BindingCount; i++)
		{
			let binding = action.GetBinding(i);
			if (binding != null)
				entry.Bindings.Add(binding.Clone());
		}
		mEntries.Add(entry);
	}

	/// Applies the bindings from this file to an InputService.
	public void ApplyTo(InputService service)
	{
		for (let entry in mEntries)
		{
			if (let ctx = service.GetContext(entry.ContextName))
			{
				if (let action = ctx.GetAction(entry.ActionName))
				{
					action.ClearBindings();
					for (let binding in entry.Bindings)
						action.AddBinding(binding.Clone());
				}
			}
		}
	}

	/// Gets the number of entries.
	public int EntryCount => mEntries.Count;

	/// Clears all entries.
	public void Clear()
	{
		DeleteContainerAndItems!(mEntries);
		mEntries = new .();
	}

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer serializer)
	{
		var version = SerializationVersion;
		var result = serializer.Version(ref version);
		if (result != .Ok)
			return result;

		int32 count = (int32)mEntries.Count;
		result = serializer.Int32("entryCount", ref count);
		if (result != .Ok)
			return result;

		if (serializer.IsReading)
		{
			for (int i = 0; i < count; i++)
			{
				let entry = new ActionEntry();
				result = entry.Serialize(serializer);
				if (result != .Ok)
				{
					delete entry;
					return result;
				}
				mEntries.Add(entry);
			}
		}
		else
		{
			for (let entry in mEntries)
			{
				result = entry.Serialize(serializer);
				if (result != .Ok)
					return result;
			}
		}

		return .Ok;
	}

	/// Creates a binding from a type discriminator.
	private static InputBinding CreateBinding(BindingType type)
	{
		switch (type)
		{
		case .Key: return new KeyBinding();
		case .MouseButton: return new MouseButtonBinding();
		case .MouseAxis: return new MouseAxisBinding();
		case .GamepadButton: return new GamepadButtonBinding();
		case .GamepadAxis: return new GamepadAxisBinding();
		case .GamepadStick: return new GamepadStickBinding();
		case .Composite: return new CompositeBinding();
		}
	}

	/// Gets the type discriminator for a binding.
	private static BindingType GetBindingType(InputBinding binding)
	{
		if (binding is KeyBinding) return .Key;
		if (binding is MouseButtonBinding) return .MouseButton;
		if (binding is MouseAxisBinding) return .MouseAxis;
		if (binding is GamepadButtonBinding) return .GamepadButton;
		if (binding is GamepadAxisBinding) return .GamepadAxis;
		if (binding is GamepadStickBinding) return .GamepadStick;
		if (binding is CompositeBinding) return .Composite;
		return .Key; // Fallback
	}
}
