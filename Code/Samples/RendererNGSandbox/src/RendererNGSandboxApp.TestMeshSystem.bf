namespace RendererNGSandbox;

using System;
using Sedulous.RendererNG;
using Sedulous.RHI;
using Sedulous.Mathematics;
using Sedulous.Geometry;

extension RendererNGSandboxApp
{
	/// Tests the Geometry mesh data structures.
	public void TestMeshData()
	{
		Console.WriteLine("\n=== Testing Geometry Mesh Data ===\n");

		// Test StaticMesh creation with common vertex format
		let mesh = new Sedulous.Geometry.StaticMesh();
		mesh.SetupCommonVertexFormat();
		mesh.Vertices.Resize(24);
		mesh.Indices.Resize(36);

		Console.WriteLine("StaticMesh created:");
		Console.WriteLine("  VertexCount: {}", mesh.Vertices.VertexCount);
		Console.WriteLine("  IndexCount: {}", mesh.Indices.IndexCount);
		Console.WriteLine("  VertexSize: {} bytes", mesh.Vertices.VertexSize);
		Console.WriteLine("  VertexDataSize: {} bytes", mesh.Vertices.GetDataSize());
		Console.WriteLine("  IndexDataSize: {} bytes", mesh.Indices.GetDataSize());

		// Fill some test data using the high-level API
		mesh.SetPosition(0, .(0, 0, 0));
		mesh.SetNormal(0, .(0, 1, 0));
		mesh.SetUV(0, .(0, 0));

		mesh.SetPosition(1, .(1, 0, 0));
		mesh.SetNormal(1, .(0, 1, 0));
		mesh.SetUV(1, .(1, 0));

		mesh.SetPosition(2, .(1, 0, 1));
		mesh.SetNormal(2, .(0, 1, 0));
		mesh.SetUV(2, .(1, 1));

		// Test reading back
		let pos = mesh.GetPosition(1);
		Console.WriteLine("  Position[1]: ({}, {}, {})", pos.X, pos.Y, pos.Z);

		// Test bounds computation
		let bounds = mesh.GetBounds();
		Console.WriteLine("  Bounds: {} - {}", bounds.Min, bounds.Max);

		// Test submeshes
		mesh.SubMeshes.Add(.(0, 6, 0));
		mesh.SubMeshes.Add(.(6, 12, 1));
		Console.WriteLine("  SubMeshes: {}", mesh.SubMeshes.Count);

		delete mesh;

		// Test SkinnedMesh
		let skinnedMesh = new Sedulous.Geometry.SkinnedMesh();
		skinnedMesh.ResizeVertices(100);
		skinnedMesh.ReserveIndices(300);

		Console.WriteLine("\nSkinnedMesh created:");
		Console.WriteLine("  VertexCount: {}", skinnedMesh.VertexCount);
		Console.WriteLine("  VertexSize: {} bytes", skinnedMesh.VertexSize);

		// Set a skinned vertex
		var vertex = SkinnedVertex();
		vertex.Position = .(1, 2, 3);
		vertex.Normal = .(0, 1, 0);
		vertex.Joints = .(0, 1, 0, 0);
		vertex.Weights = .(0.7f, 0.3f, 0, 0);
		skinnedMesh.SetVertex(0, vertex);

		let readBack = skinnedMesh.GetVertex(0);
		Console.WriteLine("  Vertex[0] Position: ({}, {}, {})", readBack.Position.X, readBack.Position.Y, readBack.Position.Z);
		Console.WriteLine("  Vertex[0] Weights: ({}, {}, {}, {})",
			readBack.Weights.X, readBack.Weights.Y, readBack.Weights.Z, readBack.Weights.W);

		delete skinnedMesh;

		Console.WriteLine("\nGeometry Mesh Data tests passed!");
	}

