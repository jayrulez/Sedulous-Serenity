namespace Sedulous.RHI.DX12;

using System;
using System.Collections;
using Win32.Graphics.Direct3D12;
using Win32.Graphics.Direct3D;
using Win32.Graphics.Direct3D.Fxc;
using Win32.Graphics.Dxgi;
using Win32.Graphics.Dxgi.Common;
using Win32.Foundation;
using Win32.System.Com;
using Sedulous.RHI;
using Sedulous.RHI.DX12.Internal;

using Win32;

/// DX12 implementation of IDevice.
class DX12Device : IDevice
{
	private DX12Adapter mAdapter;
	private ID3D12Device* mDevice;
	private DX12Queue mQueue;

	// Descriptor heaps
	private DX12DescriptorAllocator mCbvSrvUavGpuHeap;
	private DX12DescriptorAllocator mSamplerGpuHeap;
	private DX12DescriptorAllocator mCbvSrvUavCpuHeap;
	private DX12DescriptorAllocator mSamplerCpuHeap;
	private DX12CpuDescriptorAllocator mRtvHeap;
	private DX12CpuDescriptorAllocator mDsvHeap;

	// Pre-created command signatures for indirect drawing
	private ID3D12CommandSignature* mDrawSignature;
	private ID3D12CommandSignature* mDrawIndexedSignature;
	private ID3D12CommandSignature* mDispatchSignature;

	// Blit pipeline (for scaled texture blits)
	private ID3D12RootSignature* mBlitRootSignature;
	private D3D12_SHADER_BYTECODE mBlitVsBytecode;
	private D3D12_SHADER_BYTECODE mBlitPsBytecode;
	private ID3DBlob* mBlitVsBlob;
	private ID3DBlob* mBlitPsBlob;
	private Dictionary<DXGI_FORMAT, ID3D12PipelineState*> mBlitPsoCache = new .();

	public this(DX12Adapter adapter)
	{
		mAdapter = adapter;
		CreateDevice();

		if (mDevice != null)
		{
			CreateDescriptorHeaps();
			CreateCommandSignatures();
			CreateBlitPipeline();
		}
	}

	public ~this()
	{
		Dispose();
	}

	public void Dispose()
	{
		if (mQueue != null) { delete mQueue; mQueue = null; }

		// Blit pipeline
		if (mBlitPsoCache != null)
		{
			for (let pso in mBlitPsoCache.Values)
				pso.Release();
			delete mBlitPsoCache;
			mBlitPsoCache = null;
		}
		if (mBlitVsBlob != null) { mBlitVsBlob.Release(); mBlitVsBlob = null; }
		if (mBlitPsBlob != null) { mBlitPsBlob.Release(); mBlitPsBlob = null; }
		if (mBlitRootSignature != null) { mBlitRootSignature.Release(); mBlitRootSignature = null; }

		if (mDrawSignature != null) { mDrawSignature.Release(); mDrawSignature = null; }
		if (mDrawIndexedSignature != null) { mDrawIndexedSignature.Release(); mDrawIndexedSignature = null; }
		if (mDispatchSignature != null) { mDispatchSignature.Release(); mDispatchSignature = null; }

		if (mCbvSrvUavGpuHeap != null) { delete mCbvSrvUavGpuHeap; mCbvSrvUavGpuHeap = null; }
		if (mSamplerGpuHeap != null) { delete mSamplerGpuHeap; mSamplerGpuHeap = null; }
		if (mCbvSrvUavCpuHeap != null) { delete mCbvSrvUavCpuHeap; mCbvSrvUavCpuHeap = null; }
		if (mSamplerCpuHeap != null) { delete mSamplerCpuHeap; mSamplerCpuHeap = null; }
		if (mRtvHeap != null) { delete mRtvHeap; mRtvHeap = null; }
		if (mDsvHeap != null) { delete mDsvHeap; mDsvHeap = null; }

		if (mDevice != null) { mDevice.Release(); mDevice = null; }
	}

	public bool IsInitialized => mDevice != null;
	public IAdapter Adapter => mAdapter;
	public IQueue Queue => mQueue;
	public bool FlipProjectionRequired => false;

