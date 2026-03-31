namespace RendererFramework;

using System;
using Sedulous.RHI;
using Sedulous.RenderGraph;
using Sedulous.Renderer;
using Sedulous.Core.Mathematics;
using Sedulous.Shell.Input;
using cimgui_Beef;

using internal Sedulous.Renderer;

/// Orthographic projection for ImGui rendering.
[CRepr]
struct ImGuiUniforms
{
	public Matrix Projection;
}

/// ImGui integration as a render feature.
/// Renders the ImGui draw list on top of the backbuffer after all other passes.
///
/// Usage in Application:
///   OnUpdate():
///     mImGui.BeginFrame(width, height, deltaTime);
///     mImGui.UpdateInput(inputManager);
///     // ... build UI with igBegin/igEnd etc. ...
///     mImGui.EndFrame();
///   The feature's OnAddPasses handles GPU rendering.
public class ImGuiFeature : IRenderFeature
{
	private IDevice mDevice;
	private IQueue mQueue;
	private RenderSystem mSystem;

	// ImGui context
	private ImGuiContext* mContext;
	private ImGuiIO* mIO;

	// GPU resources (per-frame for multi-buffering)
	private IBuffer[RenderConfig.FrameBufferCount] mVertexBuffers;
	private IBuffer[RenderConfig.FrameBufferCount] mIndexBuffers;
	private IBuffer[RenderConfig.FrameBufferCount] mUniformBuffers;
	private void*[RenderConfig.FrameBufferCount] mUniformPtrs;
	private ITexture mFontTexture;
	private ITextureView mFontTextureView;
	private ISampler mFontSampler;
	private IBindGroupLayout mBindGroupLayout;
	private IBindGroup[RenderConfig.FrameBufferCount] mBindGroups;
	private uint32 mTextureGeneration;  // incremented on texture create/update
	private uint32[RenderConfig.FrameBufferCount] mBindGroupGeneration;  // tracks which generation each bind group was built for
	private IPipelineLayout mPipelineLayout;
	private IRenderPipeline mPipeline;
	private ShaderLibrary mShaderLib;

	// Persistently mapped vertex/index buffer pointers
	private void*[RenderConfig.FrameBufferCount] mVertexPtrs;
	private void*[RenderConfig.FrameBufferCount] mIndexPtrs;

	// Buffer sizes
	private const int MAX_VERTEX_BUFFER = 512 * 1024;
	private const int MAX_INDEX_BUFFER = 128 * 1024;

	// Frame state
	private int32 mTotalVtxCount;
	private int32 mTotalIdxCount;
	private bool mFrameStarted;

	// Swapchain format (needed for pipeline creation)
	private TextureFormat mSwapChainFormat = .BGRA8Unorm;

	public StringView Name => "ImGui";

	/// Sets the swapchain format. Call before Initialize.
	public void SetSwapChainFormat(TextureFormat format) { mSwapChainFormat = format; }

	/// Sets the graphics queue for runtime texture uploads. Call before first frame.
	public void SetQueue(IQueue queue) { mQueue = queue; }

	/// Gets the ImGui IO for direct access (e.g., checking WantCaptureMouse).
	public ImGuiIO* IO => mIO;

	public Result<void> OnInitialize(InitContext initCtx)
	{
		mDevice = initCtx.Device;
		mSystem = initCtx.System;

		// Create ImGui context
		mContext = igCreateContext(null);
		mIO = igGetIO_Nil();

		mIO.ConfigFlags |= (.)ImGuiConfigFlags.ImGuiConfigFlags_DockingEnable;
		mIO.BackendFlags |= (.)ImGuiBackendFlags.ImGuiBackendFlags_RendererHasTextures;
		mIO.IniFilename = null;
		mIO.Fonts.TexDesiredFormat = .ImTextureFormat_RGBA32;

		ImFontAtlas_AddFontDefault(mIO.Fonts, null);

		// Register shader
		if (initCtx.Shaders.RegisterShader("imgui") case .Err)
			return .Err;

		mShaderLib = initCtx.Shaders;

		// Create GPU resources (pipeline deferred until swapchain format is known)
		if (CreateBuffers() case .Err)
			return .Err;
		if (CreateBindGroupLayout() case .Err)
			return .Err;

		return .Ok;
	}

