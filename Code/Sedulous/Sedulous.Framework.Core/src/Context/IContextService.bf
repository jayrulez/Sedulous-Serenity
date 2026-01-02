namespace Sedulous.Framework.Core;

/// Interface for services that can be registered with the Context.
/// Services provide functionality that can be accessed throughout the application.
interface IContextService
{
	/// Called when the service is registered with the context.
	void OnRegister(Context context);

	/// Called when the service is unregistered from the context.
	void OnUnregister();

	/// Called during context startup.
	void Startup();

	/// Called during context shutdown.
	void Shutdown();

	/// Called each frame during context update.
	void Update(float deltaTime);
}
