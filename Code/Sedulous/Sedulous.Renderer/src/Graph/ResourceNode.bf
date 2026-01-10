namespace Sedulous.Renderer;

using System;
using Sedulous.RHI;

/// Tracks the state and lifetime of a resource within the render graph.
class ResourceNode
{
	/// Resource name for debugging.
	public String Name ~ delete _;

	/// Type of resource (texture or buffer).
	public ResourceType Type;

	/// True if this resource was imported from outside the graph.
	public bool IsImported;

	/// True if this is a transient resource owned by the graph.
	public bool IsTransient => !IsImported;

	/// Index of the first pass that uses this resource.
	public uint32 FirstUsePass = uint32.MaxValue;

	/// Index of the last pass that uses this resource.
	public uint32 LastUsePass = 0;

	// Texture-specific properties
	public TextureDescriptor TextureDesc;
	public ITexture Texture;
	public ITextureView TextureView;

	// Buffer-specific properties
	public BufferDescriptor BufferDesc;
	public IBuffer Buffer;

	/// Current texture layout (for barrier tracking).
	public TextureLayout CurrentLayout = .Undefined;

	public this(StringView name, ResourceType type)
	{
		Name = new String(name);
		Type = type;
	}

	public ~this()
	{
		// Only delete resources if they are transient (owned by the graph)
		if (IsTransient)
		{
			if (TextureView != null)
				delete TextureView;
			if (Texture != null)
				delete Texture;
			if (Buffer != null)
				delete Buffer;
		}
	}

	/// Records that this resource is used by the given pass.
	public void RecordUsage(uint32 passIndex)
	{
		FirstUsePass = Math.Min(FirstUsePass, passIndex);
		LastUsePass = Math.Max(LastUsePass, passIndex);
	}

	/// Returns true if the resource's lifetime overlaps with the given pass range.
	public bool OverlapsWith(uint32 firstPass, uint32 lastPass)
	{
		return !(LastUsePass < firstPass || FirstUsePass > lastPass);
	}
}
