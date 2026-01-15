namespace RendererNGSandbox;

using System;
using Sedulous.RendererNG;
using Sedulous.RHI;
using Sedulous.Mathematics;

extension RendererNGSandboxApp
{
	/// Tests the mesh data structures.
	public void TestMeshData()
	{
		Console.WriteLine("\n=== Testing Mesh Data ===\n");

		// Test StaticMesh creation
		let mesh = new StaticMesh("TestMesh", .PositionNormalUV, 24, 36, false);
		Console.WriteLine("StaticMesh created:");
		Console.WriteLine("  Name: {}", mesh.Name);
		Console.WriteLine("  VertexLayout: {}", mesh.VertexLayout);
		Console.WriteLine("  VertexCount: {}", mesh.VertexCount);
		Console.WriteLine("  IndexCount: {}", mesh.IndexCount);
		Console.WriteLine("  VertexStride: {} bytes", mesh.VertexStride);
		Console.WriteLine("  VertexDataSize: {} bytes", mesh.VertexDataSize);
		Console.WriteLine("  IndexDataSize: {} bytes", mesh.IndexDataSize);

		// Test vertex access
		var vertices = mesh.GetVertices<VertexLayouts.VertexPNU>();
		Console.WriteLine("  Vertex span length: {}", vertices.Length);

		// Fill some test data
		vertices[0] = .() { Position = .(0, 0, 0), Normal = .(0, 1, 0), TexCoord = .(0, 0) };
		vertices[1] = .() { Position = .(1, 0, 0), Normal = .(0, 1, 0), TexCoord = .(1, 0) };
		vertices[2] = .() { Position = .(1, 0, 1), Normal = .(0, 1, 0), TexCoord = .(1, 1) };

		// Test bounds computation
		mesh.ComputeBounds();
		Console.WriteLine("  Bounds: {} - {}", mesh.Bounds.Min, mesh.Bounds.Max);

		// Test submeshes
		mesh.AddSubmesh(0, 6, 0);
		mesh.AddSubmesh(6, 12, 1);
		Console.WriteLine("  Submeshes: {}", mesh.Submeshes.Count);

		delete mesh;

		// Test SkinnedMesh
		let skinnedMesh = new SkinnedMesh("SkinnedTest", 100, 300, false);
		Console.WriteLine("\nSkinnedMesh created:");
		Console.WriteLine("  VertexLayout: {}", skinnedMesh.VertexLayout);
		Console.WriteLine("  VertexStride: {} bytes", skinnedMesh.VertexStride);

		// Add bones
		skinnedMesh.AddBone("Root", -1, .Identity);
		skinnedMesh.AddBone("Spine", 0, .Identity);
		skinnedMesh.AddBone("Head", 1, .Identity);
		Console.WriteLine("  Bones: {}", skinnedMesh.Bones.Count);
		Console.WriteLine("  Root bone index: {}", skinnedMesh.GetBoneIndex("Root"));
		Console.WriteLine("  Unknown bone: {}", skinnedMesh.GetBoneIndex("Unknown"));

		delete skinnedMesh;

		Console.WriteLine("\nMesh Data tests passed!");
	}

