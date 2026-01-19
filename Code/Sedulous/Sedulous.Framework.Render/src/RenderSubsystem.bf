namespace Sedulous.Framework.Render;

using System;
using Sedulous.Framework.Core;

/// Render subsystem for managing rendering.
public class RenderSubsystem : Subsystem
{
	/// Called at the end of each frame for rendering.
	public override void EndFrame()
	{
		// TODO: Submit render commands
	}

	/// Override to perform render subsystem initialization.
	protected override void OnInit()
	{
		// TODO: Initialize render resources
	}

	/// Override to perform render subsystem shutdown.
	protected override void OnShutdown()
	{
		// TODO: Cleanup render resources
	}
}
