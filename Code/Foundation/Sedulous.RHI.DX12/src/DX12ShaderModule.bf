namespace Sedulous.RHI.DX12;

using System;
using Win32.Graphics.Direct3D12;
using Sedulous.RHI;

/// DX12 implementation of IShaderModule. Stores DXIL bytecode.
class DX12ShaderModule : IShaderModule
{
	private uint8* mBytecode;
	private uint mSize;

	public this(ShaderModuleDesc descriptor)
	{
		if (descriptor.Code.Length > 0)
		{
			mSize = (uint)descriptor.Code.Length;
			mBytecode = new uint8[descriptor.Code.Length]*;
			Internal.MemCpy(mBytecode, descriptor.Code.Ptr, descriptor.Code.Length);
		}
	}

	public ~this()
	{
		Dispose();
	}

	public void Dispose()
	{
		if (mBytecode != null)
		{
			delete mBytecode;
			mBytecode = null;
		}
	}

	public bool IsValid => mBytecode != null && mSize > 0;

	/// Gets the raw bytecode as a span for reflection/parsing.
	public Span<uint8> BytecodeSpan => .(mBytecode, (int)mSize);

	/// Gets the shader bytecode as a D3D12_SHADER_BYTECODE.
	public D3D12_SHADER_BYTECODE GetBytecode()
	{
		D3D12_SHADER_BYTECODE bc = .();
		bc.pShaderBytecode = mBytecode;
		bc.BytecodeLength = mSize;
		return bc;
	}
}