	/// Tests the mesh primitives.
	public void TestMeshPrimitives()
	{
		Console.WriteLine("\n=== Testing Mesh Primitives ===\n");

		// Test cube
		let cube = MeshPrimitives.CreateCube("TestCube");
		Console.WriteLine("Cube:");
		Console.WriteLine("  Vertices: {}", cube.VertexCount);
		Console.WriteLine("  Indices: {}", cube.IndexCount);
		Console.WriteLine("  Submeshes: {}", cube.Submeshes.Count);
		Console.WriteLine("  Bounds: {} - {}", cube.Bounds.Min, cube.Bounds.Max);
		delete cube;

		// Test plane
		let plane = MeshPrimitives.CreatePlane(2, 2, "TestPlane");
		Console.WriteLine("\nPlane (2x2):");
		Console.WriteLine("  Vertices: {}", plane.VertexCount);
		Console.WriteLine("  Indices: {}", plane.IndexCount);
		delete plane;

		// Test sphere
		let sphere = MeshPrimitives.CreateSphere(8, 8, 1.0f, "TestSphere");
		Console.WriteLine("\nSphere (8x8 segments):");
		Console.WriteLine("  Vertices: {}", sphere.VertexCount);
		Console.WriteLine("  Indices: {}", sphere.IndexCount);
		Console.WriteLine("  Bounds: {} - {}", sphere.Bounds.Min, sphere.Bounds.Max);
		delete sphere;

		// Test cylinder
		let cylinder = MeshPrimitives.CreateCylinder(12, 0.5f, 2.0f, "TestCylinder");
		Console.WriteLine("\nCylinder (12 segments):");
		Console.WriteLine("  Vertices: {}", cylinder.VertexCount);
		Console.WriteLine("  Indices: {}", cylinder.IndexCount);
		delete cylinder;

		Console.WriteLine("\nMesh Primitives tests passed!");
	}

	/// Tests the mesh pool and GPU upload.
	public void TestMeshPool()
	{
		Console.WriteLine("\n=== Testing Mesh Pool ===\n");

		let pool = scope MeshPool();
		pool.Initialize(mDevice);
		Console.WriteLine("MeshPool initialized");
		Console.WriteLine("  Total: {}", pool.TotalCount);
		Console.WriteLine("  Active: {}", pool.ActiveCount);

		// Allocate a mesh slot
		switch (pool.Allocate())
		{
		case .Ok(let handle):
			Console.WriteLine("\nAllocated mesh handle:");
			Console.WriteLine("  Index: {}, Gen: {}", handle.Index, handle.Generation);

			let gpuMesh = pool.Get(handle);
			Console.WriteLine("  GPUMesh valid: {}", gpuMesh != null);

			// Release it
			pool.Release(handle);
			Console.WriteLine("  Released handle");
			Console.WriteLine("  Active after release: {}", pool.ActiveCount);

			// Reallocate
			switch (pool.Allocate())
			{
			case .Ok(let handle2):
				Console.WriteLine("  Reallocated - Index: {}, Gen: {}", handle2.Index, handle2.Generation);
				Console.WriteLine("  Generation incremented: {}", handle2.Generation > handle.Generation);
			case .Err:
				Console.WriteLine("ERROR: Reallocation failed");
			}

		case .Err:
			Console.WriteLine("ERROR: Failed to allocate mesh");
		}

		Console.WriteLine("\nMesh Pool tests passed!");
	}

	/// Tests mesh uploading.
	public void TestMeshUploader()
	{
		Console.WriteLine("\n=== Testing Mesh Uploader ===\n");

		let pool = scope MeshPool();
		pool.Initialize(mDevice);

		let uploader = scope MeshUploader();
		uploader.Initialize(mDevice, pool);
		Console.WriteLine("MeshUploader initialized");

		// Create and upload a cube
		let cube = MeshPrimitives.CreateCube("UploadCube");
		Console.WriteLine("\nUploading cube...");

		switch (uploader.Upload(cube))
		{
		case .Ok(let handle):
			Console.WriteLine("Upload successful!");
			Console.WriteLine("  Handle: Index={}, Gen={}", handle.Index, handle.Generation);

			let gpuMesh = pool.Get(handle);
			Console.WriteLine("  VertexBuffer valid: {}", gpuMesh.VertexBuffer != null);
			Console.WriteLine("  IndexBuffer valid: {}", gpuMesh.IndexBuffer != null);
			Console.WriteLine("  VertexCount: {}", gpuMesh.VertexCount);
			Console.WriteLine("  IndexCount: {}", gpuMesh.IndexCount);
			Console.WriteLine("  Submeshes: {}", gpuMesh.Submeshes.Count);
			Console.WriteLine("  IsValid: {}", gpuMesh.IsValid);

		case .Err:
			Console.WriteLine("ERROR: Failed to upload cube");
		}

		delete cube;

		Console.WriteLine("\nMesh Uploader tests passed!");
	}