	public ID3D12Device* NativeDevice => mDevice;
	public DX12DescriptorAllocator CbvSrvUavGpuHeap => mCbvSrvUavGpuHeap;
	public DX12DescriptorAllocator SamplerGpuHeap => mSamplerGpuHeap;
	public DX12DescriptorAllocator CbvSrvUavCpuHeap => mCbvSrvUavCpuHeap;
	public DX12DescriptorAllocator SamplerCpuHeap => mSamplerCpuHeap;
	public DX12CpuDescriptorAllocator RtvHeap => mRtvHeap;
	public DX12CpuDescriptorAllocator DsvHeap => mDsvHeap;
	public ID3D12CommandSignature* DrawSignature => mDrawSignature;
	public ID3D12CommandSignature* DrawIndexedSignature => mDrawIndexedSignature;
	public ID3D12CommandSignature* DispatchSignature => mDispatchSignature;
	public IDXGIFactory6* DXGIFactory => mAdapter.Backend.Factory;
	public ID3D12RootSignature* BlitRootSignature => mBlitRootSignature;

	// ===== Resource Creation =====

	public Result<IBuffer> CreateBuffer(BufferDescriptor* descriptor)
	{
		let buffer = new DX12Buffer(this, descriptor);
		if (!buffer.IsValid)
		{
			delete buffer;
			return .Err;
		}
		return .Ok(buffer);
	}

	public Result<ITexture> CreateTexture(TextureDescriptor* descriptor)
	{
		let texture = new DX12Texture(this, descriptor);
		if (!texture.IsValid)
		{
			delete texture;
			return .Err;
		}
		return .Ok(texture);
	}

	public Result<ITextureView> CreateTextureView(ITexture texture, TextureViewDescriptor* descriptor)
	{
		if (let dx12Texture = texture as DX12Texture)
		{
			let view = new DX12TextureView(this, dx12Texture, descriptor);
			if (!view.IsValid)
			{
				delete view;
				return .Err;
			}
			return .Ok(view);
		}
		return .Err;
	}

	public Result<ISampler> CreateSampler(SamplerDescriptor* descriptor)
	{
		let sampler = new DX12Sampler(this, descriptor);
		if (!sampler.IsValid)
		{
			delete sampler;
			return .Err;
		}
		return .Ok(sampler);
	}

	public Result<IShaderModule> CreateShaderModule(ShaderModuleDescriptor* descriptor)
	{
		let shaderModule = new DX12ShaderModule(descriptor);
		if (!shaderModule.IsValid)
		{
			delete shaderModule;
			return .Err;
		}
		return .Ok(shaderModule);
	}

	// ===== Binding =====

	public Result<IBindGroupLayout> CreateBindGroupLayout(BindGroupLayoutDescriptor* descriptor)
	{
		let layout = new DX12BindGroupLayout(descriptor);
		return .Ok(layout);
	}

	public Result<IBindGroup> CreateBindGroup(BindGroupDescriptor* descriptor)
	{
		let bindGroup = new DX12BindGroup(this, descriptor);
		if (!bindGroup.IsValid)
		{
			delete bindGroup;
			return .Err;
		}
		return .Ok(bindGroup);
	}

	public Result<IPipelineLayout> CreatePipelineLayout(PipelineLayoutDescriptor* descriptor)
	{
		let layout = new DX12PipelineLayout(this, descriptor);
		if (!layout.IsValid)
		{
			delete layout;
			return .Err;
		}
		return .Ok(layout);
	}

	// ===== Pipelines =====

	public Result<IRenderPipeline> CreateRenderPipeline(RenderPipelineDescriptor* descriptor)
	{
		let pipeline = new DX12RenderPipeline(this, descriptor);
		if (!pipeline.IsValid)
		{
			delete pipeline;
			return .Err;
		}
		return .Ok(pipeline);
	}

	public Result<IComputePipeline> CreateComputePipeline(ComputePipelineDescriptor* descriptor)
	{
		let pipeline = new DX12ComputePipeline(this, descriptor);
		if (!pipeline.IsValid)
		{
			delete pipeline;
			return .Err;
		}
		return .Ok(pipeline);
	}

	// ===== Commands =====

	public ICommandEncoder CreateCommandEncoder()
	{
		let encoder = new DX12CommandEncoder(this);
		if (!encoder.IsValid)
		{
			delete encoder;
			return null;
		}
		return encoder;
	}

	// ===== Queries =====

	public Result<IQuerySet> CreateQuerySet(QuerySetDescriptor* descriptor)
	{
		let querySet = new DX12QuerySet(this, descriptor);
		if (!querySet.IsValid)
		{
			delete querySet;
			return .Err;
		}
		return .Ok(querySet);
	}

	// ===== Presentation =====

	public Result<ISwapChain> CreateSwapChain(ISurface surface, SwapChainDescriptor* descriptor)
	{
		if (let dx12Surface = surface as DX12Surface)
		{
			let swapChain = new DX12SwapChain(this, dx12Surface, descriptor);
			if (!swapChain.IsValid)
			{
				delete swapChain;
				return .Err;
			}
			return .Ok(swapChain);
		}
		return .Err;
	}

