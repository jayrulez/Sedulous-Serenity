using System;
using System.Collections;
using Sedulous.Mathematics;

namespace Sedulous.UI.FontRenderer;

/// Font atlas for GPU rendering of text.
/// Stores glyph bitmaps in a texture atlas.
class FontAtlas
{
	/// Node for rectangle packing (skyline algorithm).
	private struct SkylineNode
	{
		public int32 X;
		public int32 Y;
		public int32 Width;
	}

	private uint32 mWidth;
	private uint32 mHeight;
	private uint8[] mData ~ delete _;
	private List<SkylineNode> mSkyline = new .() ~ delete _;
	private bool mIsDirty;

	/// Creates a font atlas with the specified size.
	public this(uint32 width, uint32 height)
	{
		mWidth = width;
		mHeight = height;
		mData = new uint8[width * height];
		mIsDirty = false;

		// Initialize skyline with single node spanning width
		mSkyline.Add(SkylineNode() { X = 0, Y = 0, Width = (int32)width });
	}

	/// Gets the atlas width.
	public uint32 Width => mWidth;

	/// Gets the atlas height.
	public uint32 Height => mHeight;

	/// Gets the atlas pixel data (single channel).
	public Span<uint8> Data => mData;

	/// Gets whether the atlas has been modified since last clear of dirty flag.
	public bool IsDirty => mIsDirty;

	/// Clears the dirty flag.
	public void ClearDirty()
	{
		mIsDirty = false;
	}

	/// Clears the atlas and resets the packer.
	public void Clear()
	{
		Internal.MemSet(mData.Ptr, 0, mData.Count);
		mSkyline.Clear();
		mSkyline.Add(SkylineNode() { X = 0, Y = 0, Width = (int32)mWidth });
		mIsDirty = true;
	}

	/// Attempts to pack a rectangle into the atlas.
	/// Returns the allocated region, or empty rect if it doesn't fit.
	public RectangleF Pack(uint32 width, uint32 height)
	{
		if (width == 0 || height == 0)
			return .Empty;

		// Add 1 pixel padding
		let paddedWidth = (int32)width + 1;
		let paddedHeight = (int32)height + 1;

		// Find best position using skyline bottom-left algorithm
		int bestIndex = -1;
		int32 bestY = (int32)mHeight;
		int32 bestX = 0;

		for (int i = 0; i < mSkyline.Count; i++)
		{
			let result = FitSkyline(i, paddedWidth, paddedHeight);
			if (result.fits && result.y < bestY)
			{
				bestY = result.y;
				bestX = mSkyline[i].X;
				bestIndex = i;
			}
		}

		if (bestIndex == -1)
			return .Empty; // Doesn't fit

		// Add the new skyline node
		var newNode = SkylineNode()
		{
			X = bestX,
			Y = bestY + paddedHeight,
			Width = paddedWidth
		};
		mSkyline.Insert(bestIndex, newNode);

		// Shrink/remove nodes covered by the new node
		for (int i = bestIndex + 1; i < mSkyline.Count;)
		{
			let node = mSkyline[i];
			let prevNode = mSkyline[i - 1];

			if (node.X < prevNode.X + prevNode.Width)
			{
				let shrink = prevNode.X + prevNode.Width - node.X;
				if (node.Width <= shrink)
				{
					mSkyline.RemoveAt(i);
				}
				else
				{
					mSkyline[i] = SkylineNode()
					{
						X = node.X + shrink,
						Y = node.Y,
						Width = node.Width - shrink
					};
					break;
				}
			}
			else
			{
				break;
			}
		}

		// Merge nodes at the same height
		MergeSkyline();

		mIsDirty = true;

		// Return UV coordinates (0-1 range)
		return RectangleF(
			(float)bestX / mWidth,
			(float)bestY / mHeight,
			(float)width / mWidth,
			(float)height / mHeight
		);
	}

	/// Copies glyph bitmap data into the atlas at the specified position.
	public void SetRegion(int32 x, int32 y, int32 width, int32 height, uint8* data, int32 stride)
	{
		for (int32 row = 0; row < height; row++)
		{
			let srcOffset = row * stride;
			let dstOffset = ((y + row) * (int32)mWidth) + x;

			if (dstOffset >= 0 && dstOffset + width <= mData.Count)
			{
				Internal.MemCpy(&mData[dstOffset], &data[srcOffset], width);
			}
		}
		mIsDirty = true;
	}

	/// Checks if a rectangle fits at the given skyline index.
	private (bool fits, int32 y) FitSkyline(int index, int32 width, int32 height)
	{
		let node = mSkyline[index];

		if (node.X + width > (int32)mWidth)
			return (false, 0);

		int32 y = node.Y;
		int32 widthLeft = width;
		int i = index;

		while (widthLeft > 0)
		{
			if (i >= mSkyline.Count)
				return (false, 0);

			let n = mSkyline[i];
			y = Math.Max(y, n.Y);

			if (y + height > (int32)mHeight)
				return (false, 0);

			widthLeft -= n.Width;
			i++;
		}

		return (true, y);
	}

	/// Merges adjacent skyline nodes at the same height.
	private void MergeSkyline()
	{
		for (int i = 0; i < mSkyline.Count - 1;)
		{
			let current = mSkyline[i];
			let next = mSkyline[i + 1];

			if (current.Y == next.Y)
			{
				mSkyline[i] = SkylineNode()
				{
					X = current.X,
					Y = current.Y,
					Width = current.Width + next.Width
				};
				mSkyline.RemoveAt(i + 1);
			}
			else
			{
				i++;
			}
		}
	}
}
