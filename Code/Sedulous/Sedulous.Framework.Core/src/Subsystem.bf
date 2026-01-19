namespace Sedulous.Framework.Core;

using System;

/// Base class for all engine subsystems.
/// Subsystems are managed by the application and provide services to scenes.
public abstract class Subsystem : IDisposable
{
	private bool mInitialized = false;

	/// Gets whether this subsystem has been initialized.
	public bool IsInitialized => mInitialized;

	/// Initializes the subsystem.
	public void Init()
	{
		if (!mInitialized)
		{
			OnInit();
			mInitialized = true;
		}
	}

	/// Shuts down the subsystem.
	public void Shutdown()
	{
		if (mInitialized)
		{
			OnShutdown();
			mInitialized = false;
		}
	}

	/// Called at the beginning of each frame.
	public virtual void BeginFrame(float deltaTime) { }

	/// Called during the main update phase.
	public virtual void Update(float deltaTime) { }

	/// Called at the end of each frame.
	public virtual void EndFrame() { }

	/// Override to perform subsystem initialization.
	protected virtual void OnInit() { }

	/// Override to perform subsystem shutdown.
	protected virtual void OnShutdown() { }

	/// Disposes the subsystem.
	public virtual void Dispose()
	{
		Shutdown();
	}
}
