namespace Sedulous.Engine.Renderer;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;

/// Batched sprite renderer for efficient billboard rendering.
/// Owns the sprite pipeline and handles rendering.
class SpriteRenderer
{
	private const int32 MAX_FRAMES = 2;

	private IDevice mDevice;
	private ShaderLibrary mShaderLibrary;

	// Buffers
	private IBuffer mInstanceBuffer;

	// Pipeline resources
	private IBindGroupLayout mBindGroupLayout ~ delete _;
	private IPipelineLayout mPipelineLayout ~ delete _;
	private IRenderPipeline mPipeline ~ delete _;
	private IBindGroup[MAX_FRAMES] mBindGroups ~ { for (var bg in _) delete bg; };

	// Per-frame camera buffers (references, not owned)
	private IBuffer[MAX_FRAMES] mCameraBuffers;

	// Sprite data
	private List<SpriteInstance> mSprites = new .() ~ delete _;
	private int32 mMaxSprites;
	private bool mDirty = false;

	// Configuration
	private TextureFormat mColorFormat = .BGRA8UnormSrgb;
	private TextureFormat mDepthFormat = .Depth24PlusStencil8;
	private bool mInitialized = false;

	/// Maximum number of sprites that can be rendered in one batch.
	public const int32 DEFAULT_MAX_SPRITES = 10000;

	public this(IDevice device, int32 maxSprites = DEFAULT_MAX_SPRITES)
	{
		mDevice = device;
		mMaxSprites = maxSprites;

		CreateBuffers();
	}

	public ~this()
	{
		if (mInstanceBuffer != null) delete mInstanceBuffer;
	}

	/// Initializes the sprite renderer with pipeline resources.
	public Result<void> Initialize(ShaderLibrary shaderLibrary,
		IBuffer[MAX_FRAMES] cameraBuffers, TextureFormat colorFormat, TextureFormat depthFormat)
	{
		if (mDevice == null)
			return .Err;

		mShaderLibrary = shaderLibrary;
		mCameraBuffers = cameraBuffers;
		mColorFormat = colorFormat;
		mDepthFormat = depthFormat;

		if (CreatePipeline() case .Err)
			return .Err;

		mInitialized = true;
		return .Ok;
	}

	private void CreateBuffers()
	{
		// Instance buffer (one SpriteInstance per sprite)
		let instanceSize = (uint64)(sizeof(SpriteInstance) * mMaxSprites);
		BufferDescriptor instanceDesc = .(instanceSize, .Vertex, .Upload);
		if (mDevice.CreateBuffer(&instanceDesc) case .Ok(let instBuf))
			mInstanceBuffer = instBuf;
	}

