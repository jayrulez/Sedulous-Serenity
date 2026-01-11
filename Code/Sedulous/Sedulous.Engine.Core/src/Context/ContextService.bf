namespace Sedulous.Engine.Core;

/// Base class for services that can be registered with the Context.
/// Services provide functionality that can be accessed throughout the application.
abstract class ContextService
{
	/// Called when the service is registered with the context.
	public virtual void OnRegister(Context context) {}

	/// Called when the service is unregistered from the context.
	public virtual void OnUnregister() {}

	/// Called during context startup.
	public virtual void Startup() {}

	/// Called during context shutdown.
	public virtual void Shutdown() {}

	/// Called each frame during context update.
	public abstract void Update(float deltaTime);

	/// Called when a scene is created via SceneManager.
	/// Override to automatically add scene components.
	public virtual void OnSceneCreated(Scene scene) {}

	/// Called when a scene is being destroyed.
	/// Scene components are automatically detached; use this for service-level cleanup.
	public virtual void OnSceneDestroyed(Scene scene) {}
}
