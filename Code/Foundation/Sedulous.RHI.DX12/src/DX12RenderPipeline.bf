namespace Sedulous.RHI.DX12;

using System;
using System.Collections;
using Win32;
using Win32.Graphics.Direct3D12;
using Win32.Graphics.Direct3D;
using Win32.Graphics.Dxgi.Common;
using Win32.Foundation;
using Sedulous.RHI;
using Sedulous.RHI.DX12.Internal;

/// DX12 implementation of IRenderPipeline.
class DX12RenderPipeline : IRenderPipeline
{
	private DX12Device mDevice;
	private ID3D12PipelineState* mPipelineState;
	private DX12PipelineLayout mLayout;
	private D3D_PRIMITIVE_TOPOLOGY mTopology;
	private uint32[8] mVertexStrides; // Per-slot vertex strides

	public this(DX12Device device, RenderPipelineDesc descriptor)
	{
		mDevice = device;
		for (int i = 0; i < 8; i++)
			mVertexStrides[i] = 0;

		if (let layout = descriptor.Layout as DX12PipelineLayout)
		{
			mLayout = layout;
			CreatePipeline(descriptor);
		}
	}

	public ~this()
	{
		Dispose();
	}

	public void Dispose()
	{
		if (mPipelineState != null)
		{
			mPipelineState.Release();
			mPipelineState = null;
		}
	}

	public bool IsValid => mPipelineState != null;
	public IPipelineLayout Layout => mLayout;
	public ID3D12PipelineState* PipelineState => mPipelineState;
	public ID3D12RootSignature* RootSignature => mLayout?.RootSignature;
	public DX12PipelineLayout PipelineLayout => mLayout;
	public D3D_PRIMITIVE_TOPOLOGY Topology => mTopology;

	/// Gets the vertex stride for a given buffer slot.
	public uint32 GetVertexStride(uint32 slot)
	{
		if (slot < 8)
			return mVertexStrides[slot];
		return 0;
	}

	private void CreatePipeline(RenderPipelineDesc descriptor)
	{
		if (mLayout == null)
			return;

		D3D12_GRAPHICS_PIPELINE_STATE_DESC desc = .();
		desc.pRootSignature = mLayout.RootSignature;

		// ===== Shader stages =====

		// Vertex shader (required)
		let vsModule = descriptor.Vertex.Shader.Module as DX12ShaderModule;
		if (vsModule == null)
			return;
		desc.VS = vsModule.GetBytecode();

		// Fragment shader (optional — depth-only passes may not have one)
		if (descriptor.Fragment.HasValue)
		{
			let fs = descriptor.Fragment.Value;
			if (let fsModule = fs.Shader.Module as DX12ShaderModule)
				desc.PS = fsModule.GetBytecode();
		}

		// ===== Input layout =====
		BuildInputLayout(descriptor, ref desc);

		// ===== Primitive topology =====
		mTopology = DX12Conversions.ToDx12Topology(descriptor.Primitive.Topology);
		desc.PrimitiveTopologyType = DX12Conversions.ToDx12TopologyType(descriptor.Primitive.Topology);

		// ===== Rasterizer state =====
		desc.RasterizerState = BuildRasterizerState(descriptor);

		// ===== Blend state =====
		desc.BlendState = BuildBlendState(descriptor);

		// ===== Depth/stencil state =====
		if (descriptor.DepthStencil.HasValue)
		{
			let ds = descriptor.DepthStencil.Value;
			desc.DepthStencilState = BuildDepthStencilState(ds);
			desc.DSVFormat = DX12Conversions.GetDepthDsvFormat(ds.Format);
		}
		else
		{
			desc.DepthStencilState.DepthEnable = FALSE;
			desc.DepthStencilState.StencilEnable = FALSE;
			desc.DSVFormat = .DXGI_FORMAT_UNKNOWN;
		}

		// ===== Render target formats =====
		if (descriptor.Fragment.HasValue)
		{
			let targets = descriptor.Fragment.Value.Targets;
			desc.NumRenderTargets = (uint32)Math.Min(targets.Length, 8);
			for (int i = 0; i < desc.NumRenderTargets; i++)
				desc.RTVFormats[i] = DX12Conversions.ToDxgiFormat(targets[i].Format);
		}

		// ===== Multisample =====
		desc.SampleDesc.Count = descriptor.Multisample.Count;
		desc.SampleDesc.Quality = 0;
		desc.SampleMask = descriptor.Multisample.Mask;

		// ===== Other =====
		desc.NodeMask = 0;
		desc.Flags = .D3D12_PIPELINE_STATE_FLAG_NONE;
		desc.IBStripCutValue = .D3D12_INDEX_BUFFER_STRIP_CUT_VALUE_DISABLED;

		HRESULT hr = mDevice.NativeDevice.CreateGraphicsPipelineState(
			&desc,
			ID3D12PipelineState.IID,
			(void**)&mPipelineState);

		if (!SUCCEEDED(hr))
			mPipelineState = null;

		// Clean up input layout elements
		if (desc.InputLayout.pInputElementDescs != null)
		{
			let elements = (D3D12_INPUT_ELEMENT_DESC*)desc.InputLayout.pInputElementDescs;
			for (uint32 i = 0; i < desc.InputLayout.NumElements; i++)
			{
				if (elements[i].SemanticName != null)
					delete (char8*)elements[i].SemanticName;
			}
			delete elements;
		}
	}

