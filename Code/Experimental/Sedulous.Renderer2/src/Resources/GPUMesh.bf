namespace Sedulous.Renderer;

using System;
using Sedulous.RHI;
using Sedulous.Core.Mathematics;

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

/// Handle to a GPU bone buffer.
public struct GPUBoneBufferHandle : IHashable
{
	public uint32 Index;
	public uint32 Generation;

	public static Self Invalid = .() { Index = uint32.MaxValue, Generation = 0 };

	public bool IsValid => Index != uint32.MaxValue;

	public int GetHashCode() => (int)(Index ^ (Generation << 16));

	public static bool operator ==(Self lhs, Self rhs) => lhs.Index == rhs.Index && lhs.Generation == rhs.Generation;
	public static bool operator !=(Self lhs, Self rhs) => !(lhs == rhs);
}

/// LOD level descriptor within a GPU mesh.
public struct GPUMeshLOD
{
	public uint32 SubMeshStart;
	public uint32 SubMeshCount;
}

/// A submesh within a GPU mesh.
public struct GPUSubMesh
{
	public uint32 IndexStart;
	public uint32 IndexCount;
	public int32 BaseVertex;
	public uint32 MaterialSlot;
}

/// GPU-side mesh data.
public class GPUMesh
{
	public IBuffer VertexBuffer;
	public IBuffer IndexBuffer;
	public uint32 VertexCount;
	public uint32 IndexCount;
	public uint32 VertexStride;
	public IndexFormat IndexFormat;
	public GPUSubMesh[] SubMeshes ~ delete _;
	public BoundingBox Bounds;
	public int32 RefCount;
	public uint32 Generation;
	public bool IsActive;
	public bool IsSkinned;
	public GPUMeshLOD[] LODLevels ~ delete _;
	public uint32 LODCount;

	public void Release(IDevice device)
	{
		if (device != null)
		{
			device.DestroyBuffer(ref VertexBuffer);
			device.DestroyBuffer(ref IndexBuffer);
		}
		if (SubMeshes != null) { delete SubMeshes; SubMeshes = null; }
		if (LODLevels != null) { delete LODLevels; LODLevels = null; }
		LODCount = 0;
		IsActive = false;
	}
}

/// GPU-side texture data.
public class GPUTexture
{
	public ITexture Texture;
	public ITextureView DefaultView;
	public uint32 Width;
	public uint32 Height;
	public uint32 DepthOrArrayLayers;
	public uint32 MipLevels;
	public TextureFormat Format;
	public int32 RefCount;
	public uint32 Generation;
	public bool IsActive;

	public void Release(IDevice device)
	{
		if (device != null)
		{
			device.DestroyTextureView(ref DefaultView);
			device.DestroyTexture(ref Texture);
		}
		IsActive = false;
	}
}
