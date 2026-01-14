namespace Sedulous.Shaders;

using System;
using Sedulous.RHI;

/// Identifies a specific shader variant.
struct ShaderVariantKey : IEquatable<ShaderVariantKey>, IHashable
{
	public StringView ShaderName;
	public ShaderFlags Flags;
	public ShaderStage Stage;

	public this(StringView name, ShaderStage stage, ShaderFlags flags = .None)
	{
		ShaderName = name;
		Stage = stage;
		Flags = flags;
	}

	public bool Equals(ShaderVariantKey other)
	{
		return ShaderName == other.ShaderName && Flags == other.Flags && Stage == other.Stage;
	}

	public int GetHashCode()
	{
		int hash = ShaderName.GetHashCode();
		hash = hash * 31 + (int)Flags;
		hash = hash * 31 + (int)Stage;
		return hash;
	}

	/// Generate a unique string key for caching purposes.
	public void GenerateCacheKey(String outKey)
	{
		outKey.Clear();
		outKey.Append(ShaderName);
		outKey.Append("_");

		switch (Stage)
		{
		case .Vertex:   outKey.Append("vert");
		case .Fragment: outKey.Append("frag");
		case .Compute:  outKey.Append("comp");
		default:        outKey.Append("unknown");
		}

		if (Flags != .None)
		{
			outKey.AppendF("_{:X}", (uint32)Flags);
		}
	}
}
