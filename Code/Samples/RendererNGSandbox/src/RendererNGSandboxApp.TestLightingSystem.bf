namespace RendererNGSandbox;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.RendererNG;

extension RendererNGSandboxApp
{
	/// Tests the cluster grid.
	public void TestClusterGrid()
	{
		Console.WriteLine("\n=== Testing Cluster Grid ===\n");

		let grid = scope ClusterGrid(16, 9, 24);
		Console.WriteLine("Created ClusterGrid:");
		Console.WriteLine("  Grid size: {}x{}x{}", grid.GridSizeX, grid.GridSizeY, grid.GridSizeZ);
		Console.WriteLine("  Total clusters: {}", grid.TotalClusters);

		// Initialize GPU buffers
		switch (grid.Initialize(mDevice))
		{
		case .Ok:
			Console.WriteLine("  GPU buffers initialized: True");
		case .Err:
			Console.WriteLine("  ERROR: Failed to initialize GPU buffers");
			return;
		}

		// Test cluster bounds computation
		let projection = Matrix.CreatePerspectiveFieldOfView(
			Math.PI_f / 4, // 45 degree FOV
			16.0f / 9.0f,  // 16:9 aspect
			0.1f,          // Near plane
			1000.0f        // Far plane
		);

		grid.ComputeClusterBounds(projection, 0.1f, 1000.0f, 1920, 1080);
		Console.WriteLine("  Cluster bounds computed for 1920x1080");

		// Test depth slice calculation
		Console.WriteLine("\nDepth slice tests:");
		Console.WriteLine("  Depth 0.1 -> slice {}", grid.GetDepthSlice(0.1f));
		Console.WriteLine("  Depth 1.0 -> slice {}", grid.GetDepthSlice(1.0f));
		Console.WriteLine("  Depth 10.0 -> slice {}", grid.GetDepthSlice(10.0f));
		Console.WriteLine("  Depth 100.0 -> slice {}", grid.GetDepthSlice(100.0f));
		Console.WriteLine("  Depth 1000.0 -> slice {}", grid.GetDepthSlice(1000.0f));

		// Test cluster index calculation
		let idx = grid.GetClusterIndex(8, 4, 12);
		Console.WriteLine("\nCluster index (8,4,12) = {}", idx);

		let stats = scope String();
		grid.GetStats(stats);
		Console.WriteLine("\nStats:\n{}", stats);

		Console.WriteLine("Cluster Grid tests passed!");
	}

	/// Tests the light buffer.
	public void TestLightBuffer()
	{
		Console.WriteLine("\n=== Testing Light Buffer ===\n");

		let lightBuffer = scope LightBuffer();

		// Initialize GPU buffers
		switch (lightBuffer.Initialize(mDevice))
		{
		case .Ok:
			Console.WriteLine("LightBuffer initialized");
		case .Err:
			Console.WriteLine("ERROR: Failed to initialize LightBuffer");
			return;
		}

		// Test light data structures
		Console.WriteLine("\nLightData size: {} bytes", LightData.Size);
		Console.WriteLine("LightingParams size: {} bytes", LightingParams.Size);

		// Add lights
		lightBuffer.AddDirectionalLight(
			.(0.5f, -1.0f, 0.3f),  // Direction
			.(1.0f, 0.95f, 0.9f), // Color
			1.5f                   // Intensity
		);
		Console.WriteLine("\nAdded directional light");

		lightBuffer.AddPointLight(
			.(10, 5, 0),          // Position
			15.0f,                // Range
			.(1.0f, 0.8f, 0.6f), // Color
			2.0f                  // Intensity
		);
		Console.WriteLine("Added point light");

		lightBuffer.AddSpotLight(
			.(0, 10, 0),          // Position
			.(0, -1, 0),          // Direction
			20.0f,                // Range
			0.3f,                 // Inner angle (radians)
			0.5f,                 // Outer angle (radians)
			.(0.8f, 0.8f, 1.0f), // Color
			3.0f                  // Intensity
		);
		Console.WriteLine("Added spot light");

		Console.WriteLine("\nLight count: {}", lightBuffer.LightCount);

		// Test ambient/sun configuration
		lightBuffer.SetAmbient(.(0.1f, 0.1f, 0.15f), 0.5f);
		lightBuffer.SetSun(.(0.5f, -1.0f, 0.3f), .(1, 0.95f, 0.9f), 2.0f);
		Console.WriteLine("Set ambient and sun parameters");

		// Upload to GPU
		lightBuffer.Upload();
		Console.WriteLine("Uploaded to GPU");

		let stats = scope String();
		lightBuffer.GetStats(stats);
		Console.WriteLine("\n{}", stats);

		Console.WriteLine("Light Buffer tests passed!");
	}

