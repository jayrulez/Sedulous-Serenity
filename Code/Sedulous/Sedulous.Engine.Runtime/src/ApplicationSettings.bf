using Sedulous.RHI;
using Sedulous.Mathematics;
using System;

namespace Sedulous.Engine.Runtime;

struct ApplicationSettings
{
	public StringView Title = "Sedulous Application";
	public int32 Width = 1280;
	public int32 Height = 720;
	public bool Resizable = true;
	public TextureFormat SwapChainFormat = .BGRA8UnormSrgb;
	public PresentMode PresentMode = .Fifo;
	public Color ClearColor = .(0.1f, 0.1f, 0.1f, 1.0f);
	public bool EnableDepth = false;
	public TextureFormat DepthFormat = .Depth24PlusStencil8;
}
