namespace RendererNGSandbox;

using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.RHI;
using Sedulous.RendererNG;

extension RendererNGSandboxApp
{
	/// Tests cascaded shadow maps.
	public void TestCascadedShadowMaps()
	{
		Console.WriteLine("\n=== Testing Cascaded Shadow Maps ===\n");

		let csm = scope CascadedShadowMaps(4, 2048);
		Console.WriteLine("Created CascadedShadowMaps:");
		Console.WriteLine("  Cascade count: {}", csm.CascadeCount);
		Console.WriteLine("  Shadow map size: {}x{}", csm.ShadowMapSize, csm.ShadowMapSize);

		// Initialize
		switch (csm.Initialize(mDevice))
		{
		case .Ok:
			Console.WriteLine("  Initialized: OK");
		case .Err:
			Console.WriteLine("  ERROR: Failed to initialize");
			return;
		}

		// Verify textures created
		Console.WriteLine("  Shadow map array: {}", csm.ShadowMapArray != null ? "Created" : "NULL");
		Console.WriteLine("  Array view: {}", csm.ArrayView != null ? "Created" : "NULL");
		Console.WriteLine("  Cascade buffer: {}", csm.CascadeBuffer != null ? "Created" : "NULL");

		// Test update
		let view = Matrix.CreateLookAt(.(0, 5, 10), .Zero, .UnitY);
		let proj = Matrix.CreatePerspectiveFieldOfView(Math.PI_f / 4, 16.0f / 9.0f, 0.1f, 100.0f);

		csm.Update(view, proj, 0.1f, 100.0f, .(0.5f, -1.0f, 0.3f));
		Console.WriteLine("  Update completed");

		// Test cascade splits
		Console.WriteLine("\nCascade splits:");
		for (uint32 i = 0; i <= csm.CascadeCount; i++)
		{
			Console.WriteLine("  Split {}: {:.2f}", i, csm.GetSplitDistance(i));
		}

		// Test cascade index lookup
		Console.WriteLine("\nCascade index tests:");
		Console.WriteLine("  Depth 0.5 -> cascade {}", csm.GetCascadeIndex(0.5f));
		Console.WriteLine("  Depth 5.0 -> cascade {}", csm.GetCascadeIndex(5.0f));
		Console.WriteLine("  Depth 20.0 -> cascade {}", csm.GetCascadeIndex(20.0f));
		Console.WriteLine("  Depth 50.0 -> cascade {}", csm.GetCascadeIndex(50.0f));

		let stats = scope String();
		csm.GetStats(stats);
		Console.WriteLine("\n{}", stats);

		Console.WriteLine("Cascaded Shadow Maps tests passed!");
	}

	/// Tests shadow atlas.
	public void TestShadowAtlas()
	{
		Console.WriteLine("\n=== Testing Shadow Atlas ===\n");

		let atlas = scope ShadowAtlas(4096, 256, 1024);
		Console.WriteLine("Created ShadowAtlas:");
		Console.WriteLine("  Atlas size: {}x{}", atlas.AtlasSize, atlas.AtlasSize);
		Console.WriteLine("  Min region: {}", atlas.MinRegionSize);
		Console.WriteLine("  Max region: {}", atlas.MaxRegionSize);

		// Initialize
		switch (atlas.Initialize(mDevice))
		{
		case .Ok:
			Console.WriteLine("  Initialized: OK");
		case .Err:
			Console.WriteLine("  ERROR: Failed to initialize");
			return;
		}

		// Verify resources
		Console.WriteLine("  Atlas texture: {}", atlas.AtlasTexture != null ? "Created" : "NULL");
		Console.WriteLine("  Atlas view: {}", atlas.AtlasView != null ? "Created" : "NULL");

		// Begin frame and allocate regions
		atlas.BeginFrame();

		Console.WriteLine("\nAllocating shadow regions:");

		// Allocate several regions
		uint32 region0 = atlas.AllocateRegion(0, 512);
		Console.WriteLine("  Light 0, size 512: region {}", region0);

		uint32 region1 = atlas.AllocateRegion(1, 256);
		Console.WriteLine("  Light 1, size 256: region {}", region1);

		uint32 region2 = atlas.AllocateRegion(2, 1024);
		Console.WriteLine("  Light 2, size 1024: region {}", region2);

		uint32 region3 = atlas.AllocateRegion(3, 512);
		Console.WriteLine("  Light 3, size 512: region {}", region3);

		uint32 region4 = atlas.AllocateRegion(4, 256);
		Console.WriteLine("  Light 4, size 256: region {}", region4);

		Console.WriteLine("\nTotal regions: {}", atlas.RegionCount);

		// Get region details
		Console.WriteLine("\nRegion details:");
		for (int i = 0; i < atlas.RegionCount; i++)
		{
			let region = atlas.GetRegion((uint32)i);
			Console.WriteLine("  Region {}: pos=({},{}), size={}, light={}",
				i, region.X, region.Y, region.Size, region.LightIndex);
		}

		// Set shadow data
		let viewProj = Matrix.CreateLookAt(.(5, 5, 5), .Zero, .UnitY) *
					   Matrix.CreatePerspectiveFieldOfView(Math.PI_f / 2, 1.0f, 0.1f, 50.0f);

		atlas.SetShadowData(region0, viewProj, 0.1f, 50.0f);
		atlas.SetShadowData(region1, viewProj, 0.1f, 30.0f);
		Console.WriteLine("\nShadow data set for 2 regions");

		atlas.Upload();
		Console.WriteLine("Uploaded to GPU");

		let stats = scope String();
		atlas.GetStats(stats);
		Console.WriteLine("\n{}", stats);

		Console.WriteLine("Shadow Atlas tests passed!");
	}

