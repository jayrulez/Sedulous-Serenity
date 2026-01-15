namespace Sedulous.RendererNG;

using System;
using Sedulous.RHI;

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

	/// Uploads a static mesh to the GPU.
	/// Returns a handle to the GPU mesh.
	public Result<MeshHandle> Upload(StaticMesh mesh)
	{
		if (mesh.VertexData == null || mesh.IndexData == null)
			return .Err;

		// Allocate GPU mesh slot
		let handleResult = mMeshPool.Allocate();
		if (handleResult case .Err)
			return .Err;

		let handle = handleResult.Value;
		let gpuMesh = mMeshPool.Get(handle);

		// Create vertex buffer with Upload access for direct writes
		var vbDesc = BufferDescriptor(mesh.VertexDataSize, .Vertex, .Upload);
		vbDesc.Label = "MeshVertexBuffer";

		switch (mDevice.CreateBuffer(&vbDesc))
		{
		case .Ok(let buffer):
			gpuMesh.VertexBuffer = buffer;
			// Copy data to buffer
			let mappedPtr = buffer.Map();
			if (mappedPtr != null)
			{
				Internal.MemCpy(mappedPtr, mesh.VertexData.Ptr, mesh.VertexDataSize);
				buffer.Unmap();
			}
		case .Err:
			mMeshPool.Release(handle);
			return .Err;
		}

		// Create index buffer with Upload access for direct writes
		var ibDesc = BufferDescriptor(mesh.IndexDataSize, .Index, .Upload);
		ibDesc.Label = "MeshIndexBuffer";

		switch (mDevice.CreateBuffer(&ibDesc))
		{
		case .Ok(let buffer):
			gpuMesh.IndexBuffer = buffer;
			// Copy data to buffer
			let mappedPtr = buffer.Map();
			if (mappedPtr != null)
			{
				Internal.MemCpy(mappedPtr, mesh.IndexData.Ptr, mesh.IndexDataSize);
				buffer.Unmap();
			}
		case .Err:
			mMeshPool.Release(handle);
			return .Err;
		}

		// Copy mesh properties
		gpuMesh.VertexLayout = mesh.VertexLayout;
		gpuMesh.VertexCount = mesh.VertexCount;
		gpuMesh.IndexCount = mesh.IndexCount;
		gpuMesh.Use32BitIndices = mesh.Use32BitIndices;
		gpuMesh.Bounds = mesh.Bounds;
		gpuMesh.IsSkinned = false;

		// Copy submeshes
		gpuMesh.Submeshes.Clear();
		for (let submesh in mesh.Submeshes)
			gpuMesh.Submeshes.Add(submesh);

		// If no submeshes defined, create one covering entire mesh
		if (gpuMesh.Submeshes.Count == 0)
			gpuMesh.Submeshes.Add(.(0, mesh.IndexCount, 0));

		return handle;
	}

	/// Uploads a skinned mesh to the GPU.
	public Result<MeshHandle> Upload(SkinnedMesh mesh)
	{
		// Use base upload logic
		let handleResult = Upload((StaticMesh)mesh);
		if (handleResult case .Err)
			return .Err;

		let handle = handleResult.Value;
		let gpuMesh = mMeshPool.Get(handle);

		// Set skinned mesh properties
		gpuMesh.IsSkinned = true;
		gpuMesh.BoneCount = mesh.Bones.Count;

		return handle;
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
}