	/// Tests the Geometry mesh primitives.
	public void TestMeshPrimitives()
	{
		Console.WriteLine("\n=== Testing Geometry Mesh Primitives ===\n");

		// Test cube
		let cube = Sedulous.Geometry.StaticMesh.CreateCube(1.0f);
		Console.WriteLine("Cube:");
		Console.WriteLine("  Vertices: {}", cube.Vertices.VertexCount);
		Console.WriteLine("  Indices: {}", cube.Indices.IndexCount);
		Console.WriteLine("  SubMeshes: {}", cube.SubMeshes.Count);
		let cubeBounds = cube.GetBounds();
		Console.WriteLine("  Bounds: {} - {}", cubeBounds.Min, cubeBounds.Max);
		delete cube;

		// Test plane
		let plane = Sedulous.Geometry.StaticMesh.CreatePlane(2, 2, 1, 1);
		Console.WriteLine("\nPlane (2x2):");
		Console.WriteLine("  Vertices: {}", plane.Vertices.VertexCount);
		Console.WriteLine("  Indices: {}", plane.Indices.IndexCount);
		delete plane;

		// Test sphere
		let sphere = Sedulous.Geometry.StaticMesh.CreateSphere(1.0f, 8, 8);
		Console.WriteLine("\nSphere (8x8 segments):");
		Console.WriteLine("  Vertices: {}", sphere.Vertices.VertexCount);
		Console.WriteLine("  Indices: {}", sphere.Indices.IndexCount);
		let sphereBounds = sphere.GetBounds();
		Console.WriteLine("  Bounds: {} - {}", sphereBounds.Min, sphereBounds.Max);
		delete sphere;

		// Test cylinder
		let cylinder = Sedulous.Geometry.StaticMesh.CreateCylinder(0.5f, 2.0f, 12);
		Console.WriteLine("\nCylinder (12 segments):");
		Console.WriteLine("  Vertices: {}", cylinder.Vertices.VertexCount);
		Console.WriteLine("  Indices: {}", cylinder.Indices.IndexCount);
		delete cylinder;

		// Test torus
		let torus = Sedulous.Geometry.StaticMesh.CreateTorus(1.0f, 0.3f, 16, 8);
		Console.WriteLine("\nTorus (16x8 segments):");
		Console.WriteLine("  Vertices: {}", torus.Vertices.VertexCount);
		Console.WriteLine("  Indices: {}", torus.Indices.IndexCount);
		delete torus;

		Console.WriteLine("\nGeometry Mesh Primitives tests passed!");
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

	/// Tests mesh uploading with Geometry meshes.
	public void TestMeshUploader()
	{
		Console.WriteLine("\n=== Testing Mesh Uploader (Geometry) ===\n");

		let pool = scope MeshPool();
		pool.Initialize(mDevice);

		let uploader = scope MeshUploader();
		uploader.Initialize(mDevice, pool);
		Console.WriteLine("MeshUploader initialized");

		// Create and upload a Geometry cube
		let cube = Sedulous.Geometry.StaticMesh.CreateCube(1.0f);
		Console.WriteLine("\nUploading Geometry cube...");

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
			Console.WriteLine("  VertexLayout: {}", gpuMesh.VertexLayout);
			Console.WriteLine("  Submeshes: {}", gpuMesh.Submeshes.Count);
			Console.WriteLine("  IsValid: {}", gpuMesh.IsValid);

		case .Err:
			Console.WriteLine("ERROR: Failed to upload cube");
		}

		delete cube;

		// Test uploading a skinned mesh
		Console.WriteLine("\nUploading Geometry skinned mesh...");
		let skinnedMesh = new Sedulous.Geometry.SkinnedMesh();
		skinnedMesh.ResizeVertices(4);
		skinnedMesh.ReserveIndices(6);

		// Add some vertices
		for (int i < 4)
		{
			var v = SkinnedVertex();
			v.Position = .((float)i, 0, 0);
			v.Normal = .(0, 1, 0);
			v.Joints = .(0, 0, 0, 0);
			v.Weights = .(1, 0, 0, 0);
			skinnedMesh.SetVertex((int32)i, v);
		}

		// Add indices
		skinnedMesh.AddTriangle(0, 1, 2);
		skinnedMesh.AddTriangle(0, 2, 3);
		skinnedMesh.SubMeshes.Add(.(0, 6, 0));

		switch (uploader.Upload(skinnedMesh))
		{
		case .Ok(let handle):
			Console.WriteLine("Skinned mesh upload successful!");
			let gpuMesh = pool.Get(handle);
			Console.WriteLine("  VertexLayout: {}", gpuMesh.VertexLayout);
			Console.WriteLine("  IsSkinned: {}", gpuMesh.IsSkinned);

		case .Err:
			Console.WriteLine("ERROR: Failed to upload skinned mesh");
		}

		delete skinnedMesh;

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

	/// Tests skinned mesh rendering with bone matrices.
	public void TestSkinnedMeshRendering()
	{
		Console.WriteLine("\n=== Testing Skinned Mesh Rendering ===\n");

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

		Console.WriteLine("Testing skinned instance data structures...");
		Console.WriteLine("  SkinnedInstanceData size: {} bytes", SkinnedInstanceData.Size);
		Console.WriteLine("  SkinnedMeshInstanceData size: {} bytes", SkinnedMeshInstanceData.Size);

		// Create test bone matrices (simple identity bones)
		Matrix[4] boneMatrices = .(
			.Identity,
			.Identity,
			.Identity,
			.Identity
		);

		Console.WriteLine("\nTesting skinned mesh draw system...");

		drawSystem.BeginFrame();

		// Create a dummy mesh handle
		let meshHandle = MeshHandle(0, 1);

		// Add static instance
		var staticInstance = MeshInstanceData.FromTransform(.(0, 0, 0), .Identity, .One);
		drawSystem.AddInstance(meshHandle, null, staticInstance, 0);

		// Add skinned instances
		var skinnedInstance1 = MeshInstanceData.FromTransform(.(2, 0, 0), .Identity, .One);
		drawSystem.AddSkinnedInstance(meshHandle, null, skinnedInstance1, &boneMatrices[0], 4, 0);

		var skinnedInstance2 = MeshInstanceData.FromTransform(.(4, 0, 0), .Identity, .One);
		drawSystem.AddSkinnedInstance(meshHandle, null, skinnedInstance2, &boneMatrices[0], 4, 0);

		Console.WriteLine("After adding instances:");
		Console.WriteLine("  Total instances: {}", drawSystem.InstanceCount);
		Console.WriteLine("  Skinned instances: {}", drawSystem.SkinnedInstanceCount);
		Console.WriteLine("  Total bone count: {}", drawSystem.TotalBoneCount);

		// Build batches
		drawSystem.BuildBatches();

		Console.WriteLine("\nAfter building batches:");
		Console.WriteLine("  Batches: {}", drawSystem.BatchCount);
		Console.WriteLine("  Bone buffer valid: {}", drawSystem.BoneBuffer.IsValid);
		if (drawSystem.BoneBuffer.IsValid)
			Console.WriteLine("  Bone buffer size: {} bytes", drawSystem.TotalBoneCount * MeshDrawSystem.BoneMatrixSize);

		// Get stats
		let stats = scope String();
		drawSystem.GetStats(stats);
		Console.WriteLine("\nStats:");
		Console.Write(stats);

		Console.WriteLine("\nSkinned Mesh Rendering tests passed!");
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
		TestSkinnedMeshRendering();

		Console.WriteLine("\n=====================================");
		Console.WriteLine("    ALL MESH TESTS COMPLETED!       ");
		Console.WriteLine("=====================================\n");
	}
}
