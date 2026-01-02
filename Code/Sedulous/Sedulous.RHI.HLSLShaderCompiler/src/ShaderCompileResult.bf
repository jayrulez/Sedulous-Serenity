namespace Sedulous.RHI.HLSLShaderCompiler;

using System;
using System.Collections;

/// Result of shader compilation.
class ShaderCompileResult
{
	/// Compiled bytecode (owned).
	public List<uint8> Bytecode ~ delete _;

	/// Error messages if compilation failed.
	public String Errors ~ delete _;

	/// Warning messages (may be present even on success).
	public String Warnings ~ delete _;

	/// True if compilation succeeded.
	public bool Success => Bytecode != null && Bytecode.Count > 0 && (Errors == null || Errors.IsEmpty);

	public this()
	{
	}

	/// Creates a successful result with bytecode.
	public static ShaderCompileResult Ok(Span<uint8> bytecode, StringView warnings = default)
	{
		let result = new ShaderCompileResult();
		result.Bytecode = new List<uint8>(bytecode.Length);
		result.Bytecode.AddRange(bytecode);
		if (!warnings.IsEmpty)
		{
			result.Warnings = new String(warnings);
		}
		return result;
	}

	/// Creates a failed result with error message.
	public static ShaderCompileResult Fail(StringView errors)
	{
		let result = new ShaderCompileResult();
		result.Errors = new String(errors);
		return result;
	}
}
