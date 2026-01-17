namespace Sedulous.RendererNG;

using System;
using Sedulous.RHI;
using Sedulous.Materials;

/// Uploads CPU mesh data to GPU buffers.
class MeshUploader
{
	private IDevice mDevice;
	private MeshPool mMeshPool;

	/// Initializes the mesh uploader.
	public void Initialize(IDevice device, MeshPool meshPool)
	{
		mDevice = device;
		mMeshPool = meshPool;
	}

	/// Updates vertex data for an existing GPU mesh.
	public Result<void> UpdateVertices(MeshHandle handle, Span<uint8> vertexData, uint32 offset = 0)
	{
		let gpuMesh = mMeshPool.Get(handle);
		if (gpuMesh == null || gpuMesh.VertexBuffer == null)
			return .Err;

		let mappedPtr = gpuMesh.VertexBuffer.Map();
		if (mappedPtr == null)
			return .Err;

		Internal.MemCpy((uint8*)mappedPtr + offset, vertexData.Ptr, vertexData.Length);
		gpuMesh.VertexBuffer.Unmap();
		return .Ok;
	}

	/// Updates index data for an existing GPU mesh.
	public Result<void> UpdateIndices(MeshHandle handle, Span<uint8> indexData, uint32 offset = 0)
	{
		let gpuMesh = mMeshPool.Get(handle);
		if (gpuMesh == null || gpuMesh.IndexBuffer == null)
			return .Err;

		let mappedPtr = gpuMesh.IndexBuffer.Map();
		if (mappedPtr == null)
			return .Err;

		Internal.MemCpy((uint8*)mappedPtr + offset, indexData.Ptr, indexData.Length);
		gpuMesh.IndexBuffer.Unmap();
		return .Ok;
	}

	/// Uploads a Sedulous.Geometry.StaticMesh to the GPU.
	/// Returns a handle to the GPU mesh.
	public Result<MeshHandle> Upload(Sedulous.Geometry.StaticMesh mesh)
	{
		if (mesh.Vertices == null || mesh.Indices == null)
			return .Err;

		let vertexDataSize = (uint32)mesh.Vertices.GetDataSize();
		let indexDataSize = (uint32)mesh.Indices.GetDataSize();

		if (vertexDataSize == 0 || indexDataSize == 0)
			return .Err;

		// Allocate GPU mesh slot
		let handleResult = mMeshPool.Allocate();
		if (handleResult case .Err)
			return .Err;

		let handle = handleResult.Value;
		let gpuMesh = mMeshPool.Get(handle);

		// Create vertex buffer
		var vbDesc = BufferDescriptor(vertexDataSize, .Vertex, .Upload);
		vbDesc.Label = "GeometryMeshVertexBuffer";

		switch (mDevice.CreateBuffer(&vbDesc))
		{
		case .Ok(let buffer):
			gpuMesh.VertexBuffer = buffer;
			let mappedPtr = buffer.Map();
			if (mappedPtr != null)
			{
				Internal.MemCpy(mappedPtr, mesh.Vertices.GetRawData(), vertexDataSize);
				buffer.Unmap();
			}
		case .Err:
			mMeshPool.Release(handle);
			return .Err;
		}

		// Create index buffer
		var ibDesc = BufferDescriptor(indexDataSize, .Index, .Upload);
		ibDesc.Label = "GeometryMeshIndexBuffer";

		switch (mDevice.CreateBuffer(&ibDesc))
		{
		case .Ok(let buffer):
			gpuMesh.IndexBuffer = buffer;
			let mappedPtr = buffer.Map();
			if (mappedPtr != null)
			{
				Internal.MemCpy(mappedPtr, mesh.Indices.GetRawData(), indexDataSize);
				buffer.Unmap();
			}
		case .Err:
			mMeshPool.Release(handle);
			return .Err;
		}

		// Set mesh properties
		gpuMesh.VertexLayout = .Mesh;
		gpuMesh.VertexCount = (uint32)mesh.Vertices.VertexCount;
		gpuMesh.IndexCount = (uint32)mesh.Indices.IndexCount;
		gpuMesh.Use32BitIndices = mesh.Indices.Format == .UInt32;
		gpuMesh.Bounds = mesh.GetBounds();
		gpuMesh.IsSkinned = false;

		// Convert submeshes
		gpuMesh.Submeshes.Clear();
		for (let sub in mesh.SubMeshes)
		{
			gpuMesh.Submeshes.Add(Submesh((uint32)sub.startIndex, (uint32)sub.indexCount, (uint32)sub.materialIndex));
		}

		// If no submeshes defined, create one covering entire mesh
		if (gpuMesh.Submeshes.Count == 0)
			gpuMesh.Submeshes.Add(.(0, (uint32)mesh.Indices.IndexCount, 0));

		return handle;
	}

