namespace Sedulous.Framework.Input;

using System;
using Sedulous.Framework.Core;

/// Input subsystem for managing input devices and events.
public class InputSubsystem : Subsystem
{
	/// Called at the beginning of each frame to poll input.
	public override void BeginFrame(float deltaTime)
	{
		// TODO: Poll input devices
	}

	/// Override to perform input subsystem initialization.
	protected override void OnInit()
	{
		// TODO: Initialize input system
	}

	/// Override to perform input subsystem shutdown.
	protected override void OnShutdown()
	{
		// TODO: Cleanup input resources
	}
}
