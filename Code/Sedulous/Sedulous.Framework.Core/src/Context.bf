namespace Sedulous.Framework.Core;

using System;
using System.Collections;
using Sedulous.Profiler;

/// Central access point for all subsystems.
/// Manages subsystem registration, lifecycle, and update ordering.
public class Context : IDisposable
{
	private Dictionary<Type, Subsystem> mSubsystems = new .() ~ delete _;
	private List<Subsystem> mSortedSubsystems = new .() ~ delete _;
	private bool mIsRunning = false;
	private bool mDisposed = false;

	/// Returns true if the context is running.
	public bool IsRunning => mIsRunning;

	/// Gets all registered subsystems in update order.
	public List<Subsystem> Subsystems => mSortedSubsystems;

	/// Creates a new context.
	public this()
	{
	}

	/// Destructor - ensures Dispose is called.
	public ~this()
	{
		Dispose();
	}

	/// Registers a subsystem with the context.
	/// Subsystems are type-keyed and must extend Subsystem.
	/// Subsystems are updated in order based on their UpdateOrder property.
	public void RegisterSubsystem<T>(T subsystem) where T : Subsystem
	{
		let type = typeof(T);
		if (mSubsystems.ContainsKey(type))
			return;

		mSubsystems[type] = subsystem;
		RebuildSortedList();
		subsystem.OnRegister(this);

		if (mIsRunning)
			subsystem.Init();
	}

	/// Unregisters a subsystem from the context.
	public void UnregisterSubsystem<T>() where T : Subsystem
	{
		let type = typeof(T);
		if (mSubsystems.TryGetValue(type, let subsystem))
		{
			if (mIsRunning)
				subsystem.Shutdown();
			subsystem.OnUnregister();
			mSubsystems.Remove(type);
			RebuildSortedList();
		}
	}

	/// Gets a registered subsystem by type.
	/// Returns null if the subsystem is not registered.
	public T GetSubsystem<T>() where T : Subsystem
	{
		if (mSubsystems.TryGetValue(typeof(T), let subsystem))
			return (T)subsystem;
		return null;
	}

	/// Checks if a subsystem is registered.
	public bool HasSubsystem<T>() where T : Subsystem
	{
		return mSubsystems.ContainsKey(typeof(T));
	}

	/// Starts up the context and all registered subsystems.
	public virtual void Startup()
	{
		if (mIsRunning)
			return;

		// Initialize all subsystems in UpdateOrder
		for (let subsystem in mSortedSubsystems)
			subsystem.Init();

		mIsRunning = true;
	}

	/// Called at the beginning of each frame.
	public virtual void BeginFrame(float deltaTime)
	{
		if (!mIsRunning)
			return;

		for (let subsystem in mSortedSubsystems)
			subsystem.BeginFrame(deltaTime);
	}

	/// Calls FixedUpdate on all subsystems for deterministic simulation.
	/// Should be called from a fixed timestep loop (may be called multiple times per frame).
	public virtual void FixedUpdate(float fixedDeltaTime)
	{
		if (!mIsRunning)
			return;

		for (let subsystem in mSortedSubsystems)
		{
			let name = subsystem.GetType().GetName(.. scope .());
			using (SProfiler.Begin(name))
				subsystem.FixedUpdate(fixedDeltaTime);
		}
	}

	/// Updates all subsystems.
	public virtual void Update(float deltaTime)
	{
		if (!mIsRunning)
			return;

		for (let subsystem in mSortedSubsystems)
		{
			let name = subsystem.GetType().GetName(.. scope .());
			using (SProfiler.Begin(name))
				subsystem.Update(deltaTime);
		}
	}

	/// Calls PostUpdate on all subsystems.
	/// Called after Update, before EndFrame.
	public virtual void PostUpdate(float deltaTime)
	{
		if (!mIsRunning)
			return;

		for (let subsystem in mSortedSubsystems)
			subsystem.PostUpdate(deltaTime);
	}

	/// Called at the end of each frame.
	public virtual void EndFrame()
	{
		if (!mIsRunning)
			return;

		for (let subsystem in mSortedSubsystems)
			subsystem.EndFrame();
	}

	/// Shuts down all subsystems and the context.
	public virtual void Shutdown()
	{
		if (!mIsRunning)
			return;

		// Shutdown subsystems in reverse UpdateOrder (higher values first)
		for (int i = mSortedSubsystems.Count - 1; i >= 0; i--)
			mSortedSubsystems[i].Shutdown();

		mIsRunning = false;
	}

	/// Disposes the context and all owned subsystems.
	public virtual void Dispose()
	{
		if (mDisposed)
			return;
		mDisposed = true;

		Shutdown();

		// Dispose all subsystems in reverse order
		for (int i = mSortedSubsystems.Count - 1; i >= 0; i--)
		{
			let subsystem = mSortedSubsystems[i];
			subsystem.OnUnregister();
			subsystem.Dispose();
			delete subsystem;
		}

		mSubsystems.Clear();
		mSortedSubsystems.Clear();
	}

	/// Rebuilds the sorted subsystem list after registration changes.
	private void RebuildSortedList()
	{
		mSortedSubsystems.Clear();
		for (let subsystem in mSubsystems.Values)
			mSortedSubsystems.Add(subsystem);

		// Sort by UpdateOrder (lower values first)
		mSortedSubsystems.Sort(scope (a, b) => a.UpdateOrder <=> b.UpdateOrder);
	}
}
