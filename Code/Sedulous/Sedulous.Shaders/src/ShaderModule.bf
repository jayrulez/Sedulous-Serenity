namespace Sedulous.Shaders;

using System;
using Sedulous.RHI;

/// A compiled shader module with its metadata.
class ShaderModule
{
	public IShaderModule Module ~ delete _;
	public ShaderStage Stage;
	public ShaderFlags Flags;
	public String Name ~ delete _;

	public this(IShaderModule module, ShaderStage stage, ShaderFlags flags, StringView name)
	{
		Module = module;
		Stage = stage;
		Flags = flags;
		Name = new String(name);
	}
}