	/// Parsed input signature parameter from DXIL/DXBC container.
	struct InputSignatureParam
	{
		public char8* SemanticName; // Points into parsed bytecode — do NOT free
		public uint32 SemanticIndex;
		public uint32 Register;
	}

	/// Parses the DXIL/DXBC container to extract the input signature (ISGN/ISG1 chunk).
	/// Returns the number of parameters found, or 0 on failure.
	private static int ParseInputSignature(Span<uint8> bytecode, ref InputSignatureParam[16] outParams)
	{
		if (bytecode.Length < 32)
			return 0;

		// Verify DXBC magic: 'DXBC' = 0x44 0x58 0x42 0x43
		if (bytecode[0] != 0x44 || bytecode[1] != 0x58 ||
			bytecode[2] != 0x42 || bytecode[3] != 0x43)
			return 0;

		uint32 partCount = *(uint32*)(bytecode.Ptr + 28);
		if (32 + partCount * 4 > (uint32)bytecode.Length)
			return 0;

		for (uint32 i = 0; i < partCount; i++)
		{
			uint32 partOffset = *(uint32*)(bytecode.Ptr + 32 + i * 4);
			if (partOffset + 8 > (uint32)bytecode.Length)
				continue;

			uint32 fourCC = *(uint32*)(bytecode.Ptr + partOffset);
			uint32 partSize = *(uint32*)(bytecode.Ptr + partOffset + 4);

			// ISGN = 0x4E475349, ISG1 = 0x31475349
			bool isISGN = fourCC == 0x4E475349;
			bool isISG1 = fourCC == 0x31475349;
			if (!isISGN && !isISG1)
				continue;

			uint8* data = bytecode.Ptr + partOffset + 8;
			if (partOffset + 8 + partSize > (uint32)bytecode.Length)
				return 0;

			uint32 paramCount = *(uint32*)data;
			// Bytes 4-7: reserved (usually 8)
			uint32 paramStride = isISG1 ? 32 : 24; // ISG1 adds MinPrecision + Stream fields
			int count = 0;

			for (uint32 j = 0; j < paramCount && count < 16; j++)
			{
				uint8* paramData = data + 8 + j * paramStride;

				// ISG1 has Stream (uint32) at offset 0, shifting all fields by 4
				// ISGN layout: nameOffset(0) semanticIndex(4) sysVal(8) compType(12) register(16) mask(20)
				// ISG1 layout: stream(0) nameOffset(4) semanticIndex(8) sysVal(12) compType(16) register(20) mask(24) minPrec(28)
				uint32 baseOffset = isISG1 ? 4 : 0;
				uint32 nameOffset = *(uint32*)(paramData + baseOffset);

				outParams[count].SemanticName = (char8*)(data + nameOffset);
				outParams[count].SemanticIndex = *(uint32*)(paramData + baseOffset + 4);
				outParams[count].Register = *(uint32*)(paramData + baseOffset + 16);
				count++;
			}

			return count;
		}

		return 0;
	}