	// ===== Synchronization =====

	public Result<IFence> CreateFence(bool signaled = false)
	{
		let fence = new DX12Fence(this, signaled);
		if (!fence.IsValid)
		{
			delete fence;
			return .Err;
		}
		return .Ok(fence);
	}

	public void WaitIdle()
	{
		if (mQueue != null)
			mQueue.WaitIdle();
	}

	// ===== Internal =====

	private void CreateDevice()
	{
		HRESULT hr = D3D12CreateDevice(
			(IUnknown*)mAdapter.Adapter,
			.D3D_FEATURE_LEVEL_12_0,
			ID3D12Device.IID,
			(void**)&mDevice);

		if (!SUCCEEDED(hr))
		{
			mDevice = null;
			Console.Error.WriteLine("[DX12] ERROR: Failed to create D3D12 device");
			return;
		}

		// Create command queue
		D3D12_COMMAND_QUEUE_DESC queueDesc = .();
		queueDesc.Type = .D3D12_COMMAND_LIST_TYPE_DIRECT;
		queueDesc.Priority = (int32)D3D12_COMMAND_QUEUE_PRIORITY.D3D12_COMMAND_QUEUE_PRIORITY_NORMAL;
		queueDesc.Flags = .D3D12_COMMAND_QUEUE_FLAG_NONE;
		queueDesc.NodeMask = 0;

		ID3D12CommandQueue* cmdQueue = null;
		hr = mDevice.CreateCommandQueue(&queueDesc, ID3D12CommandQueue.IID, (void**)&cmdQueue);
		if (SUCCEEDED(hr))
		{
			mQueue = new DX12Queue(this, cmdQueue);
		}
		else
		{
			Console.Error.WriteLine("[DX12] ERROR: Failed to create command queue");
		}

		// Suppress harmless warnings via info queue
		ConfigureInfoQueue();

		Console.WriteLine("[DX12] Device created successfully");
	}

	private void ConfigureInfoQueue()
	{
		ID3D12InfoQueue* infoQueue = null;
		if (SUCCEEDED(mDevice.QueryInterface(ID3D12InfoQueue.IID, (void**)&infoQueue)))
		{
			// Suppress warnings that are unavoidable or harmless
			D3D12_MESSAGE_ID[1] suppressIds = .(
				// Swap chain back buffers can't have optimized clear values
				.D3D12_MESSAGE_ID_CLEARRENDERTARGETVIEW_MISMATCHINGCLEARVALUE
			);

			D3D12_INFO_QUEUE_FILTER filter = .();
			filter.DenyList.NumIDs = (uint32)suppressIds.Count;
			filter.DenyList.pIDList = &suppressIds;
			infoQueue.AddStorageFilterEntries(&filter);
			infoQueue.Release();
		}
	}

	private void CreateDescriptorHeaps()
	{
		mCbvSrvUavGpuHeap = new DX12DescriptorAllocator(mDevice, .D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV, 100000, true);
		mSamplerGpuHeap = new DX12DescriptorAllocator(mDevice, .D3D12_DESCRIPTOR_HEAP_TYPE_SAMPLER, 2048, true);
		mCbvSrvUavCpuHeap = new DX12DescriptorAllocator(mDevice, .D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV, 100000, false);
		mSamplerCpuHeap = new DX12DescriptorAllocator(mDevice, .D3D12_DESCRIPTOR_HEAP_TYPE_SAMPLER, 2048, false);
		mRtvHeap = new DX12CpuDescriptorAllocator(mDevice, .D3D12_DESCRIPTOR_HEAP_TYPE_RTV, 1024);
		mDsvHeap = new DX12CpuDescriptorAllocator(mDevice, .D3D12_DESCRIPTOR_HEAP_TYPE_DSV, 256);
	}