	/// Tests the mesh instance data.
	public void TestMeshInstance()
	{
		Console.WriteLine("\n=== Testing Mesh Instance Data ===\n");

		// Test default instance
		var instance = MeshInstanceData();
		Console.WriteLine("Default MeshInstanceData:");
		Console.WriteLine("  Size: {} bytes", MeshInstanceData.Size);
		Console.WriteLine("  WorldMatrix identity: {}", instance.WorldMatrix == .Identity);
		Console.WriteLine("  CustomData: ({}, {}, {}, {})",
			instance.CustomData.X, instance.CustomData.Y, instance.CustomData.Z, instance.CustomData.W);

		// Test from transform
		let transformedInstance = MeshInstanceData.FromTransform(
			.(1, 2, 3),           // Position
			.Identity,            // Rotation
			.(2, 2, 2)            // Scale
		);
		Console.WriteLine("\nTransformed MeshInstanceData:");
		Console.WriteLine("  World[3][0-2]: ({}, {}, {})",
			transformedInstance.WorldMatrix.M41,
			transformedInstance.WorldMatrix.M42,
			transformedInstance.WorldMatrix.M43);

		Console.WriteLine("\nMesh Instance tests passed!");
	}

	/// Tests the mesh draw system batching.
	public void TestMeshDrawBatching()
	{
		Console.WriteLine("\n=== Testing Mesh Draw Batching ===\n");

		// Create test components
		let pool = scope MeshPool();
		pool.Initialize(mDevice);

		let transientPool = scope TransientBufferPool(mDevice);
		transientPool.BeginFrame(0);

		let pipelineFactory = scope PipelineFactory();

		let layoutCache = scope BindGroupLayoutCache();
		layoutCache.Initialize(mDevice);

		let drawSystem = scope MeshDrawSystem();
		drawSystem.Initialize(mDevice, pool, transientPool, pipelineFactory, layoutCache);

		Console.WriteLine("MeshDrawSystem initialized");

		// Begin frame
		drawSystem.BeginFrame();
		Console.WriteLine("Frame started");
		Console.WriteLine("  Instances: {}", drawSystem.InstanceCount);
		Console.WriteLine("  Batches: {}", drawSystem.BatchCount);

		// Create a dummy mesh handle
		let meshHandle = MeshHandle(0, 1);

		// Add some instances
		var instance1 = MeshInstanceData.FromTransform(.(0, 0, 0), .Identity, .One);
		var instance2 = MeshInstanceData.FromTransform(.(2, 0, 0), .Identity, .One);
		var instance3 = MeshInstanceData.FromTransform(.(4, 0, 0), .Identity, .One);

		drawSystem.AddInstance(meshHandle, null, instance1, 0);
		drawSystem.AddInstance(meshHandle, null, instance2, 0);
		drawSystem.AddInstance(meshHandle, null, instance3, 0);

		Console.WriteLine("\nAfter adding 3 instances:");
		Console.WriteLine("  Instances: {}", drawSystem.InstanceCount);

		// Build batches
		drawSystem.BuildBatches();
		Console.WriteLine("\nAfter building batches:");
		Console.WriteLine("  Batches: {}", drawSystem.BatchCount);

		Console.WriteLine("\nMesh Draw Batching tests passed!");
	}

	/// Runs all mesh system tests.
	public void RunMeshSystemTests()
	{
		Console.WriteLine("\n");
		Console.WriteLine("=====================================");
		Console.WriteLine("    PHASE 3: MESH SYSTEM TESTS      ");
		Console.WriteLine("=====================================");

		TestMeshData();
		TestMeshPrimitives();
		TestMeshPool();
		TestMeshUploader();
		TestMeshInstance();
		TestMeshDrawBatching();

		Console.WriteLine("\n=====================================");
		Console.WriteLine("    ALL MESH TESTS COMPLETED!       ");
		Console.WriteLine("=====================================\n");
	}
}