	/// Uploads a Sedulous.Geometry.SkinnedMesh to the GPU.
	/// Returns a handle to the GPU mesh.
	public Result<MeshHandle> Upload(Sedulous.Geometry.SkinnedMesh mesh)
	{
		if (mesh.Vertices == null || mesh.Indices == null)
			return .Err;

		let vertexDataSize = (uint32)(mesh.VertexCount * mesh.VertexSize);
		let indexDataSize = (uint32)mesh.Indices.GetDataSize();

		if (vertexDataSize == 0 || indexDataSize == 0)
			return .Err;

		// Allocate GPU mesh slot
		let handleResult = mMeshPool.Allocate();
		if (handleResult case .Err)
			return .Err;

		let handle = handleResult.Value;
		let gpuMesh = mMeshPool.Get(handle);

		// Create vertex buffer
		var vbDesc = BufferDescriptor(vertexDataSize, .Vertex, .Upload);
		vbDesc.Label = "SkinnedMeshVertexBuffer";

		switch (mDevice.CreateBuffer(&vbDesc))
		{
		case .Ok(let buffer):
			gpuMesh.VertexBuffer = buffer;
			let mappedPtr = buffer.Map();
			if (mappedPtr != null)
			{
				Internal.MemCpy(mappedPtr, mesh.GetVertexData(), vertexDataSize);
				buffer.Unmap();
			}
		case .Err:
			mMeshPool.Release(handle);
			return .Err;
		}

		// Create index buffer
		var ibDesc = BufferDescriptor(indexDataSize, .Index, .Upload);
		ibDesc.Label = "SkinnedMeshIndexBuffer";

		switch (mDevice.CreateBuffer(&ibDesc))
		{
		case .Ok(let buffer):
			gpuMesh.IndexBuffer = buffer;
			let mappedPtr = buffer.Map();
			if (mappedPtr != null)
			{
				Internal.MemCpy(mappedPtr, mesh.Indices.GetRawData(), indexDataSize);
				buffer.Unmap();
			}
		case .Err:
			mMeshPool.Release(handle);
			return .Err;
		}

		// Set mesh properties
		gpuMesh.VertexLayout = .SkinnedMesh;
		gpuMesh.VertexCount = (uint32)mesh.VertexCount;
		gpuMesh.IndexCount = (uint32)mesh.Indices.IndexCount;
		gpuMesh.Use32BitIndices = mesh.Indices.Format == .UInt32;
		gpuMesh.Bounds = mesh.Bounds;
		gpuMesh.IsSkinned = true;
		gpuMesh.BoneCount = 0; // SkinnedMesh doesn't have bone hierarchy, just per-vertex bone data

		// Convert submeshes
		gpuMesh.Submeshes.Clear();
		for (let sub in mesh.SubMeshes)
		{
			gpuMesh.Submeshes.Add(Submesh((uint32)sub.startIndex, (uint32)sub.indexCount, (uint32)sub.materialIndex));
		}

		// If no submeshes defined, create one covering entire mesh
		if (gpuMesh.Submeshes.Count == 0)
			gpuMesh.Submeshes.Add(.(0, (uint32)mesh.Indices.IndexCount, 0));

		return handle;
	}
}