	/// Gets or creates a blit PSO for the given render target format.
	public ID3D12PipelineState* GetOrCreateBlitPSO(DXGI_FORMAT format)
	{
		if (mBlitRootSignature == null)
			return null;

		if (mBlitPsoCache.TryGetValue(format, let pso))
			return pso;

		D3D12_GRAPHICS_PIPELINE_STATE_DESC desc = .();
		desc.pRootSignature = mBlitRootSignature;
		desc.VS = mBlitVsBytecode;
		desc.PS = mBlitPsBytecode;

		// No input layout (fullscreen triangle from SV_VertexID)
		desc.InputLayout.pInputElementDescs = null;
		desc.InputLayout.NumElements = 0;
		desc.PrimitiveTopologyType = .D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE;

		// Rasterizer — no culling
		desc.RasterizerState.FillMode = .D3D12_FILL_MODE_SOLID;
		desc.RasterizerState.CullMode = .D3D12_CULL_MODE_NONE;
		desc.RasterizerState.FrontCounterClockwise = FALSE;
		desc.RasterizerState.DepthClipEnable = FALSE;

		// No blending, write all channels
		desc.BlendState.RenderTarget[0].BlendEnable = FALSE;
		desc.BlendState.RenderTarget[0].RenderTargetWriteMask = 0x0F;

		// No depth
		desc.DepthStencilState.DepthEnable = FALSE;
		desc.DepthStencilState.StencilEnable = FALSE;
		desc.DSVFormat = .DXGI_FORMAT_UNKNOWN;

		// Single render target
		desc.NumRenderTargets = 1;
		desc.RTVFormats[0] = format;
		desc.SampleDesc.Count = 1;
		desc.SampleDesc.Quality = 0;
		desc.SampleMask = uint32.MaxValue;
		desc.NodeMask = 0;
		desc.Flags = .D3D12_PIPELINE_STATE_FLAG_NONE;

		ID3D12PipelineState* newPso = null;
		HRESULT hr = mDevice.CreateGraphicsPipelineState(&desc, ID3D12PipelineState.IID, (void**)&newPso);
		if (SUCCEEDED(hr))
		{
			mBlitPsoCache[format] = newPso;
			return newPso;
		}

		return null;
	}

	private void CreateCommandSignatures()
	{
		// Draw signature
		{
			D3D12_INDIRECT_ARGUMENT_DESC argDesc = .();
			argDesc.Type = .D3D12_INDIRECT_ARGUMENT_TYPE_DRAW;

			D3D12_COMMAND_SIGNATURE_DESC desc = .();
			desc.ByteStride = 16; // sizeof(D3D12_DRAW_ARGUMENTS)
			desc.NumArgumentDescs = 1;
			desc.pArgumentDescs = &argDesc;
			desc.NodeMask = 0;

			mDevice.CreateCommandSignature(&desc, null, ID3D12CommandSignature.IID, (void**)&mDrawSignature);
		}

		// Draw indexed signature
		{
			D3D12_INDIRECT_ARGUMENT_DESC argDesc = .();
			argDesc.Type = .D3D12_INDIRECT_ARGUMENT_TYPE_DRAW_INDEXED;

			D3D12_COMMAND_SIGNATURE_DESC desc = .();
			desc.ByteStride = 20; // sizeof(D3D12_DRAW_INDEXED_ARGUMENTS)
			desc.NumArgumentDescs = 1;
			desc.pArgumentDescs = &argDesc;
			desc.NodeMask = 0;

			mDevice.CreateCommandSignature(&desc, null, ID3D12CommandSignature.IID, (void**)&mDrawIndexedSignature);
		}

		// Dispatch signature
		{
			D3D12_INDIRECT_ARGUMENT_DESC argDesc = .();
			argDesc.Type = .D3D12_INDIRECT_ARGUMENT_TYPE_DISPATCH;

			D3D12_COMMAND_SIGNATURE_DESC desc = .();
			desc.ByteStride = 12; // sizeof(D3D12_DISPATCH_ARGUMENTS)
			desc.NumArgumentDescs = 1;
			desc.pArgumentDescs = &argDesc;
			desc.NodeMask = 0;

			mDevice.CreateCommandSignature(&desc, null, ID3D12CommandSignature.IID, (void**)&mDispatchSignature);
		}
	}

