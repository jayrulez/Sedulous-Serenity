using Sedulous.Mathematics;
using Sedulous.Runtime;
using Sedulous.RHI;
using Sedulous.Shell;
using System;
namespace RenderSandbox;

/// Integrated sample demonstrating the full Render pipeline.
/// This sample shows how to use all Render systems together.
class RenderIntegratedApp : Application
{
	// Camera control
	private float mCameraYaw = 0;
	private float mCameraPitch = 0.3f;
	private float mCameraDistance = 5.0f;
	private Vector3 mCameraTarget = .Zero;


	public this(IShell shell, IDevice device, IBackend backend)
		: base(shell, device, backend)
	{
	}

	protected override void OnInitialize()
	{
		Console.WriteLine("=== Render Integrated Sample ===");
		Console.WriteLine("Demonstrating full renderer pipeline\n");

		let shaderPath = GetAssetPath("shaders", .. scope .());
		Console.WriteLine("Shader path: {}", shaderPath);

		Console.WriteLine("\n=== Initialization Complete ===");
		Console.WriteLine("Controls: WASD/Arrow keys to rotate camera, Q/E to zoom");
		Console.WriteLine("Press R for render stats");
		Console.WriteLine("Press ESC to exit\n");
	}
	private void UpdateCamera()
	{
		// Calculate camera position from spherical coordinates
		float x = mCameraDistance * Math.Cos(mCameraPitch) * Math.Sin(mCameraYaw);
		float y = mCameraDistance * Math.Sin(mCameraPitch);
		float z = mCameraDistance * Math.Cos(mCameraPitch) * Math.Cos(mCameraYaw);

		let position = mCameraTarget + Vector3(x, y, z);
		let forward = Vector3.Normalize(mCameraTarget - position);

	}

	protected override void OnInput()
	{
		let keyboard = mShell.InputManager.Keyboard;

		if (keyboard.IsKeyPressed(.Escape))
			Exit();

		// Camera rotation
		float rotSpeed = 0.02f;
		if (keyboard.IsKeyDown(.Left) || keyboard.IsKeyDown(.A))
			mCameraYaw -= rotSpeed;
		if (keyboard.IsKeyDown(.Right) || keyboard.IsKeyDown(.D))
			mCameraYaw += rotSpeed;
		if (keyboard.IsKeyDown(.Up) || keyboard.IsKeyDown(.W))
			mCameraPitch = Math.Clamp(mCameraPitch + rotSpeed, -1.4f, 1.4f);
		if (keyboard.IsKeyDown(.Down) || keyboard.IsKeyDown(.S))
			mCameraPitch = Math.Clamp(mCameraPitch - rotSpeed, -1.4f, 1.4f);

		// Camera zoom
		if (keyboard.IsKeyDown(.Q))
			mCameraDistance = Math.Clamp(mCameraDistance - 0.1f, 2.0f, 20.0f);
		if (keyboard.IsKeyDown(.E))
			mCameraDistance = Math.Clamp(mCameraDistance + 0.1f, 2.0f, 20.0f);

		// Stats
		if (keyboard.IsKeyPressed(.R))
			PrintStats();
	}

	private void PrintStats()
	{
		Console.WriteLine("\n=== Render Stats ===");
	}

	protected override void OnUpdate(FrameContext frame)
	{
		// Update camera
		UpdateCamera();

		
	}

	protected override bool OnRenderFrame(RenderContext render)
	{
		// Create main render pass
		RenderPassColorAttachment[1] colorAttachments = .(.()
		{
			View = render.CurrentTextureView,
			ResolveTarget = null,
			LoadOp = .Clear,
			StoreOp = .Store,
			ClearValue = render.ClearColor
		});

		RenderPassDescriptor mainDesc = .(colorAttachments);
		if (render.DepthTextureView != null)
		{
			mainDesc.DepthStencilAttachment = .()
			{
				View = render.DepthTextureView,
				DepthLoadOp = .Clear,
				DepthStoreOp = .Store,
				DepthClearValue = 1.0f,
				StencilLoadOp = .Clear,
				StencilStoreOp = .Store,
				StencilClearValue = 0
			};
		}

		let renderPass = render.Encoder.BeginRenderPass(&mainDesc);
		renderPass.SetViewport(0, 0, render.SwapChain.Width, render.SwapChain.Height, 0, 1);
		renderPass.SetScissorRect(0, 0, render.SwapChain.Width, render.SwapChain.Height);

		renderPass.End();
		delete renderPass;

		return true;  // We handled rendering
	}

	protected override void OnFrameEnd()
	{
	}

	protected override void OnShutdown()
	{
		Console.WriteLine("\n=== Shutting Down ===");

		Console.WriteLine("Shutdown complete");
	}
}