	private Result<void> CreatePipeline()
	{
		// Load sprite shaders
		let vertResult = mShaderLibrary.GetShader("sprite", .Vertex);
		if (vertResult case .Err)
			return .Err;
		let vertShader = vertResult.Get();

		let fragResult = mShaderLibrary.GetShader("sprite", .Fragment);
		if (fragResult case .Err)
			return .Err;
		let fragShader = fragResult.Get();

		// Bind group layout: b0=camera uniforms
		BindGroupLayoutEntry[1] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex)
		);
		BindGroupLayoutDescriptor bindLayoutDesc = .(layoutEntries);
		if (mDevice.CreateBindGroupLayout(&bindLayoutDesc) not case .Ok(let layout))
			return .Err;
		mBindGroupLayout = layout;

		// Pipeline layout
		IBindGroupLayout[1] layouts = .(mBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (mDevice.CreatePipelineLayout(&pipelineLayoutDesc) not case .Ok(let pipelineLayout))
			return .Err;
		mPipelineLayout = pipelineLayout;

		// Create per-frame bind groups
		for (int i = 0; i < MAX_FRAMES; i++)
		{
			BindGroupEntry[1] entries = .(
				BindGroupEntry.Buffer(0, mCameraBuffers[i])
			);
			BindGroupDescriptor bindGroupDesc = .(mBindGroupLayout, entries);
			if (mDevice.CreateBindGroup(&bindGroupDesc) not case .Ok(let group))
				return .Err;
			mBindGroups[i] = group;
		}

		// SpriteInstance layout: Position(12) + Size(8) + UVRect(16) + Color(4) = 40 bytes
		Sedulous.RHI.VertexAttribute[4] vertexAttrs = .(
			.(VertexFormat.Float3, 0, 0),              // Position
			.(VertexFormat.Float2, 12, 1),             // Size
			.(VertexFormat.Float4, 20, 2),             // UVRect
			.(VertexFormat.UByte4Normalized, 36, 3)    // Color
		);
		VertexBufferLayout[1] vertexBuffers = .(
			VertexBufferLayout(40, vertexAttrs, .Instance)
		);

		ColorTargetState[1] colorTargets = .(
			ColorTargetState(mColorFormat, .AlphaBlend)
		);

		DepthStencilState depthState = .();
		depthState.DepthTestEnabled = true;
		depthState.DepthWriteEnabled = false;
		depthState.DepthCompare = .Less;
		depthState.Format = mDepthFormat;

		RenderPipelineDescriptor pipelineDesc = .()
		{
			Layout = mPipelineLayout,
			Vertex = .()
			{
				Shader = .(vertShader.Module, "main"),
				Buffers = vertexBuffers
			},
			Fragment = .()
			{
				Shader = .(fragShader.Module, "main"),
				Targets = colorTargets
			},
			Primitive = .()
			{
				Topology = .TriangleList,
				FrontFace = .CCW,
				CullMode = .None
			},
			DepthStencil = depthState,
			Multisample = .()
			{
				Count = 1,
				Mask = uint32.MaxValue
			}
		};

		if (mDevice.CreateRenderPipeline(&pipelineDesc) not case .Ok(let pipeline))
			return .Err;
		mPipeline = pipeline;

		return .Ok;
	}

	/// Renders all sprites in the current batch.
	public void Render(IRenderPassEncoder renderPass, int32 frameIndex)
	{
		if (!mInitialized || mPipeline == null || mSprites.Count == 0)
			return;

		if (frameIndex < 0 || frameIndex >= MAX_FRAMES)
			return;

		renderPass.SetPipeline(mPipeline);
		renderPass.SetBindGroup(0, mBindGroups[frameIndex]);
		renderPass.SetVertexBuffer(0, mInstanceBuffer, 0);
		renderPass.Draw(6, (uint32)mSprites.Count, 0, 0);
	}

	/// Clears all sprites for a new frame.
	public void Begin()
	{
		mSprites.Clear();
		mDirty = true;
	}

	/// Adds a sprite to the batch.
	public void AddSprite(SpriteInstance sprite)
	{
		if (mSprites.Count < mMaxSprites)
		{
			mSprites.Add(sprite);
			mDirty = true;
		}
	}

	/// Adds a sprite with common parameters.
	public void AddSprite(Vector3 position, Vector2 size, Color color = .White)
	{
		AddSprite(.(position, size, color));
	}

	/// Uploads sprite data to GPU and prepares for rendering.
	public void End()
	{
		if (!mDirty || mSprites.Count == 0)
			return;

		// Upload instance data
		let dataSize = (uint64)(sizeof(SpriteInstance) * mSprites.Count);
		Span<uint8> data = .((uint8*)mSprites.Ptr, (int)dataSize);
		mDevice.Queue.WriteBuffer(mInstanceBuffer, 0, data);

		mDirty = false;
	}

	/// Returns the number of sprites in the current batch.
	public int32 SpriteCount => (int32)mSprites.Count;

	/// Gets the instance buffer for rendering.
	public IBuffer InstanceBuffer => mInstanceBuffer;

	/// Returns true if the renderer is fully initialized with pipeline.
	public bool IsInitialized => mInitialized && mPipeline != null;
}
