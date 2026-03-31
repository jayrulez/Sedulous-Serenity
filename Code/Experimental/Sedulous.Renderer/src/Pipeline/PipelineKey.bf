namespace Sedulous.Renderer;

using System;
using Sedulous.RHI;

/// Cache key that uniquely identifies a render pipeline configuration.
/// Encodes shader identity, render state, vertex layout, and RT formats
/// into a hashable struct for dictionary lookup.
public struct PipelineKey : IHashable
{
	/// Vertex shader variant key.
	public ShaderVariantKey VertexShader;
	/// Fragment shader variant key.
	public ShaderVariantKey FragmentShader;
	/// Vertex layout hash.
	public uint32 VertexLayoutHash;
	/// Blend mode.
	public BlendMode BlendMode;
	/// Cull mode.
	public CullMode CullMode;
	/// Depth mode.
	public DepthMode DepthMode;
	/// Color target format.
	public TextureFormat ColorFormat;
	/// Second color target format (Undefined = single target).
	public TextureFormat ColorFormat2;
	/// Depth target format.
	public TextureFormat DepthFormat;
	/// MSAA sample count.
	public uint8 SampleCount;
	/// Pipeline variant flags.
	public PipelineVariantFlags VariantFlags;

	public int GetHashCode()
	{
		var h = VertexShader.GetHashCode();
		h = h * 31 + FragmentShader.GetHashCode();
		h = h * 31 + (int)VertexLayoutHash;
		h = h * 31 + (int)BlendMode;
		h = h * 31 + (int)CullMode;
		h = h * 31 + (int)DepthMode;
		h = h * 31 + (int)ColorFormat;
		h = h * 31 + (int)ColorFormat2;
		h = h * 31 + (int)DepthFormat;
		h = h * 31 + (int)SampleCount;
		h = h * 31 + (int)VariantFlags;
		return h;
	}

	public static bool operator ==(Self lhs, Self rhs)
	{
		return lhs.VertexShader == rhs.VertexShader &&
			lhs.FragmentShader == rhs.FragmentShader &&
			lhs.VertexLayoutHash == rhs.VertexLayoutHash &&
			lhs.BlendMode == rhs.BlendMode &&
			lhs.CullMode == rhs.CullMode &&
			lhs.DepthMode == rhs.DepthMode &&
			lhs.ColorFormat == rhs.ColorFormat &&
			lhs.ColorFormat2 == rhs.ColorFormat2 &&
			lhs.DepthFormat == rhs.DepthFormat &&
			lhs.SampleCount == rhs.SampleCount &&
			lhs.VariantFlags == rhs.VariantFlags;
	}

	public static bool operator !=(Self lhs, Self rhs) => !(lhs == rhs);

	/// Computes a hash from vertex buffer layouts for use in VertexLayoutHash.
	public static uint32 HashVertexLayouts(Span<VertexBufferLayout> layouts)
	{
		uint32 hash = 2166136261;
		for (let layout in layouts)
		{
			hash ^= layout.Stride;
			hash *= 16777619;
			hash ^= (uint32)layout.StepMode;
			hash *= 16777619;
			for (let attr in layout.Attributes)
			{
				hash ^= (uint32)attr.Format;
				hash *= 16777619;
				hash ^= attr.Offset;
				hash *= 16777619;
				hash ^= attr.ShaderLocation;
				hash *= 16777619;
			}
		}
		return hash;
	}
}