	private Result<void> CreateBuffers()
	{
		for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			let vbResult = mDevice.CreateBuffer(BufferDesc()
			{
				Size = MAX_VERTEX_BUFFER,
				Usage = .Vertex,
				Memory = .CpuToGpu,
				Label = "ImGui_VertexBuffer"
			});
			if (vbResult case .Err) return .Err;
			mVertexBuffers[i] = vbResult.Value;
			mVertexPtrs[i] = mVertexBuffers[i].Map();

			let ibResult = mDevice.CreateBuffer(BufferDesc()
			{
				Size = MAX_INDEX_BUFFER,
				Usage = .Index,
				Memory = .CpuToGpu,
				Label = "ImGui_IndexBuffer"
			});
			if (ibResult case .Err) return .Err;
			mIndexBuffers[i] = ibResult.Value;
			mIndexPtrs[i] = mIndexBuffers[i].Map();

			let ubResult = mDevice.CreateBuffer(BufferDesc()
			{
				Size = (uint64)sizeof(ImGuiUniforms),
				Usage = .Uniform,
				Memory = .CpuToGpu,
				Label = "ImGui_Uniforms"
			});
			if (ubResult case .Err) return .Err;
			mUniformBuffers[i] = ubResult.Value;
			mUniformPtrs[i] = mUniformBuffers[i].Map();
		}

		// Font sampler
		let samplerResult = mDevice.CreateSampler(SamplerDesc()
		{
			MinFilter = .Linear,
			MagFilter = .Linear,
			MipmapFilter = .Linear,
			AddressU = .ClampToEdge,
			AddressV = .ClampToEdge,
			AddressW = .ClampToEdge,
			Label = "ImGui_FontSampler"
		});
		if (samplerResult case .Err) return .Err;
		mFontSampler = samplerResult.Value;