	/// Tests the lighting system facade.
	public void TestLightingSystemFacade()
	{
		Console.WriteLine("\n=== Testing Lighting System ===\n");

		let lightingSystem = scope LightingSystem(16, 9, 24);

		// Initialize
		switch (lightingSystem.Initialize(mDevice))
		{
		case .Ok:
			Console.WriteLine("LightingSystem initialized");
		case .Err:
			Console.WriteLine("ERROR: Failed to initialize LightingSystem");
			return;
		}

		// Set view parameters
		let view = Matrix.CreateLookAt(.(0, 5, 10), .Zero, .UnitY);
		let projection = Matrix.CreatePerspectiveFieldOfView(
			Math.PI_f / 4, 16.0f / 9.0f, 0.1f, 1000.0f);

		lightingSystem.SetView(view, projection, 0.1f, 1000.0f, 1920, 1080);
		Console.WriteLine("View parameters set");

		// Begin frame and add lights
		lightingSystem.BeginFrame();

		lightingSystem.AddDirectionalLight(.(0.5f, -1.0f, 0.3f), .(1, 0.95f, 0.9f), 1.5f);
		lightingSystem.AddPointLight(.(5, 2, 3), 10.0f, .(1, 0.5f, 0), 2.0f);
		lightingSystem.AddPointLight(.(-5, 2, -3), 15.0f, .(0, 0.5f, 1), 1.5f);
		lightingSystem.AddSpotLight(.(0, 8, 0), .(0, -1, 0), 20.0f, 30, 45, .(1, 1, 1), 3.0f);

		Console.WriteLine("Added 4 lights (1 dir, 2 point, 1 spot)");

		// Set ambient
		lightingSystem.SetAmbient(.(0.05f, 0.05f, 0.1f), 1.0f);
		lightingSystem.SetSun(.(0.5f, -1.0f, 0.3f), .(1, 0.95f, 0.9f), 2.0f);

		// Update (computes clusters, uploads data)
		lightingSystem.Update();
		Console.WriteLine("Lighting system updated");

		// Get stats
		let stats = scope String();
		lightingSystem.GetStats(stats);
		Console.WriteLine("\n{}", stats);

		Console.WriteLine("Lighting System tests passed!");
	}

	/// Tests light-cluster assignment.
	public void TestLightClusterAssignment()
	{
		Console.WriteLine("\n=== Testing Light-Cluster Assignment ===\n");

		let lightingSystem = scope LightingSystem(8, 6, 16);

		switch (lightingSystem.Initialize(mDevice))
		{
		case .Ok:
		case .Err:
			Console.WriteLine("ERROR: Failed to initialize");
			return;
		}

		// Set up view
		let view = Matrix.CreateLookAt(.(0, 0, 20), .Zero, .UnitY);
		let projection = Matrix.CreatePerspectiveFieldOfView(
			Math.PI_f / 4, 16.0f / 9.0f, 1.0f, 100.0f);

		lightingSystem.SetView(view, projection, 1.0f, 100.0f, 1280, 720);

		lightingSystem.BeginFrame();

		// Add many point lights in a grid
		for (int x = -2; x <= 2; x++)
		{
			for (int z = -2; z <= 2; z++)
			{
				lightingSystem.AddPointLight(
					.((float)x * 5, 0, (float)z * 5),
					8.0f,
					.(1, 1, 1),
					1.0f
				);
			}
		}

		Console.WriteLine("Added {} point lights in a grid", 25);

		lightingSystem.Update();

		let stats = scope String();
		lightingSystem.GetStats(stats);
		Console.WriteLine("\n{}", stats);

		Console.WriteLine("Light-Cluster Assignment tests passed!");
	}

	/// Runs all lighting system tests.
	public void RunLightingSystemTests()
	{
		Console.WriteLine("\n");
		Console.WriteLine("=====================================");
		Console.WriteLine("   PHASE 4: LIGHTING SYSTEM TESTS   ");
		Console.WriteLine("=====================================");

		TestClusterGrid();
		TestLightBuffer();
		TestLightingSystemFacade();
		TestLightClusterAssignment();

		Console.WriteLine("\n=====================================");
		Console.WriteLine("   ALL LIGHTING TESTS COMPLETED!    ");
		Console.WriteLine("=====================================\n");
	}
}
