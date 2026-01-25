namespace Sedulous.Drawing.Renderer;

using System;

/// Default shader provider with embedded HLSL shaders for 2D drawing.
public class DefaultDrawingShaderProvider : IDrawingShaderProvider
{
	public void GetVertexShaderSource(String outSource)
	{
		outSource.Append(
			"""
			// 2D Drawing vertex shader
			// Transforms 2D vertices with projection matrix

			struct VSInput
			{
			    float2 position : POSITION;
			    float2 texCoord : TEXCOORD0;
			    float4 color : COLOR0;
			};

			struct VSOutput
			{
			    float4 position : SV_Position;
			    float2 texCoord : TEXCOORD0;
			    float4 color : COLOR0;
			};

			cbuffer Uniforms : register(b0)
			{
			    float4x4 projection;
			};

			VSOutput main(VSInput input)
			{
			    VSOutput output;
			    output.position = mul(projection, float4(input.position, 0.0, 1.0));
			    output.texCoord = input.texCoord;
			    output.color = input.color;
			    return output;
			}
			""");
	}

	public void GetFragmentShaderSource(String outSource)
	{
		outSource.Append(
			"""
			// 2D Drawing fragment shader
			// Samples texture and multiplies with vertex color

			struct PSInput
			{
			    float4 position : SV_Position;
			    float2 texCoord : TEXCOORD0;
			    float4 color : COLOR0;
			};

			Texture2D drawTexture : register(t0);
			SamplerState drawSampler : register(s0);

			float4 main(PSInput input) : SV_Target
			{
			    float4 texColor = drawTexture.Sample(drawSampler, input.texCoord);
			    return texColor * input.color;
			}
			""");
	}
}
