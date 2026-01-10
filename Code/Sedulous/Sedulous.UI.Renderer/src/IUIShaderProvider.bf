namespace Sedulous.UI.Renderer;

using System;

/// Interface for providing UI shader source code.
/// Implement this to use custom shaders with UIRenderer.
public interface IUIShaderProvider
{
	/// Get the vertex shader HLSL source code.
	void GetVertexShaderSource(String outSource);

	/// Get the fragment shader HLSL source code.
	void GetFragmentShaderSource(String outSource);
}
