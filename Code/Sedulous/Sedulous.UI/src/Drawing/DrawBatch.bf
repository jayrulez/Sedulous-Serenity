using System;
using System.Collections;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// Vertex for UI rendering.
struct UIVertex
{
	/// Position (x, y).
	public Vector2 Position;
	/// Texture coordinates.
	public Vector2 TexCoord;
	/// Vertex color.
	public Color Color;

	/// Creates a UI vertex.
	public this(Vector2 position, Vector2 texCoord, Color color)
	{
		Position = position;
		TexCoord = texCoord;
		Color = color;
	}
}

/// Batched draw commands for rendering.
class DrawBatch
{
	/// Draw commands to execute.
	public List<DrawCommand> Commands = new .() ~ delete _;
	/// Clip rectangles.
	public List<ClipRect> ClipRects = new .() ~ delete _;
	/// Vertices for custom geometry.
	public List<UIVertex> Vertices = new .() ~ delete _;
	/// Indices for custom geometry.
	public List<uint16> Indices = new .() ~ delete _;
	/// Text buffer for text commands.
	public String TextBuffer = new .() ~ delete _;
	/// Textures used in this batch.
	public List<TextureHandle> Textures = new .() ~ delete _;

	/// Clears all data from the batch.
	public void Clear()
	{
		Commands.Clear();
		ClipRects.Clear();
		Vertices.Clear();
		Indices.Clear();
		TextBuffer.Clear();
		Textures.Clear();
	}

	/// Gets the total number of draw commands.
	public int CommandCount => Commands.Count;

	/// Gets whether the batch is empty.
	public bool IsEmpty => Commands.Count == 0;

	/// Adds a clip rectangle and returns its index.
	public uint16 AddClipRect(RectangleF bounds, int32 parentIndex = -1)
	{
		let index = (uint16)ClipRects.Count;
		ClipRects.Add(ClipRect(bounds, parentIndex));
		return index;
	}

	/// Adds a texture and returns its index (for deduplication).
	public int AddTexture(TextureHandle texture)
	{
		// Check if already added
		let idx = Textures.IndexOf(texture);
		if (idx >= 0)
			return idx;

		let newIdx = Textures.Count;
		Textures.Add(texture);
		return newIdx;
	}

	/// Adds text to the text buffer and returns offset.
	public uint32 AddText(StringView text)
	{
		let offset = (uint32)TextBuffer.Length;
		TextBuffer.Append(text);
		return offset;
	}

	/// Adds vertices and returns the starting offset.
	public uint32 AddVertices(Span<UIVertex> verts)
	{
		let offset = (uint32)Vertices.Count;
		for (let v in verts)
			Vertices.Add(v);
		return offset;
	}

	/// Adds indices and returns the starting offset.
	public uint32 AddIndices(Span<uint16> inds)
	{
		let offset = (uint32)Indices.Count;
		for (let i in inds)
			Indices.Add(i);
		return offset;
	}
}