		return .Ok;
	}

	private Result<void> CreateBindGroupLayout()
	{
		// Bind group layout: uniform buffer + texture + sampler
		BindGroupLayoutEntry[3] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex),         // b0: projection
			BindGroupLayoutEntry.SampledTexture(1, .Fragment),      // t1: font texture
			BindGroupLayoutEntry.Sampler(2, .Fragment)              // s2: font sampler
		);
		let layoutResult = mDevice.CreateBindGroupLayout(BindGroupLayoutDesc()
		{
			Entries = layoutEntries,
			Label = "ImGui_BindGroupLayout"
		});
		if (layoutResult case .Err) return .Err;
		mBindGroupLayout = layoutResult.Value;

		// Pipeline layout (single bind group)
		IBindGroupLayout[1] layouts = .(mBindGroupLayout);
		let pipeLayoutResult = mDevice.CreatePipelineLayout(PipelineLayoutDesc()
		{
			BindGroupLayouts = layouts,
			Label = "ImGui_PipelineLayout"
		});
		if (pipeLayoutResult case .Err) return .Err;
		mPipelineLayout = pipeLayoutResult.Value;

		return .Ok;
	}

	/// Creates the render pipeline on first use (deferred until swapchain format is set).
	private void EnsurePipeline()
	{
		if (mPipeline != null || mShaderLib == null) return;

		let vsResult = mShaderLib.GetCompiledShader("imgui", .Vertex);
		if (vsResult case .Err) return;
		let psResult = mShaderLib.GetCompiledShader("imgui", .Fragment);
		if (psResult case .Err) return;

		VertexAttribute[3] attrs = .(
			.() { Format = .Float32x2, Offset = 0, ShaderLocation = 0 },
			.() { Format = .Float32x2, Offset = 8, ShaderLocation = 1 },
			.() { Format = .Unorm8x4, Offset = 16, ShaderLocation = 2 }
		);
		VertexBufferLayout[1] vertexLayouts = .(
			.() { Stride = (uint32)sizeof(ImDrawVert), Attributes = Span<VertexAttribute>(&attrs[0], 3) }
		);

		var colorTarget = ColorTargetState()
		{
			Format = mSwapChainFormat,
			Blend = BlendState()
			{
				Color = BlendComponent()
				{
					SrcFactor = .SrcAlpha,
					DstFactor = .OneMinusSrcAlpha,
					Operation = .Add
				},
				Alpha = BlendComponent()
				{
					SrcFactor = .One,
					DstFactor = .OneMinusSrcAlpha,
					Operation = .Add
				}
			}
		};

		let pipeResult = mDevice.CreateRenderPipeline(RenderPipelineDesc()
		{
			Layout = mPipelineLayout,
			Vertex = .() { Shader = .(vsResult.Value, "VSMain"), Buffers = vertexLayouts },
			Fragment = .() { Shader = .(psResult.Value, "PSMain"), Targets = Span<ColorTargetState>(&colorTarget, 1) },
			Primitive = PrimitiveState() { Topology = .TriangleList, CullMode = .None },
			Label = "ImGui_Pipeline"
		});
		if (pipeResult case .Ok(let p))
			mPipeline = p;
	}

	/// Starts a new ImGui frame. Call at the beginning of OnUpdate.
	public void BeginFrame(float width, float height, float deltaTime)
	{
		mIO.DisplaySize = .() { x = width, y = height };
		mIO.DeltaTime = (deltaTime > 0) ? deltaTime : 1.0f / 60.0f;
		igNewFrame();
		mFrameStarted = true;
	}

	/// Forwards input events to ImGui. Call after BeginFrame.
	public void UpdateInput(IInputManager input)
	{
		let mouse = input.Mouse;
		let keyboard = input.Keyboard;

		ImGuiIO_AddMousePosEvent(mIO, mouse.X, mouse.Y);
		ImGuiIO_AddMouseButtonEvent(mIO, 0, mouse.IsButtonDown(.Left));
		ImGuiIO_AddMouseButtonEvent(mIO, 1, mouse.IsButtonDown(.Right));
		ImGuiIO_AddMouseButtonEvent(mIO, 2, mouse.IsButtonDown(.Middle));
		if (mouse.ScrollY != 0)
			ImGuiIO_AddMouseWheelEvent(mIO, 0, mouse.ScrollY);

		ImGuiIO_AddKeyEvent(mIO, .ImGuiMod_Ctrl, keyboard.IsKeyDown(.LeftCtrl) || keyboard.IsKeyDown(.RightCtrl));
		ImGuiIO_AddKeyEvent(mIO, .ImGuiMod_Shift, keyboard.IsKeyDown(.LeftShift) || keyboard.IsKeyDown(.RightShift));
		ImGuiIO_AddKeyEvent(mIO, .ImGuiMod_Alt, keyboard.IsKeyDown(.LeftAlt) || keyboard.IsKeyDown(.RightAlt));

		ImGuiIO_AddKeyEvent(mIO, .ImGuiKey_Tab, keyboard.IsKeyDown(.Tab));
		ImGuiIO_AddKeyEvent(mIO, .ImGuiKey_LeftArrow, keyboard.IsKeyDown(.Left));
		ImGuiIO_AddKeyEvent(mIO, .ImGuiKey_RightArrow, keyboard.IsKeyDown(.Right));
		ImGuiIO_AddKeyEvent(mIO, .ImGuiKey_UpArrow, keyboard.IsKeyDown(.Up));
		ImGuiIO_AddKeyEvent(mIO, .ImGuiKey_DownArrow, keyboard.IsKeyDown(.Down));
		ImGuiIO_AddKeyEvent(mIO, .ImGuiKey_Delete, keyboard.IsKeyDown(.Delete));
		ImGuiIO_AddKeyEvent(mIO, .ImGuiKey_Backspace, keyboard.IsKeyDown(.Backspace));
		ImGuiIO_AddKeyEvent(mIO, .ImGuiKey_Enter, keyboard.IsKeyDown(.Return));
		ImGuiIO_AddKeyEvent(mIO, .ImGuiKey_Escape, keyboard.IsKeyDown(.Escape));

		ImGuiIO_AddKeyEvent(mIO, .ImGuiKey_A, keyboard.IsKeyDown(.A));
		ImGuiIO_AddKeyEvent(mIO, .ImGuiKey_C, keyboard.IsKeyDown(.C));
		ImGuiIO_AddKeyEvent(mIO, .ImGuiKey_V, keyboard.IsKeyDown(.V));
		ImGuiIO_AddKeyEvent(mIO, .ImGuiKey_X, keyboard.IsKeyDown(.X));
		ImGuiIO_AddKeyEvent(mIO, .ImGuiKey_Y, keyboard.IsKeyDown(.Y));
		ImGuiIO_AddKeyEvent(mIO, .ImGuiKey_Z, keyboard.IsKeyDown(.Z));
	}

	/// Ends the ImGui frame and finalizes draw data. Call after building UI.
	/// Note: vertex/index upload is deferred to RenderDrawData (after BeginFrame
	/// sets the correct FrameIndex). EndFrame only calls igRender() and handles
	/// texture updates.
	public void EndFrame()
	{
		if (!mFrameStarted) return;
		igRender();
		mFrameStarted = false;

		ImDrawData* drawData = igGetDrawData();
		if (drawData == null || !drawData.Valid)
		{
			mTotalVtxCount = 0;
			mTotalIdxCount = 0;
			return;
		}

		// Handle font texture creation/updates
		if (drawData.Textures != null)
		{
			let texList = drawData.Textures;
			for (int32 i = 0; i < texList.Size; i++)
			{
				ImTextureData* tex = texList.Data[i];
				if (tex != null && tex.Status != .ImTextureStatus_OK && tex.Status != .ImTextureStatus_Destroyed)
					HandleTextureUpdate(tex);
			}
		}

		mTotalVtxCount = drawData.TotalVtxCount;
		mTotalIdxCount = drawData.TotalIdxCount;
	}

	/// Uploads vertex/index/uniform data for the current frame.
	/// Called from RenderDrawData after BeginFrame has set the correct FrameIndex.
	private void UploadDrawData(int frameIndex)
	{
		ImDrawData* drawData = igGetDrawData();
		if (drawData == null || !drawData.Valid) return;

		float width = drawData.DisplaySize.x;
		float height = drawData.DisplaySize.y;
		if (width <= 0 || height <= 0) return;

		// Update projection matrix
		let projection = Matrix.CreateOrthographicOffCenter(0, width, height, 0, -1.0f, 1.0f);
		ImGuiUniforms uniforms = .() { Projection = projection };
		if (mUniformPtrs[frameIndex] != null)
			Internal.MemCpy(mUniformPtrs[frameIndex], &uniforms, sizeof(ImGuiUniforms));

		if (mTotalVtxCount == 0 || mTotalIdxCount == 0) return;

		let vtxMap = mVertexPtrs[frameIndex];
		let idxMap = mIndexPtrs[frameIndex];
		if (vtxMap == null || idxMap == null) return;

		uint64 vtxOffset = 0;
		uint64 idxOffset = 0;
		for (int32 n = 0; n < drawData.CmdListsCount; n++)
		{
			ImDrawList* cmdList = drawData.CmdLists.Data[n];
			int vtxSize = cmdList.VtxBuffer.Size * sizeof(ImDrawVert);
			int idxSize = cmdList.IdxBuffer.Size * sizeof(uint16);

			if (vtxOffset + (uint64)vtxSize <= MAX_VERTEX_BUFFER)
				Internal.MemCpy((uint8*)vtxMap + vtxOffset, cmdList.VtxBuffer.Data, vtxSize);
			if (idxOffset + (uint64)idxSize <= MAX_INDEX_BUFFER)
				Internal.MemCpy((uint8*)idxMap + idxOffset, cmdList.IdxBuffer.Data, idxSize);

			vtxOffset += (uint64)vtxSize;
			idxOffset += (uint64)idxSize;
		}
	}

	/// Whether ImGui wants to capture mouse input (UI is hovered).
	public bool WantCaptureMouse => mIO != null && mIO.WantCaptureMouse;

	/// Whether ImGui wants to capture keyboard input (text input active).
	public bool WantCaptureKeyboard => mIO != null && mIO.WantCaptureKeyboard;

	public void OnAddPasses(RenderGraph graph, FrameContext frameCtx, ViewContext viewCtx)
	{
		EnsurePipeline();
		if (mTotalVtxCount == 0 || mFontTextureView == null || mPipeline == null) return;

		let renderTarget = viewCtx.RenderTarget;
		if (!renderTarget.IsValid) return;

		let renderW = viewCtx.RenderWidth;
		let renderH = viewCtx.RenderHeight;
		let frameIndex = mSystem.FrameIndex;

		graph.AddPass("ImGui", .Graphics, scope [&] (builder) =>
		{
			// WriteRenderTarget with Load creates a read-after-write dependency
			// on the previous writer (blit/tonemap), ensuring correct ordering.
			builder.WriteRenderTarget(renderTarget, 0, .Load, .Store);
			builder.HasSideEffects();

			let graphPass = builder.Pass;
			builder.SetExecute(new [=] (encoder, registry) =>
			{
				let rpDesc = registry.GetRenderPassDesc(graphPass);
				let rp = encoder.BeginRenderPass(rpDesc);

				rp.SetViewport(0, 0, (float)renderW, (float)renderH, 0.0f, 1.0f);
				rp.SetScissor(0, 0, renderW, renderH);

				RenderDrawData(rp, frameIndex);

				rp.End();
			});
		});
	}

	private void RenderDrawData(IRenderPassEncoder rp, int frameIndex)
	{
		// Upload vertex/index/uniform data using the correct FrameIndex
		// (set by BeginFrame, which runs after OnUpdate/EndFrame).
		UploadDrawData(frameIndex);

		ImDrawData* drawData = igGetDrawData();
		if (drawData == null || !drawData.Valid || mTotalVtxCount == 0 || mFontTextureView == null)
			return;

		// Lazily rebuild bind group when texture has changed (generation mismatch).
		if (mBindGroups[frameIndex] == null || mBindGroupGeneration[frameIndex] != mTextureGeneration)
		{
			if (mBindGroups[frameIndex] != null)
				mDevice.DestroyBindGroup(ref mBindGroups[frameIndex]);

			BindGroupEntry[3] entries = .(
				BindGroupEntry.Buffer(mUniformBuffers[frameIndex], 0, (uint64)sizeof(ImGuiUniforms)),
				BindGroupEntry.Texture(mFontTextureView),
				BindGroupEntry.Sampler(mFontSampler)
			);
			let bgResult = mDevice.CreateBindGroup(BindGroupDesc()
			{
				Layout = mBindGroupLayout,
				Entries = entries,
				Label = "ImGui_BindGroup"
			});
			if (bgResult case .Err) return;
			mBindGroups[frameIndex] = bgResult.Value;
			mBindGroupGeneration[frameIndex] = mTextureGeneration;
		}

		rp.SetPipeline(mPipeline);
		rp.SetBindGroup(0, mBindGroups[frameIndex]);
		rp.SetVertexBuffer(0, mVertexBuffers[frameIndex], 0);
		rp.SetIndexBuffer(mIndexBuffers[frameIndex], .UInt16, 0);

		int32 globalVtxOffset = 0;
		int32 globalIdxOffset = 0;
		ImVec2 clipOff = drawData.DisplayPos;

		for (int32 n = 0; n < drawData.CmdListsCount; n++)
		{
			ImDrawList* cmdList = drawData.CmdLists.Data[n];

			for (int32 cmdIdx = 0; cmdIdx < cmdList.CmdBuffer.Size; cmdIdx++)
			{
				ImDrawCmd* cmd = &cmdList.CmdBuffer.Data[cmdIdx];
				if (cmd.ElemCount == 0) continue;

				let clipX = Math.Max(0, (int32)(cmd.ClipRect.x - clipOff.x));
				let clipY = Math.Max(0, (int32)(cmd.ClipRect.y - clipOff.y));
				let clipW = (uint32)(cmd.ClipRect.z - cmd.ClipRect.x);
				let clipH = (uint32)(cmd.ClipRect.w - cmd.ClipRect.y);

				if (clipW > 0 && clipH > 0)
				{
					rp.SetScissor(clipX, clipY, clipW, clipH);
					rp.DrawIndexed(cmd.ElemCount, 1,
						(uint32)(cmd.IdxOffset + (uint32)globalIdxOffset),
						(int32)(cmd.VtxOffset + (uint32)globalVtxOffset), 0);
				}
			}

			globalVtxOffset += cmdList.VtxBuffer.Size;
			globalIdxOffset += cmdList.IdxBuffer.Size;
		}
	}

	private void HandleTextureUpdate(ImTextureData* tex)
	{
		if (tex.Status == .ImTextureStatus_WantCreate)
		{
			void* pixels = ImTextureData_GetPixels(tex);
			if (pixels == null) return;

			// Defer destruction of old texture (may be referenced by in-flight frames).
			// Don't touch bind groups here — they're rebuilt lazily via generation tracking.
			let deletionQueue = mSystem.DeferredDeletions;
			let frameNum = (uint64)mSystem.FrameCtx.FrameNumber;
			if (mFontTextureView != null)
			{
				deletionQueue.Enqueue(frameNum, mFontTextureView);
				mFontTextureView = null;
			}
			if (mFontTexture != null)
			{
				deletionQueue.Enqueue(frameNum, mFontTexture);
				mFontTexture = null;
			}

			uint32 w = (uint32)tex.Width;
			uint32 h = (uint32)tex.Height;

			// Create texture
			let texResult = mDevice.CreateTexture(TextureDesc.Tex2D(
				.RGBA8Unorm, w, h, .Sampled | .CopyDst, label: "ImGui_FontTexture"));
			if (texResult case .Err) return;
			mFontTexture = texResult.Value;

			// Upload pixel data via transfer batch
			if (mQueue != null)
			{
				let batch = mQueue.CreateTransferBatch();
				if (batch case .Ok(let tb))
				{
					let dataLayout = TextureDataLayout() { Offset = 0, BytesPerRow = w * 4, RowsPerImage = h };
					let extent = Extent3D(w, h, 1);
					tb.WriteTexture(mFontTexture, Span<uint8>((uint8*)pixels, (int)(w * h * 4)), dataLayout, extent);
					tb.Submit();
					var tbRef = tb;
					mQueue.DestroyTransferBatch(ref tbRef);
				}
			}

			// Create texture view
			let viewResult = mDevice.CreateTextureView(mFontTexture, TextureViewDesc()
			{
				Label = "ImGui_FontTextureView"
			});
			if (viewResult case .Err) return;
			mFontTextureView = viewResult.Value;

			// Bump generation — bind groups will be rebuilt lazily in RenderDrawData
			// when the current frame actually needs them (safe for in-flight frames).
			mTextureGeneration++;

			ImTextureData_SetTexID(tex, 1);
			ImTextureData_SetStatus(tex, .ImTextureStatus_OK);
		}
		else if (tex.Status == .ImTextureStatus_WantUpdates)
		{
			// Treat updates as full recreate — writing to the in-use texture would
			// race with in-flight frames reading it. Create a new texture instead.
			void* pixels = ImTextureData_GetPixels(tex);
			if (pixels != null && tex.Width > 0 && tex.Height > 0 && mQueue != null)
			{
				uint32 w = (uint32)tex.Width;
				uint32 h = (uint32)tex.Height;

				// Defer old texture
				let deletionQueue = mSystem.DeferredDeletions;
				let frameNum = (uint64)mSystem.FrameCtx.FrameNumber;
				if (mFontTextureView != null) { deletionQueue.Enqueue(frameNum, mFontTextureView); mFontTextureView = null; }
				if (mFontTexture != null) { deletionQueue.Enqueue(frameNum, mFontTexture); mFontTexture = null; }

				// Create new texture + upload
				let texResult = mDevice.CreateTexture(TextureDesc.Tex2D(
					.RGBA8Unorm, w, h, .Sampled | .CopyDst, label: "ImGui_FontTexture"));
				if (texResult case .Ok(let newTex))
				{
					mFontTexture = newTex;
					let batch = mQueue.CreateTransferBatch();
					if (batch case .Ok(let tb))
					{
						let dataLayout = TextureDataLayout() { Offset = 0, BytesPerRow = w * 4, RowsPerImage = h };
						let extent = Extent3D(w, h, 1);
						tb.WriteTexture(mFontTexture, Span<uint8>((uint8*)pixels, (int)(w * h * 4)), dataLayout, extent);
						tb.Submit();
						var tbRef = tb;
						mQueue.DestroyTransferBatch(ref tbRef);
					}
					let viewResult = mDevice.CreateTextureView(mFontTexture, TextureViewDesc() { Label = "ImGui_FontTextureView" });
					if (viewResult case .Ok(let view))
						mFontTextureView = view;
					mTextureGeneration++;
				}
			}
			ImTextureData_SetStatus(tex, .ImTextureStatus_OK);
		}
		else if (tex.Status == .ImTextureStatus_WantDestroy)
		{
			ImTextureData_SetTexID(tex, 0);
			ImTextureData_SetStatus(tex, .ImTextureStatus_Destroyed);
		}
	}

	public void OnPostRender() { }

	public void OnShutdown(IDevice device)
	{
		if (mPipeline != null) device.DestroyRenderPipeline(ref mPipeline);
		if (mPipelineLayout != null) device.DestroyPipelineLayout(ref mPipelineLayout);
		for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			if (mBindGroups[i] != null) device.DestroyBindGroup(ref mBindGroups[i]);
			if (mUniformBuffers[i] != null) { mUniformBuffers[i].Unmap(); mUniformPtrs[i] = null; device.DestroyBuffer(ref mUniformBuffers[i]); }
			if (mIndexBuffers[i] != null) { mIndexBuffers[i].Unmap(); mIndexPtrs[i] = null; device.DestroyBuffer(ref mIndexBuffers[i]); }
			if (mVertexBuffers[i] != null) { mVertexBuffers[i].Unmap(); mVertexPtrs[i] = null; device.DestroyBuffer(ref mVertexBuffers[i]); }
		}
		if (mBindGroupLayout != null) device.DestroyBindGroupLayout(ref mBindGroupLayout);
		if (mFontSampler != null) device.DestroySampler(ref mFontSampler);
		if (mFontTextureView != null) device.DestroyTextureView(ref mFontTextureView);
		if (mFontTexture != null) device.DestroyTexture(ref mFontTexture);

		if (mContext != null)
			igDestroyContext(mContext);
	}
}
