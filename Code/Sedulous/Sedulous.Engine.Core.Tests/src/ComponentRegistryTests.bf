using System;
using Sedulous.Engine.Core;
using Sedulous.Serialization;

namespace Sedulous.Engine.Core.Tests;

/// Registerable test component.
class RegisterableComponent : IEntityComponent
{
	public int32 Data = 0;

	public int32 SerializationVersion => 1;

	public void OnAttach(Entity entity) { }
	public void OnDetach() { }
	public void OnUpdate(float deltaTime) { }

	public SerializationResult Serialize(Serializer serializer)
	{
		return serializer.Int32("data", ref Data);
	}
}

/// Another registerable component.
class AnotherComponent : IEntityComponent
{
	public int32 SerializationVersion => 1;

	public void OnAttach(Entity entity) { }
	public void OnDetach() { }
	public void OnUpdate(float deltaTime) { }

	public SerializationResult Serialize(Serializer serializer)
	{
		return .Ok;
	}
}

class ComponentRegistryTests
{
	[Test]
	public static void TestRegister()
	{
		let registry = scope ComponentRegistry();

		registry.Register<RegisterableComponent>("RegisterableComponent");

		Test.Assert(registry.IsRegistered<RegisterableComponent>());
		Test.Assert(registry.IsRegistered("RegisterableComponent"));
	}

	[Test]
	public static void TestGetTypeName()
	{
		let registry = scope ComponentRegistry();

		registry.Register<RegisterableComponent>("MyComponent");

		let name = registry.GetTypeName<RegisterableComponent>();
		Test.Assert(name == "MyComponent");
	}

	[Test]
	public static void TestCreate()
	{
		let registry = scope ComponentRegistry();

		registry.Register<RegisterableComponent>("RegisterableComponent");

		let component = registry.Create("RegisterableComponent");
		defer delete component;

		Test.Assert(component != null);
		Test.Assert(component is RegisterableComponent);
	}

	[Test]
	public static void TestCreateUnregistered()
	{
		let registry = scope ComponentRegistry();

		let component = registry.Create("NonExistent");

		Test.Assert(component == null);
	}

	[Test]
	public static void TestMultipleRegistrations()
	{
		let registry = scope ComponentRegistry();

		registry.Register<RegisterableComponent>("ComponentA");
		registry.Register<AnotherComponent>("ComponentB");

		Test.Assert(registry.IsRegistered<RegisterableComponent>());
		Test.Assert(registry.IsRegistered<AnotherComponent>());
		Test.Assert(registry.IsRegistered("ComponentA"));
		Test.Assert(registry.IsRegistered("ComponentB"));
	}

	[Test]
	public static void TestGetTypeNameForInstance()
	{
		let registry = scope ComponentRegistry();

		registry.Register<RegisterableComponent>("TestComponent");

		let component = new RegisterableComponent();
		defer delete component;

		let name = registry.GetTypeName(component);
		Test.Assert(name == "TestComponent");
	}

	[Test]
	public static void TestGetTypeNameUnregistered()
	{
		let registry = scope ComponentRegistry();

		let name = registry.GetTypeName<RegisterableComponent>();
		Test.Assert(name == default);
	}

	[Test]
	public static void TestIsRegisteredFalse()
	{
		let registry = scope ComponentRegistry();

		Test.Assert(!registry.IsRegistered<RegisterableComponent>());
		Test.Assert(!registry.IsRegistered("NonExistent"));
	}

	[Test]
	public static void TestSerializableFactory()
	{
		let registry = scope ComponentRegistry();

		registry.Register<RegisterableComponent>("RegisterableComponent");

		// Test ISerializableFactory interface
		ISerializableFactory factory = registry;

		let serializable = factory.CreateInstance("RegisterableComponent");
		defer delete serializable;

		Test.Assert(serializable != null);
		Test.Assert(serializable is RegisterableComponent);
	}

	[Test]
	public static void TestGetTypeIdFromFactory()
	{
		let registry = scope ComponentRegistry();

		registry.Register<RegisterableComponent>("RegisterableComponent");

		let component = new RegisterableComponent();
		defer delete component;

		let typeId = scope String();
		registry.GetTypeId(component, typeId);

		Test.Assert(typeId == "RegisterableComponent");
	}
}
