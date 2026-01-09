using System;
using Sedulous.Engine.Core;

namespace Sedulous.Engine.Core.Tests;

/// Test service implementation.
class TestService : IContextService
{
	public bool WasRegistered = false;
	public bool WasUnregistered = false;
	public bool WasStarted = false;
	public bool WasShutdown = false;
	public float TotalDeltaTime = 0;
	public Context RegisteredContext = null;

	public void OnRegister(Context context)
	{
		WasRegistered = true;
		RegisteredContext = context;
	}

	public void OnUnregister()
	{
		WasUnregistered = true;
	}

	public void Startup()
	{
		WasStarted = true;
	}

	public void Shutdown()
	{
		WasShutdown = true;
	}

	public void Update(float deltaTime)
	{
		TotalDeltaTime += deltaTime;
	}
}

/// Another test service.
class AnotherTestService : IContextService
{
	public void OnRegister(Context context) { }
	public void OnUnregister() { }
	public void Startup() { }
	public void Shutdown() { }
	public void Update(float deltaTime) { }
}

class ContextTests
{
	[Test]
	public static void TestContextCreation()
	{
		let context = scope Context(null, 1);

		Test.Assert(context.JobSystem != null);
		Test.Assert(context.ResourceSystem != null);
		Test.Assert(context.SceneManager != null);
		Test.Assert(context.ComponentRegistry != null);
		Test.Assert(!context.IsRunning);
	}

	[Test]
	public static void TestStartup()
	{
		let context = scope Context(null, 1);

		context.Startup();
		Test.Assert(context.IsRunning);

		context.Shutdown();
	}

	[Test]
	public static void TestShutdown()
	{
		let context = scope Context(null, 1);

		context.Startup();
		context.Shutdown();

		Test.Assert(!context.IsRunning);
	}

	[Test]
	public static void TestRegisterService()
	{
		let context = scope Context(null, 1);

		let service = new TestService();
		context.RegisterService<TestService>(service);

		Test.Assert(service.WasRegistered);
		Test.Assert(service.RegisteredContext == context);
		Test.Assert(context.HasService<TestService>());

		delete service;
	}

	[Test]
	public static void TestGetService()
	{
		let context = scope Context(null, 1);

		let service = new TestService();
		context.RegisterService<TestService>(service);

		let retrieved = context.GetService<TestService>();
		Test.Assert(retrieved == service);

		delete service;
	}

	[Test]
	public static void TestGetServiceNotRegistered()
	{
		let context = scope Context(null, 1);

		let retrieved = context.GetService<TestService>();
		Test.Assert(retrieved == null);
	}

	[Test]
	public static void TestUnregisterService()
	{
		let context = scope Context(null, 1);

		let service = new TestService();
		context.RegisterService<TestService>(service);
		context.UnregisterService<TestService>();

		Test.Assert(service.WasUnregistered);
		Test.Assert(!context.HasService<TestService>());

		delete service;
	}

	[Test]
	public static void TestServiceStartupWithContext()
	{
		let context = scope Context(null, 1);

		let service = new TestService();
		context.RegisterService<TestService>(service);

		context.Startup();

		Test.Assert(service.WasStarted);

		context.Shutdown();
		delete service;
	}

	[Test]
	public static void TestServiceStartupAfterContext()
	{
		let context = scope Context(null, 1);

		context.Startup();

		let service = new TestService();
		context.RegisterService<TestService>(service);

		// Service should be started immediately when registered after context startup
		Test.Assert(service.WasStarted);

		context.Shutdown();
		delete service;
	}

	[Test]
	public static void TestServiceShutdown()
	{
		let context = scope Context(null, 1);

		let service = new TestService();
		context.RegisterService<TestService>(service);

		context.Startup();
		context.Shutdown();

		Test.Assert(service.WasShutdown);

		delete service;
	}

	[Test]
	public static void TestServiceUpdate()
	{
		let context = scope Context(null, 1);

		let service = new TestService();
		context.RegisterService<TestService>(service);

		context.Startup();
		context.Update(0.016f);

		Test.Assert(Math.Abs(service.TotalDeltaTime - 0.016f) < 0.0001f);

		context.Shutdown();
		delete service;
	}

	[Test]
	public static void TestMultipleServices()
	{
		let context = scope Context(null, 1);

		let service1 = new TestService();
		let service2 = new AnotherTestService();

		context.RegisterService<TestService>(service1);
		context.RegisterService<AnotherTestService>(service2);

		Test.Assert(context.HasService<TestService>());
		Test.Assert(context.HasService<AnotherTestService>());

		delete service1;
		delete service2;
	}

	[Test]
	public static void TestHasService()
	{
		let context = scope Context(null, 1);

		Test.Assert(!context.HasService<TestService>());

		let service = new TestService();
		context.RegisterService<TestService>(service);

		Test.Assert(context.HasService<TestService>());

		delete service;
	}
}
