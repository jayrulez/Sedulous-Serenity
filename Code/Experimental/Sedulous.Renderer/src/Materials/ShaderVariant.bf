namespace Sedulous.Renderer;

using System;
using Sedulous.RHI;

/// Defines passed to the shader compiler for variant compilation.
public struct ShaderDefine
{
	public StringView Name;
	public StringView Value;
}

/// Uniquely identifies a compiled shader variant.
public struct ShaderVariantKey : IHashable
{
	public uint32 ShaderNameHash;
	public ShaderStage Stage;
	public PipelineVariantFlags Flags;

	public int GetHashCode()
	{
		var h = (int)ShaderNameHash;
		h = h * 31 + (int)Stage;
		h = h * 31 + (int)Flags;
		return h;
	}

	public static bool operator ==(Self lhs, Self rhs) =>
		lhs.ShaderNameHash == rhs.ShaderNameHash &&
		lhs.Stage == rhs.Stage &&
		lhs.Flags == rhs.Flags;

	public static bool operator !=(Self lhs, Self rhs) => !(lhs == rhs);
}
