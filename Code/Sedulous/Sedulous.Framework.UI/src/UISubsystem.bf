namespace Sedulous.Framework.UI;

using System;
using Sedulous.Framework.Core;

/// UI subsystem for managing user interface.
public class UISubsystem : Subsystem
{
	/// Called during the main update phase for UI updates.
	public override void Update(float deltaTime)
	{
		// TODO: Update UI state
	}

	/// Override to perform UI subsystem initialization.
	protected override void OnInit()
	{
		// TODO: Initialize UI context
	}

	/// Override to perform UI subsystem shutdown.
	protected override void OnShutdown()
	{
		// TODO: Cleanup UI resources
	}
}
