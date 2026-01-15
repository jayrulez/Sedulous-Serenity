namespace RendererNGSandbox;

using System;
using Sedulous.Mathematics;
using Sedulous.RendererNG;

extension RendererNGSandboxApp
{
	/// Tests the RenderFrame and RenderView system (Phase 1.5)
	private void TestRenderFrameAndViews()
	{
		Console.WriteLine("\n--- Testing RenderFrame and RenderView ---");

		// Create a RenderFrame
		let frame = new RenderFrame();
		defer delete frame;

		// Test frame initialization
		Console.WriteLine("\nTesting RenderFrame...");
		frame.Begin(0, 0.016f, 1.5f);
		Console.WriteLine("  Frame initialized: index={0}, deltaTime={1}, totalTime={2}",
			frame.FrameIndex, frame.DeltaTime, frame.TotalTime);

		// Test creating camera views using factory methods
		Console.WriteLine("\nTesting RenderView factory methods...");

		// Create a perspective camera view
		let mainCamera = RenderView.CreateCamera(
			"MainCamera",
			.(0, 5, 10),           // position
			.(0, -0.3f, -1),       // forward (looking slightly down)
			.(0, 1, 0),            // up
			Math.PI_f / 4.0f,      // 45 degree FOV
			16.0f / 9.0f,          // aspect ratio
			0.1f,                  // near
			1000.0f,               // far
			1920, 1080             // viewport
		);
		defer delete mainCamera;

		Console.WriteLine("  Created MainCamera:");
		Console.WriteLine("    Position: ({0}, {1}, {2})",
			mainCamera.Position.X, mainCamera.Position.Y, mainCamera.Position.Z);
		Console.WriteLine("    Forward: ({0:F2}, {1:F2}, {2:F2})",
			mainCamera.Forward.X, mainCamera.Forward.Y, mainCamera.Forward.Z);
		Console.WriteLine("    Viewport: {0}x{1}", mainCamera.ViewportWidth, mainCamera.ViewportHeight);
		Console.WriteLine("    IsEnabled: {0}", mainCamera.IsEnabled);

		// Check matrices are computed
		let vp = mainCamera.ViewProjectionMatrix;
		Console.WriteLine("    ViewProjection computed: {0}", vp.M11 != 0 || vp.M22 != 0);

		// Add view to frame
		let slot = frame.AddView(mainCamera);
		Console.WriteLine("    Added to frame at slot: {0}", slot);
		Console.WriteLine("    Frame view count: {0}", frame.ViewCount);
		Console.WriteLine("    MainView matches: {0}", frame.MainView == mainCamera);

		// Test creating view from CameraProxy
		Console.WriteLine("\nTesting RenderView from CameraProxy...");
		let cameraHandle = mRenderWorld.CreateCamera(CameraProxy.DefaultPerspective);
		if (let cameraProxy = mRenderWorld.GetCamera(cameraHandle))
		{
			cameraProxy.Position = .(5, 3, 8);
			cameraProxy.Forward = Vector3.Normalize(.(-1, -0.2f, -1));
			cameraProxy.Up = .(0, 1, 0);
			cameraProxy.Right = Vector3.Normalize(Vector3.Cross(cameraProxy.Forward, cameraProxy.Up));

			let proxyView = RenderView.CreateFromCameraProxy(cameraProxy, 1920, 1080);
			defer delete proxyView;

			Console.WriteLine("  Created view from CameraProxy:");
			Console.WriteLine("    Position: ({0}, {1}, {2})",
				proxyView.Position.X, proxyView.Position.Y, proxyView.Position.Z);
			Console.WriteLine("    Type: {0}", proxyView.Type);

			let slot2 = frame.AddView(proxyView);
			Console.WriteLine("    Added to frame at slot: {0}", slot2);
		}

		// Test frustum planes
		Console.WriteLine("\nTesting frustum plane extraction...");
		Console.WriteLine("  Frustum planes extracted (6 planes):");
		for (int i = 0; i < 6; i++)
		{
			let plane = mainCamera.FrustumPlanes[i];
			String[6] planeNames = .("Left", "Right", "Bottom", "Top", "Near", "Far");
			Console.WriteLine("    {0}: normal=({1:F2}, {2:F2}, {3:F2}), d={4:F2}",
				planeNames[i], plane.Normal.X, plane.Normal.Y, plane.Normal.Z, plane.D);
		}

		// Test shadow cascade view
		Console.WriteLine("\nTesting shadow cascade view...");
		let lightDir = Vector3.Normalize(.(0.5f, -1, 0.3f));
		let shadowViewMat = Matrix.CreateLookAt(.(0, 100, 0), .(0, 0, 0), .(0, 0, 1));
		let shadowProjMat = Matrix.CreateOrthographic(100, 100, 0.1f, 200);

		let shadowView = RenderView.CreateShadowCascade(0, lightDir, shadowViewMat, shadowProjMat, 2048);
		defer delete shadowView;

		Console.WriteLine("  Created shadow cascade view:");
		Console.WriteLine("    Type: {0}", shadowView.Type);
		Console.WriteLine("    CascadeIndex: {0}", shadowView.CascadeIndex);
		Console.WriteLine("    Priority: {0}", shadowView.Priority);
		Console.WriteLine("    IsDepthOnly: {0}", shadowView.IsDepthOnly);
		Console.WriteLine("    Resolution: {0}x{1}", shadowView.ViewportWidth, shadowView.ViewportHeight);

		let shadowSlot = frame.AddShadowView(shadowView);
		Console.WriteLine("    Added as shadow view at slot: {0}", shadowSlot);
		Console.WriteLine("    Frame shadow view count: {0}", frame.ShadowViewCount);

		// Test previous transform saving
		Console.WriteLine("\nTesting motion vector support...");
		mainCamera.SavePreviousTransform();
		let prevVP = mainCamera.PreviousViewProjectionMatrix;
		Console.WriteLine("  PreviousViewProjection saved: {0}", prevVP.M11 != 0 || prevVP.M22 != 0);

		// Test frame end and reset
		Console.WriteLine("\nTesting frame lifecycle...");
		frame.End();
		Console.WriteLine("  Frame ended");

		// Begin new frame
		frame.Begin(1, 0.016f, 1.516f);
		Console.WriteLine("  New frame started: index={0}, views cleared: {1}",
			frame.FrameIndex, frame.ViewCount == 0);

		Console.WriteLine("\nRenderFrame and RenderView tests complete!");
	}
}