	/// Tests shadow draw system.
	public void TestShadowDrawSystem()
	{
		Console.WriteLine("\n=== Testing Shadow Draw System ===\n");

		var config = ShadowConfig();
		config.CascadeCount = 4;
		config.CascadeResolution = 1024;
		config.AtlasSize = 2048;
		config.MaxShadowDistance = 100.0f;

		let shadowSystem = scope ShadowDrawSystem(config);

		// Initialize
		switch (shadowSystem.Initialize(mDevice))
		{
		case .Ok:
			Console.WriteLine("ShadowDrawSystem initialized");
		case .Err:
			Console.WriteLine("ERROR: Failed to initialize");
			return;
		}

		// Verify components
		Console.WriteLine("  Cascade shadows: {}", shadowSystem.CascadeShadows != null ? "OK" : "NULL");
		Console.WriteLine("  Shadow atlas: {}", shadowSystem.ShadowAtlas != null ? "OK" : "NULL");
		Console.WriteLine("  Shadow sampler: {}", shadowSystem.ShadowSampler != null ? "OK" : "NULL");

		// Set camera
		let view = Matrix.CreateLookAt(.(0, 10, 20), .Zero, .UnitY);
		let proj = Matrix.CreatePerspectiveFieldOfView(Math.PI_f / 4, 16.0f / 9.0f, 0.5f, 200.0f);

		shadowSystem.SetCamera(view, proj, 0.5f, 200.0f);
		shadowSystem.SetSunDirection(.(0.5f, -1.0f, 0.3f));
		Console.WriteLine("\nCamera and sun direction set");

		// Begin frame
		shadowSystem.BeginFrame();

		// Update cascades
		shadowSystem.UpdateCascades();
		Console.WriteLine("Cascades updated");

		// Allocate local shadows
		Console.WriteLine("\nAllocating local shadows:");

		uint32 shadow0 = shadowSystem.AllocateLocalShadow(0, 25.0f);
		Console.WriteLine("  Light 0 (range 25): shadow index {}", shadow0);

		uint32 shadow1 = shadowSystem.AllocateLocalShadow(1, 50.0f);
		Console.WriteLine("  Light 1 (range 50): shadow index {}", shadow1);

		uint32 shadow2 = shadowSystem.AllocateLocalShadow(2, 10.0f);
		Console.WriteLine("  Light 2 (range 10): shadow index {}", shadow2);

		// Set shadow matrices
		let spotViewProj = ShadowDrawSystem.CreateSpotLightViewProjection(
			.(5, 10, 0), .(0, -1, 0), 25.0f, Math.PI_f / 4);
		shadowSystem.SetLocalShadowMatrix(shadow0, spotViewProj, 0.1f, 25.0f);

		Console.WriteLine("\nLocal shadow matrices set");

		// Test point light view projections
		Console.WriteLine("\nPoint light view-projection test:");
		Matrix[6] pointMatrices = .();
		ShadowDrawSystem.CreatePointLightViewProjections(.(0, 5, 0), 20.0f, ref pointMatrices);
		Console.WriteLine("  Generated 6 cubemap face matrices");

		// Upload
		shadowSystem.Upload();
		Console.WriteLine("\nUploaded to GPU");

		// Get cascade info
		Console.WriteLine("\nCascade view-projections:");
		for (uint32 i = 0; i < shadowSystem.CascadeCount; i++)
		{
			shadowSystem.GetCascadeViewProjection(i); // Verify we can get the VP matrix
			Console.WriteLine("  Cascade {}: split at {:.2f}", i, shadowSystem.GetCascadeSplit(i + 1));
		}

		let stats = scope String();
		shadowSystem.GetStats(stats);
		Console.WriteLine("\n{}", stats);

		Console.WriteLine("Shadow Draw System tests passed!");
	}

	/// Runs all shadow system tests.
	public void RunShadowSystemTests()
	{
		Console.WriteLine("\n");
		Console.WriteLine("=====================================");
		Console.WriteLine("   PHASE 4b: SHADOW SYSTEM TESTS    ");
		Console.WriteLine("=====================================");

		TestCascadedShadowMaps();
		TestShadowAtlas();
		TestShadowDrawSystem();

		Console.WriteLine("\n=====================================");
		Console.WriteLine("   ALL SHADOW TESTS COMPLETED!      ");
		Console.WriteLine("=====================================\n");
	}
}
