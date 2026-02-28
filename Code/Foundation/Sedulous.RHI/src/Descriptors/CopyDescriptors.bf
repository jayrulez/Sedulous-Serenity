namespace Sedulous.RHI;

/// Origin in a texture for copy operations.
struct Origin3D
{
	public uint32 X;
	public uint32 Y;
	public uint32 Z;

	public this()
	{
		X = 0;
		Y = 0;
		Z = 0;
	}

	public this(uint32 x, uint32 y, uint32 z = 0)
	{
		X = x;
		Y = y;
		Z = z;
	}
}

/// Extent/size for copy operations.
struct Extent3D
{
	public uint32 Width;
	public uint32 Height;
	public uint32 Depth;

	public this()
	{
		Width = 1;
		Height = 1;
		Depth = 1;
	}

	public this(uint32 width, uint32 height = 1, uint32 depth = 1)
	{
		Width = width;
		Height = height;
		Depth = depth;
	}
}

/// Describes a buffer's layout for texture copy operations.
struct TextureDataLayout
{
	/// Offset in bytes from the start of the buffer.
	public uint64 Offset;
	/// Bytes per row (must be multiple of 256 in some APIs).
	public uint32 BytesPerRow;
	/// Rows per image (for 3D textures/texture arrays).
	public uint32 RowsPerImage;

	public this()
	{
		Offset = 0;
		BytesPerRow = 0;
		RowsPerImage = 0;
	}
}

/// Information for copying between buffer and texture.
struct BufferTextureCopyInfo
{
	/// Buffer data layout.
	public TextureDataLayout BufferLayout;
	/// Texture mip level.
	public uint32 TextureMipLevel;
	/// Texture origin.
	public Origin3D TextureOrigin;
	/// Texture array layer.
	public uint32 TextureArrayLayer;
	/// Size of the region to copy.
	public Extent3D CopySize;

	public this()
	{
		BufferLayout = .();
		TextureMipLevel = 0;
		TextureOrigin = .();
		TextureArrayLayer = 0;
		CopySize = .();
	}
}

/// Information for copying between textures.
struct TextureCopyInfo
{
	/// Source mip level.
	public uint32 SrcMipLevel;
	/// Source origin.
	public Origin3D SrcOrigin;
	/// Source array layer.
	public uint32 SrcArrayLayer;
	/// Destination mip level.
	public uint32 DstMipLevel;
	/// Destination origin.
	public Origin3D DstOrigin;
	/// Destination array layer.
	public uint32 DstArrayLayer;
	/// Size of the region to copy.
	public Extent3D CopySize;

	public this()
	{
		SrcMipLevel = 0;
		SrcOrigin = .();
		SrcArrayLayer = 0;
		DstMipLevel = 0;
		DstOrigin = .();
		DstArrayLayer = 0;
		CopySize = .();
	}
}
