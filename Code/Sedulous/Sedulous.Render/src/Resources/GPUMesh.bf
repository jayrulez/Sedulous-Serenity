namespace Sedulous.Render;

using System;
using Sedulous.RHI;
using Sedulous.Mathematics;

/// Handle to a GPU mesh.
public struct GPUMeshHandle : IHashable
{
	public uint32 Index;
	public uint32 Generation;

	public static Self Invalid = .() { Index = uint32.MaxValue, Generation = 0 };

	public bool IsValid => Index != uint32.MaxValue;

	public int GetHashCode() => (int)(Index ^ (Generation << 16));

	public static bool operator ==(Self lhs, Self rhs) => lhs.Index == rhs.Index && lhs.Generation == rhs.Generation;
	public static bool operator !=(Self lhs, Self rhs) => !(lhs == rhs);
}

/// Handle to a GPU texture.
public struct GPUTextureHandle : IHashable
{
	public uint32 Index;
	public uint32 Generation;

	public static Self Invalid = .() { Index = uint32.MaxValue, Generation = 0 };

	public bool IsValid => Index != uint32.MaxValue;

	public int GetHashCode() => (int)(Index ^ (Generation << 16));

	public static bool operator ==(Self lhs, Self rhs) => lhs.Index == rhs.Index && lhs.Generation == rhs.Generation;
	public static bool operator !=(Self lhs, Self rhs) => !(lhs == rhs);
}

/// A submesh within a GPU mesh.
public struct GPUSubMesh
{
	/// Start index in the index buffer.
	public uint32 IndexStart;

	/// Number of indices.
	public uint32 IndexCount;

	/// Base vertex offset.
	public int32 BaseVertex;

	/// Material slot index.
	public uint32 MaterialSlot;
}

/// GPU-side mesh data.
public class GPUMesh
{
	/// Vertex buffer.
	public IBuffer VertexBuffer;

	/// Index buffer.
	public IBuffer IndexBuffer;

	/// Vertex count.
	public uint32 VertexCount;

	/// Index count.
	public uint32 IndexCount;

	/// Vertex stride in bytes.
	public uint32 VertexStride;

	/// Index format.
	public IndexFormat IndexFormat;

	/// Submeshes.
	public GPUSubMesh[] SubMeshes ~ delete _;

	/// Local-space bounding box.
	public BoundingBox Bounds;

	/// Reference count.
	public int32 RefCount;

	/// Generation for handle validation.
	public uint32 Generation;

	/// Whether this slot is in use.
	public bool IsActive;

	/// Frees GPU resources.
	public void Release()
	{
		if (VertexBuffer != null)
		{
			delete VertexBuffer;
			VertexBuffer = null;
		}
		if (IndexBuffer != null)
		{
			delete IndexBuffer;
			IndexBuffer = null;
		}
		IsActive = false;
	}
}

/// GPU-side texture data.
public class GPUTexture
{
	/// The texture.
	public ITexture Texture;

	/// Default view.
	public ITextureView DefaultView;

	/// Width.
	public uint32 Width;

	/// Height.
	public uint32 Height;

	/// Depth or array layers.
	public uint32 DepthOrArrayLayers;

	/// Mip levels.
	public uint32 MipLevels;

	/// Format.
	public TextureFormat Format;

	/// Reference count.
	public int32 RefCount;

	/// Generation for handle validation.
	public uint32 Generation;

	/// Whether this slot is in use.
	public bool IsActive;

	/// Frees GPU resources.
	public void Release()
	{
		if (DefaultView != null)
		{
			delete DefaultView;
			DefaultView = null;
		}
		if (Texture != null)
		{
			delete Texture;
			Texture = null;
		}
		IsActive = false;
	}
}