	private void CreateBlitPipeline()
	{
		// Compile blit shaders via D3DCompile (SM 5.0)
		StringView vsSource = """
			struct VSOutput {
			    float4 Position : SV_Position;
			    float2 UV : TEXCOORD0;
			};
			VSOutput main(uint vertexId : SV_VertexID) {
			    VSOutput output;
			    output.UV = float2((vertexId << 1) & 2, vertexId & 2);
			    output.Position = float4(output.UV * float2(2, -2) + float2(-1, 1), 0, 1);
			    return output;
			}
			""";

		StringView psSource = """
			Texture2D srcTexture : register(t0);
			SamplerState srcSampler : register(s0);
			float4 main(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target {
			    return srcTexture.Sample(srcSampler, uv);
			}
			""";

		ID3DBlob* errorBlob = null;

		HRESULT hr = D3DCompile(
			vsSource.Ptr, (uint)vsSource.Length,
			null, null, null,
			(uint8*)"main", (uint8*)"vs_5_0",
			0, 0, &mBlitVsBlob, &errorBlob);

		if (!SUCCEEDED(hr))
		{
			if (errorBlob != null) errorBlob.Release();
			Console.Error.WriteLine("[DX12] ERROR: Failed to compile blit vertex shader");
			return;
		}
		if (errorBlob != null) { errorBlob.Release(); errorBlob = null; }

		hr = D3DCompile(
			psSource.Ptr, (uint)psSource.Length,
			null, null, null,
			(uint8*)"main", (uint8*)"ps_5_0",
			0, 0, &mBlitPsBlob, &errorBlob);

		if (!SUCCEEDED(hr))
		{
			if (errorBlob != null) errorBlob.Release();
			mBlitVsBlob.Release(); mBlitVsBlob = null;
			Console.Error.WriteLine("[DX12] ERROR: Failed to compile blit pixel shader");
			return;
		}
		if (errorBlob != null) { errorBlob.Release(); errorBlob = null; }

		mBlitVsBytecode.pShaderBytecode = mBlitVsBlob.GetBufferPointer();
		mBlitVsBytecode.BytecodeLength = mBlitVsBlob.GetBufferSize();
		mBlitPsBytecode.pShaderBytecode = mBlitPsBlob.GetBufferPointer();
		mBlitPsBytecode.BytecodeLength = mBlitPsBlob.GetBufferSize();

		// Create root signature: 1 SRV descriptor table (t0) + 1 static linear sampler (s0)
		D3D12_DESCRIPTOR_RANGE srvRange = .();
		srvRange.RangeType = .D3D12_DESCRIPTOR_RANGE_TYPE_SRV;
		srvRange.NumDescriptors = 1;
		srvRange.BaseShaderRegister = 0;
		srvRange.RegisterSpace = 0;
		srvRange.OffsetInDescriptorsFromTableStart = 0;

		D3D12_ROOT_PARAMETER rootParam = .();
		rootParam.ParameterType = .D3D12_ROOT_PARAMETER_TYPE_DESCRIPTOR_TABLE;
		rootParam.ShaderVisibility = .D3D12_SHADER_VISIBILITY_PIXEL;
		rootParam.DescriptorTable.NumDescriptorRanges = 1;
		rootParam.DescriptorTable.pDescriptorRanges = &srvRange;

		D3D12_STATIC_SAMPLER_DESC staticSampler = .();
		staticSampler.Filter = .D3D12_FILTER_MIN_MAG_MIP_LINEAR;
		staticSampler.AddressU = .D3D12_TEXTURE_ADDRESS_MODE_CLAMP;
		staticSampler.AddressV = .D3D12_TEXTURE_ADDRESS_MODE_CLAMP;
		staticSampler.AddressW = .D3D12_TEXTURE_ADDRESS_MODE_CLAMP;
		staticSampler.MipLODBias = 0;
		staticSampler.MaxAnisotropy = 1;
		staticSampler.ComparisonFunc = .D3D12_COMPARISON_FUNC_NEVER;
		staticSampler.BorderColor = .D3D12_STATIC_BORDER_COLOR_TRANSPARENT_BLACK;
		staticSampler.MinLOD = 0;
		staticSampler.MaxLOD = float.MaxValue;
		staticSampler.ShaderRegister = 0;
		staticSampler.RegisterSpace = 0;
		staticSampler.ShaderVisibility = .D3D12_SHADER_VISIBILITY_PIXEL;

		D3D12_ROOT_SIGNATURE_DESC rsDesc = .();
		rsDesc.NumParameters = 1;
		rsDesc.pParameters = &rootParam;
		rsDesc.NumStaticSamplers = 1;
		rsDesc.pStaticSamplers = &staticSampler;
		rsDesc.Flags = .D3D12_ROOT_SIGNATURE_FLAG_NONE;

		ID3DBlob* signatureBlob = null;
		hr = D3D12SerializeRootSignature(&rsDesc, .D3D_ROOT_SIGNATURE_VERSION_1, &signatureBlob, &errorBlob);
		if (!SUCCEEDED(hr))
		{
			if (errorBlob != null) errorBlob.Release();
			if (signatureBlob != null) signatureBlob.Release();
			Console.Error.WriteLine("[DX12] ERROR: Failed to serialize blit root signature");
			return;
		}
		if (errorBlob != null) { errorBlob.Release(); errorBlob = null; }

		hr = mDevice.CreateRootSignature(
			0,
			signatureBlob.GetBufferPointer(),
			signatureBlob.GetBufferSize(),
			ID3D12RootSignature.IID,
			(void**)&mBlitRootSignature);

		signatureBlob.Release();

		if (!SUCCEEDED(hr))
		{
			mBlitRootSignature = null;
			Console.Error.WriteLine("[DX12] ERROR: Failed to create blit root signature");
		}
	}
}
