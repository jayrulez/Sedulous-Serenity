namespace StormTactics.Client;

using System;
using Sedulous.Shell;
using Sedulous.RHI;
using Sedulous.Framework.Runtime;
using Sedulous.Framework.Core;

class StormTacticsGame : Application
{
	public this(IShell shell, IDevice device, IBackend backend)
		: base(shell, device, backend)
	{
	}

	protected override void OnInitialize(Context context)
	{
		Sedulous.Imaging.SDL.SDLImageLoader.Initialize();

		Console.WriteLine("=== Storm Tactics ===");

		FixedTimeStep = 1.0f / 60.0f;
		MaxFixedStepsPerFrame = 3;
	}

	protected override void OnContextStarted()
	{
		Console.WriteLine("Storm Tactics initialized");
	}

	protected override void OnUpdate(FrameContext frame)
	{
	}

	protected override bool OnRenderFrame(RenderContext render)
	{
		return true;
	}

	protected override void OnShutdown()
	{
		Console.WriteLine("Storm Tactics shutting down");
	}
}
