namespace RendererNGSandbox;

using System;
using Sedulous.Mathematics;
using Sedulous.RendererNG;

extension RendererNGSandboxApp
{
	/// Tests for the visibility system (Phase 8).
	public void TestVisibilitySystem()
	{
		Console.WriteLine("\n=== Phase 8: Visibility System Tests ===\n");

		int passed = 0;
		int failed = 0;

		// Test 1: FrustumCuller creation from matrix
		{
			Console.Write("Test 1: FrustumCuller from view-projection matrix... ");
			let view = Matrix.CreateLookAt(Vector3(0, 0, 5), Vector3(0, 0, 0), Vector3(0, 1, 0));
			let proj = Matrix.CreatePerspectiveFieldOfView(Math.PI_f / 4.0f, 16.0f / 9.0f, 0.1f, 100.0f);
			let viewProj = view * proj;

			let culler = FrustumCuller(viewProj);

			// All planes should be normalized (normal length ~1)
			bool planesValid = true;
			for (int i = 0; i < 6; i++)
			{
				let normalLen = culler.Planes[i].Normal.Length();
				if (normalLen < 0.99f || normalLen > 1.01f)
					planesValid = false;
			}

			if (planesValid)
			{
				Console.WriteLine("PASSED");
				passed++;
			}
			else
			{
				Console.WriteLine("FAILED - planes not normalized");
				failed++;
			}
		}

		// Test 2: AABB inside frustum
		{
			Console.Write("Test 2: AABB inside frustum... ");
			let view = Matrix.CreateLookAt(Vector3(0, 0, 10), Vector3(0, 0, 0), Vector3(0, 1, 0));
			let proj = Matrix.CreatePerspectiveFieldOfView(Math.PI_f / 4.0f, 16.0f / 9.0f, 0.1f, 100.0f);
			let viewProj = view * proj;
			let culler = FrustumCuller(viewProj);

			// Box at origin, should be visible from camera at z=10
			let bounds = BoundingBox(.(-1, -1, -1), .(1, 1, 1));
			let result = culler.TestAABB(bounds);

			if (result != .Outside)
			{
				Console.WriteLine("PASSED");
				passed++;
			}
			else
			{
				Console.WriteLine("FAILED - box should be visible");
				failed++;
			}
		}

		// Test 3: AABB outside frustum (beyond far plane)
		{
			Console.Write("Test 3: AABB beyond far plane... ");
			let view = Matrix.CreateLookAt(Vector3(0, 0, 10), Vector3(0, 0, 0), Vector3(0, 1, 0));
			let proj = Matrix.CreatePerspectiveFieldOfView(Math.PI_f / 4.0f, 16.0f / 9.0f, 0.1f, 50.0f);  // Far = 50
			let viewProj = view * proj;
			let culler = FrustumCuller(viewProj);

			// Box beyond far plane (camera at z=10, far=50, so beyond z=-40)
			let bounds = BoundingBox(.(-1, -1, -100), .(1, 1, -95));
			let result = culler.TestAABB(bounds);

			if (result == .Outside)
			{
				Console.WriteLine("PASSED");
				passed++;
			}
			else
			{
				Console.WriteLine("FAILED - box should be culled (beyond far plane)");
				failed++;
			}
		}

		// Test 4: AABB outside frustum (far away to the side)
		{
			Console.Write("Test 4: AABB far to the side... ");
			let view = Matrix.CreateLookAt(Vector3(0, 0, 10), Vector3(0, 0, 0), Vector3(0, 1, 0));
			let proj = Matrix.CreatePerspectiveFieldOfView(Math.PI_f / 4.0f, 16.0f / 9.0f, 0.1f, 100.0f);
			let viewProj = view * proj;
			let culler = FrustumCuller(viewProj);

			// Box way off to the side
			let bounds = BoundingBox(.(100, -1, -1), .(102, 1, 1));
			let result = culler.TestAABB(bounds);

			if (result == .Outside)
			{
				Console.WriteLine("PASSED");
				passed++;
			}
			else
			{
				Console.WriteLine("FAILED - box should be culled");
				failed++;
			}
		}

		// Test 5: Sphere inside frustum
		{
			Console.Write("Test 5: Sphere inside frustum... ");
			let view = Matrix.CreateLookAt(Vector3(0, 0, 10), Vector3(0, 0, 0), Vector3(0, 1, 0));
			let proj = Matrix.CreatePerspectiveFieldOfView(Math.PI_f / 4.0f, 16.0f / 9.0f, 0.1f, 100.0f);
			let viewProj = view * proj;
			let culler = FrustumCuller(viewProj);

			// Sphere at origin
			let visible = culler.IsVisibleSphere(Vector3(0, 0, 0), 1.0f);

			if (visible)
			{
				Console.WriteLine("PASSED");
				passed++;
			}
			else
			{
				Console.WriteLine("FAILED - sphere should be visible");
				failed++;
			}
		}

		// Test 6: Sphere outside frustum
		{
			Console.Write("Test 6: Sphere outside frustum... ");
			let view = Matrix.CreateLookAt(Vector3(0, 0, 10), Vector3(0, 0, 0), Vector3(0, 1, 0));
			let proj = Matrix.CreatePerspectiveFieldOfView(Math.PI_f / 4.0f, 16.0f / 9.0f, 0.1f, 100.0f);
			let viewProj = view * proj;
			let culler = FrustumCuller(viewProj);

			// Sphere behind camera
			let visible = culler.IsVisibleSphere(Vector3(0, 0, 20), 1.0f);

			if (!visible)
			{
				Console.WriteLine("PASSED");
				passed++;
			}
			else
			{
				Console.WriteLine("FAILED - sphere should be culled");
				failed++;
			}
		}

		// Test 7: Point inside frustum
		{
			Console.Write("Test 7: Point inside frustum... ");
			let view = Matrix.CreateLookAt(Vector3(0, 0, 10), Vector3(0, 0, 0), Vector3(0, 1, 0));
			let proj = Matrix.CreatePerspectiveFieldOfView(Math.PI_f / 4.0f, 16.0f / 9.0f, 0.1f, 100.0f);
			let viewProj = view * proj;
			let culler = FrustumCuller(viewProj);

			// Point at origin should be visible (camera at z=10 looking at origin)
			let insideVisible = culler.IsVisiblePoint(Vector3(0, 0, 0));
			// Point far outside should be culled
			let outsideCulled = !culler.IsVisiblePoint(Vector3(1000, 0, 0));

			if (insideVisible && outsideCulled)
			{
				Console.WriteLine("PASSED");
				passed++;
			}
			else
			{
				Console.WriteLine("FAILED - inside:{0} outsideCulled:{1}", insideVisible, outsideCulled);
				failed++;
			}
		}

		// Test 8: DrawCommand sort key generation (opaque)
		{
			Console.Write("Test 8: DrawCommand opaque sort key... ");
			let key1 = DrawCommand.MakeOpaqueKey(1, 2, 3, 0.1f); // Near
			let key2 = DrawCommand.MakeOpaqueKey(1, 2, 3, 0.9f); // Far

			// For opaque, near objects should sort first (lower key)
			if (key1 < key2)
			{
				Console.WriteLine("PASSED");
				passed++;
			}
			else
			{
				Console.WriteLine("FAILED - near should sort before far");
				failed++;
			}
		}

		// Test 9: DrawCommand sort key generation (transparent)
		{
			Console.Write("Test 9: DrawCommand transparent sort key... ");
			let key1 = DrawCommand.MakeTransparentKey(1, 2, 3, 0.1f); // Near
			let key2 = DrawCommand.MakeTransparentKey(1, 2, 3, 0.9f); // Far

			// For transparent, far objects should sort first (lower key)
			if (key1 > key2)
			{
				Console.WriteLine("PASSED");
				passed++;
			}
			else
			{
				Console.WriteLine("FAILED - far should sort before near");
				failed++;
			}
		}

		// Test 10: DrawBatcher basic operations
		{
			Console.Write("Test 10: DrawBatcher add commands... ");
			let batcher = scope DrawBatcher();

			batcher.AddOpaque(0, 0, 1, 1, 1, 0.5f);
			batcher.AddOpaque(1, 0, 1, 1, 2, 0.3f);
			batcher.AddTransparent(2, 0, 2, 1, 1, 0.7f);

			if (batcher.CommandCount == 3)
			{
				Console.WriteLine("PASSED");
				passed++;
			}
			else
			{
				Console.WriteLine("FAILED - expected 3 commands");
				failed++;
			}
		}

		// Test 11: DrawBatcher batch building
		{
			Console.Write("Test 11: DrawBatcher batch building... ");
			let batcher = scope DrawBatcher();

			// Add commands with same pipeline/material (should batch)
			batcher.AddOpaque(0, 0, 1, 1, 1, 0.5f);
			batcher.AddOpaque(1, 0, 1, 1, 2, 0.3f);
			batcher.AddOpaque(2, 0, 1, 1, 3, 0.4f);

			batcher.BuildBatches();

			// All same pipeline/material should form 1 batch
			if (batcher.OpaqueBatchCount >= 1)
			{
				Console.WriteLine("PASSED");
				passed++;
			}
			else
			{
				Console.WriteLine("FAILED - expected at least 1 batch");
				failed++;
			}
		}

		// Test 12: DrawBatcher layer separation
		{
			Console.Write("Test 12: DrawBatcher layer separation... ");
			let batcher = scope DrawBatcher();

			batcher.AddOpaque(0, 0, 1, 1, 1, 0.5f);
			batcher.AddTransparent(1, 0, 1, 1, 1, 0.5f);

			batcher.BuildBatches();

			// Should have separate opaque and transparent batches
			if (batcher.OpaqueBatchCount >= 1 && batcher.TransparentBatchCount >= 1)
			{
				Console.WriteLine("PASSED");
				passed++;
			}
			else
			{
				Console.WriteLine("FAILED - expected separate layers");
				failed++;
			}
		}

		// Test 13: VisibilitySystem basic operations
		{
			Console.Write("Test 13: VisibilitySystem basic operations... ");
			let visSystem = scope VisibilitySystem();

			visSystem.BeginFrame();

			// Create a test view
			let renderView = scope RenderView();
			renderView.Position = Vector3(0, 0, 10);
			renderView.ViewMatrix = Matrix.CreateLookAt(Vector3(0, 0, 10), Vector3(0, 0, 0), Vector3(0, 1, 0));
			let proj = Matrix.CreatePerspectiveFieldOfView(Math.PI_f / 4.0f, 16.0f / 9.0f, 0.1f, 100.0f);
			renderView.ProjectionMatrix = proj;
			renderView.ViewProjectionMatrix = renderView.ViewMatrix * proj;
			renderView.FrustumPlanes = FrustumCuller.ExtractPlanes(renderView.ViewProjectionMatrix);
			renderView.NearPlane = 0.1f;
			renderView.FarPlane = 100.0f;

			let viewIndex = visSystem.AddView(renderView);

			if (viewIndex == 0)
			{
				Console.WriteLine("PASSED");
				passed++;
			}
			else
			{
				Console.WriteLine("FAILED - expected view index 0");
				failed++;
			}
		}

		// Test 14: VisibilitySystem AABB visibility
		{
			Console.Write("Test 14: VisibilitySystem AABB visibility... ");
			let visSystem = scope VisibilitySystem();
			visSystem.BeginFrame();

			let renderView = scope RenderView();
			renderView.Position = Vector3(0, 0, 10);
			renderView.ViewMatrix = Matrix.CreateLookAt(Vector3(0, 0, 10), Vector3(0, 0, 0), Vector3(0, 1, 0));
			let proj = Matrix.CreatePerspectiveFieldOfView(Math.PI_f / 4.0f, 16.0f / 9.0f, 0.1f, 100.0f);
			renderView.ProjectionMatrix = proj;
			renderView.ViewProjectionMatrix = renderView.ViewMatrix * proj;
			renderView.FrustumPlanes = FrustumCuller.ExtractPlanes(renderView.ViewProjectionMatrix);
			renderView.NearPlane = 0.1f;
			renderView.FarPlane = 100.0f;

			visSystem.AddView(renderView);

			// Test visible box at origin (should be visible)
			let visibleResult = visSystem.TestAABB(BoundingBox(.(-1, -1, -1), .(1, 1, 1)));
			// Test box far to the side (should be culled)
			let invisibleResult = visSystem.TestAABB(BoundingBox(.(100, -1, -1), .(102, 1, 1)));

			if (visibleResult.IsVisible && !invisibleResult.IsVisible)
			{
				Console.WriteLine("PASSED");
				passed++;
			}
			else
			{
				Console.WriteLine("FAILED - visible:{0} culled:{1}", visibleResult.IsVisible, !invisibleResult.IsVisible);
				failed++;
			}
		}

		// Test 15: VisibilitySystem statistics
		{
			Console.Write("Test 15: VisibilitySystem statistics... ");
			let visSystem = scope VisibilitySystem();
			visSystem.BeginFrame();

			let renderView = scope RenderView();
			renderView.Position = Vector3(0, 0, 10);
			renderView.ViewMatrix = Matrix.CreateLookAt(Vector3(0, 0, 10), Vector3(0, 0, 0), Vector3(0, 1, 0));
			let proj = Matrix.CreatePerspectiveFieldOfView(Math.PI_f / 4.0f, 16.0f / 9.0f, 0.1f, 100.0f);
			renderView.ProjectionMatrix = proj;
			renderView.ViewProjectionMatrix = renderView.ViewMatrix * proj;
			renderView.FrustumPlanes = FrustumCuller.ExtractPlanes(renderView.ViewProjectionMatrix);

			visSystem.AddView(renderView);

			// Test a few objects
			visSystem.TestAABB(BoundingBox(.(-1, -1, -1), .(1, 1, 1))); // Visible
			visSystem.TestAABB(BoundingBox(.(100, -1, -1), .(102, 1, 1))); // Culled
			visSystem.TestAABB(BoundingBox(.(-2, -2, -2), .(2, 2, 2))); // Visible

			if (visSystem.ObjectsTested == 3 && visSystem.ObjectsVisible == 2 && visSystem.ObjectsCulled == 1)
			{
				Console.WriteLine("PASSED");
				passed++;
			}
			else
			{
				Console.WriteLine("FAILED - statistics mismatch (tested:{0} visible:{1} culled:{2})",
					visSystem.ObjectsTested, visSystem.ObjectsVisible, visSystem.ObjectsCulled);
				failed++;
			}
		}

		// Test 16: BatchCuller batch operations
		{
			Console.Write("Test 16: BatchCuller batch operations... ");
			let view = Matrix.CreateLookAt(Vector3(0, 0, 10), Vector3(0, 0, 0), Vector3(0, 1, 0));
			let proj = Matrix.CreatePerspectiveFieldOfView(Math.PI_f / 4.0f, 16.0f / 9.0f, 0.1f, 100.0f);
			let viewProj = view * proj;

			let batchCuller = scope BatchCuller(viewProj);

			// Mix of visible and culled boxes
			BoundingBox[4] boxes = .(
				BoundingBox(.(-1, -1, -1), .(1, 1, 1)),      // Visible (at origin)
				BoundingBox(.(500, -1, -1), .(502, 1, 1)),   // Culled (far right)
				BoundingBox(.(-2, -2, 2), .(2, 2, 4)),       // Visible (in front of camera)
				BoundingBox(.(-1, 500, -1), .(1, 502, 1))    // Culled (far up)
			);

			batchCuller.CullAABBs(boxes);

			// 2 should be visible, 2 should be culled
			if (batchCuller.VisibleCount == 2)
			{
				Console.WriteLine("PASSED");
				passed++;
			}
			else
			{
				Console.WriteLine("FAILED - expected 2 visible, got {0}", batchCuller.VisibleCount);
				failed++;
			}
		}

		// Test 17: VisibilitySystem multi-view
		{
			Console.Write("Test 17: VisibilitySystem multi-view... ");
			let visSystem = scope VisibilitySystem();
			visSystem.BeginFrame();

			// Add two views looking from different directions
			let view1 = scope RenderView();
			view1.Position = Vector3(0, 0, 10);
			view1.ViewMatrix = Matrix.CreateLookAt(Vector3(0, 0, 10), Vector3(0, 0, 0), Vector3(0, 1, 0));
			let proj1 = Matrix.CreatePerspectiveFieldOfView(Math.PI_f / 4.0f, 16.0f / 9.0f, 0.1f, 100.0f);
			view1.ViewProjectionMatrix = view1.ViewMatrix * proj1;
			view1.FrustumPlanes = FrustumCuller.ExtractPlanes(view1.ViewProjectionMatrix);

			let view2 = scope RenderView();
			view2.Position = Vector3(10, 0, 0);
			view2.ViewMatrix = Matrix.CreateLookAt(Vector3(10, 0, 0), Vector3(0, 0, 0), Vector3(0, 1, 0));
			let proj2 = Matrix.CreatePerspectiveFieldOfView(Math.PI_f / 4.0f, 16.0f / 9.0f, 0.1f, 100.0f);
			view2.ViewProjectionMatrix = view2.ViewMatrix * proj2;
			view2.FrustumPlanes = FrustumCuller.ExtractPlanes(view2.ViewProjectionMatrix);

			let idx1 = visSystem.AddView(view1);
			let idx2 = visSystem.AddView(view2);

			// Box at origin should be visible from both views
			let result = visSystem.TestAABB(BoundingBox(.(-1, -1, -1), .(1, 1, 1)));

			// Check both view bits are set
			bool view0Visible = (result.ViewMask & 1) != 0;
			bool view1Visible = (result.ViewMask & 2) != 0;

			if (idx1 == 0 && idx2 == 1 && view0Visible && view1Visible)
			{
				Console.WriteLine("PASSED");
				passed++;
			}
			else
			{
				Console.WriteLine("FAILED - multi-view visibility incorrect");
				failed++;
			}
		}

		// Test 18: VisibilitySystem depth computation
		{
			Console.Write("Test 18: VisibilitySystem depth computation... ");
			let visSystem = scope VisibilitySystem();
			visSystem.BeginFrame();

			let renderView = scope RenderView();
			renderView.Position = Vector3(0, 0, 10);
			renderView.ViewMatrix = Matrix.CreateLookAt(Vector3(0, 0, 10), Vector3(0, 0, 0), Vector3(0, 1, 0));
			renderView.NearPlane = 0.1f;
			renderView.FarPlane = 100.0f;
			let proj = Matrix.CreatePerspectiveFieldOfView(Math.PI_f / 4.0f, 16.0f / 9.0f, 0.1f, 100.0f);
			renderView.ViewProjectionMatrix = renderView.ViewMatrix * proj;
			renderView.FrustumPlanes = FrustumCuller.ExtractPlanes(renderView.ViewProjectionMatrix);

			visSystem.AddView(renderView);

			// Near point should have lower depth than far point
			let nearDepth = visSystem.ComputeDepth(0, Vector3(0, 0, 5));  // 5 units from camera
			let farDepth = visSystem.ComputeDepth(0, Vector3(0, 0, -50)); // 60 units from camera

			if (nearDepth < farDepth && nearDepth >= 0.0f && farDepth <= 1.0f)
			{
				Console.WriteLine("PASSED");
				passed++;
			}
			else
			{
				Console.WriteLine("FAILED - depth ordering incorrect (near:{0} far:{1})", nearDepth, farDepth);
				failed++;
			}
		}

		Console.WriteLine("\n=== Visibility System Tests Complete ===");
		Console.WriteLine("Passed: {0}/{1}", passed, passed + failed);

		if (failed > 0)
			Console.WriteLine("WARNING: {0} test(s) failed!", failed);
	}
}