	private void BuildInputLayout(RenderPipelineDesc descriptor, ref D3D12_GRAPHICS_PIPELINE_STATE_DESC desc)
	{
		let buffers = descriptor.Vertex.Buffers;
		if (buffers.Length == 0)
		{
			desc.InputLayout.pInputElementDescs = null;
			desc.InputLayout.NumElements = 0;
			return;
		}

		// Count total attributes
		int totalAttribs = 0;
		for (let buffer in buffers)
			totalAttribs += buffer.Attributes.Length;

		if (totalAttribs == 0)
		{
			desc.InputLayout.pInputElementDescs = null;
			desc.InputLayout.NumElements = 0;
			return;
		}

		// Parse vertex shader input signature for register→semantic mapping
		InputSignatureParam[16] sigParams = .();
		int sigParamCount = 0;

		let vsModule = descriptor.Vertex.Shader.Module as DX12ShaderModule;
		if (vsModule != null)
			sigParamCount = ParseInputSignature(vsModule.BytecodeSpan, ref sigParams);

		// Allocate elements (freed after CreateGraphicsPipelineState)
		D3D12_INPUT_ELEMENT_DESC* elements = new D3D12_INPUT_ELEMENT_DESC[totalAttribs]*;
		int elemIdx = 0;

		for (int bufIdx = 0; bufIdx < buffers.Length; bufIdx++)
		{
			let buffer = ref buffers[bufIdx];

			// Store vertex stride for SetVertexBuffer
			if (bufIdx < 8)
				mVertexStrides[bufIdx] = (uint32)buffer.Stride;

			for (let attrib in buffer.Attributes)
			{
				char8* semanticName = null;
				uint32 semanticIndex = 0;

				// Look up semantic from shader input signature by register
				bool found = false;
				for (int s = 0; s < sigParamCount; s++)
				{
					if (sigParams[s].Register == attrib.ShaderLocation)
					{
						// Copy semantic name string (freed after PSO creation)
						int len = Internal.CStrLen(sigParams[s].SemanticName);
						semanticName = new char8[len + 1]*;
						Internal.MemCpy(semanticName, sigParams[s].SemanticName, len);
						semanticName[len] = 0;
						semanticIndex = sigParams[s].SemanticIndex;
						found = true;
						break;
					}
				}

				// Fallback to hardcoded mapping if reflection failed
				if (!found)
				{
					String semanticStr = scope String();
					DX12Conversions.GetSemanticName(attrib.ShaderLocation, semanticStr, out semanticIndex);
					semanticName = new char8[semanticStr.Length + 1]*;
					Internal.MemCpy(semanticName, semanticStr.Ptr, semanticStr.Length);
					semanticName[semanticStr.Length] = 0;
				}

				D3D12_INPUT_ELEMENT_DESC element = .();
				element.SemanticName = (uint8*)semanticName;
				element.SemanticIndex = semanticIndex;
				element.Format = DX12Conversions.ToDxgiFormat(attrib.Format);
				element.InputSlot = (uint32)bufIdx;
				element.AlignedByteOffset = (uint32)attrib.Offset;
				element.InputSlotClass = (buffer.StepMode == .Instance)
					? .D3D12_INPUT_CLASSIFICATION_PER_INSTANCE_DATA
					: .D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA;
				element.InstanceDataStepRate = (buffer.StepMode == .Instance) ? 1 : 0;

				elements[elemIdx++] = element;
			}
		}

		desc.InputLayout.pInputElementDescs = elements;
		desc.InputLayout.NumElements = (uint32)elemIdx;
	}

	private D3D12_RASTERIZER_DESC BuildRasterizerState(RenderPipelineDesc descriptor)
	{
		D3D12_RASTERIZER_DESC raster = .();
		raster.FillMode = DX12Conversions.ToDx12FillMode(descriptor.Primitive.FillMode);
		raster.CullMode = DX12Conversions.ToDx12CullMode(descriptor.Primitive.CullMode);
		raster.FrontCounterClockwise = (descriptor.Primitive.FrontFace == .CCW) ? TRUE : FALSE;
		raster.DepthClipEnable = descriptor.Primitive.DepthClipEnabled ? TRUE : FALSE;
		raster.MultisampleEnable = (descriptor.Multisample.Count > 1) ? TRUE : FALSE;
		raster.AntialiasedLineEnable = FALSE;
		raster.ForcedSampleCount = 0;
		raster.ConservativeRaster = .D3D12_CONSERVATIVE_RASTERIZATION_MODE_OFF;

		// Depth bias from DepthStencilState
		if (descriptor.DepthStencil.HasValue)
		{
			let ds = descriptor.DepthStencil.Value;
			raster.DepthBias = ds.DepthBias;
			raster.DepthBiasClamp = ds.DepthBiasClamp;
			raster.SlopeScaledDepthBias = ds.DepthBiasSlopeScale;
		}
		else
		{
			raster.DepthBias = 0;
			raster.DepthBiasClamp = 0.0f;
			raster.SlopeScaledDepthBias = 0.0f;
		}

		return raster;
	}

