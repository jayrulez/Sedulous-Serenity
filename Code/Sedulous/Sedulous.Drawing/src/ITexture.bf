using System;

namespace Sedulous.Drawing;

/// Interface for textures used in 2D drawing
/// This interface provides texture metadata for the drawing system.
/// The actual GPU texture is accessed via the Handle property.
public interface ITexture
{
	/// Width of the texture in pixels
	uint32 Width { get; }

	/// Height of the texture in pixels
	uint32 Height { get; }

	/// Opaque handle to the underlying GPU texture
	/// The renderer will interpret this based on its implementation
	Object Handle { get; }
}

/// A simple texture reference that wraps an existing texture handle
public class TextureRef : ITexture
{
	private Object mHandle;
	private uint32 mWidth;
	private uint32 mHeight;

	public uint32 Width => mWidth;
	public uint32 Height => mHeight;
	public Object Handle => mHandle;

	public this(Object handle, uint32 width, uint32 height)
	{
		mHandle = handle;
		mWidth = width;
		mHeight = height;
	}
}