	private D3D12_BLEND_DESC BuildBlendState(RenderPipelineDesc descriptor)
	{
		D3D12_BLEND_DESC blend = .();
		blend.AlphaToCoverageEnable = descriptor.Multisample.AlphaToCoverageEnabled ? TRUE : FALSE;
		blend.IndependentBlendEnable = TRUE; // Enable per-RT blending

		if (descriptor.Fragment.HasValue)
		{
			let targets = descriptor.Fragment.Value.Targets;
			for (int i = 0; i < Math.Min(targets.Length, 8); i++)
			{
				let target = ref targets[i];

				if (target.Blend.HasValue)
				{
					let bs = target.Blend.Value;
					blend.RenderTarget[i].BlendEnable = TRUE;
					blend.RenderTarget[i].SrcBlend = DX12Conversions.ToDx12Blend(bs.Color.SrcFactor);
					blend.RenderTarget[i].DestBlend = DX12Conversions.ToDx12Blend(bs.Color.DstFactor);
					blend.RenderTarget[i].BlendOp = DX12Conversions.ToDx12BlendOp(bs.Color.Operation);
					blend.RenderTarget[i].SrcBlendAlpha = DX12Conversions.ToDx12Blend(bs.Alpha.SrcFactor);
					blend.RenderTarget[i].DestBlendAlpha = DX12Conversions.ToDx12Blend(bs.Alpha.DstFactor);
					blend.RenderTarget[i].BlendOpAlpha = DX12Conversions.ToDx12BlendOp(bs.Alpha.Operation);
				}
				else
				{
					blend.RenderTarget[i].BlendEnable = FALSE;
				}

				blend.RenderTarget[i].RenderTargetWriteMask = (uint8)target.WriteMask;
			}
		}

		return blend;
	}

	private D3D12_DEPTH_STENCIL_DESC BuildDepthStencilState(DepthStencilState ds)
	{
		D3D12_DEPTH_STENCIL_DESC desc = .();
		desc.DepthEnable = ds.DepthTestEnabled ? TRUE : FALSE;
		desc.DepthWriteMask = ds.DepthWriteEnabled
			? .D3D12_DEPTH_WRITE_MASK_ALL
			: .D3D12_DEPTH_WRITE_MASK_ZERO;
		desc.DepthFunc = DX12Conversions.ToDx12CompareFunc(ds.DepthCompare);

		// Stencil — enabled if either face has non-default state
		bool hasStencil = (ds.StencilReadMask != 0xFF || ds.StencilWriteMask != 0xFF ||
			ds.StencilFront.Compare != .Always || ds.StencilBack.Compare != .Always ||
			ds.StencilFront.FailOp != .Keep || ds.StencilBack.FailOp != .Keep);

		desc.StencilEnable = hasStencil ? TRUE : FALSE;
		desc.StencilReadMask = (uint8)ds.StencilReadMask;
		desc.StencilWriteMask = (uint8)ds.StencilWriteMask;

		desc.FrontFace.StencilFailOp = DX12Conversions.ToDx12StencilOp(ds.StencilFront.FailOp);
		desc.FrontFace.StencilDepthFailOp = DX12Conversions.ToDx12StencilOp(ds.StencilFront.DepthFailOp);
		desc.FrontFace.StencilPassOp = DX12Conversions.ToDx12StencilOp(ds.StencilFront.PassOp);
		desc.FrontFace.StencilFunc = DX12Conversions.ToDx12CompareFunc(ds.StencilFront.Compare);

		desc.BackFace.StencilFailOp = DX12Conversions.ToDx12StencilOp(ds.StencilBack.FailOp);
		desc.BackFace.StencilDepthFailOp = DX12Conversions.ToDx12StencilOp(ds.StencilBack.DepthFailOp);
		desc.BackFace.StencilPassOp = DX12Conversions.ToDx12StencilOp(ds.StencilBack.PassOp);
		desc.BackFace.StencilFunc = DX12Conversions.ToDx12CompareFunc(ds.StencilBack.Compare);

		return desc;
	}
}
