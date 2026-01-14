namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Shaders;
using Sedulous.Mathematics;

/// A batch of sprites sharing the same texture.
struct SpriteBatch
{
	/// Texture for this batch (null = white texture).
	public ITextureView Texture;
	/// Starting index in the instance buffer.
	public uint32 StartIndex;
	/// Number of sprites in this batch.
	public uint32 Count;

	public this(ITextureView texture, uint32 startIndex, uint32 count)
	{
		Texture = texture;
		StartIndex = startIndex;
		Count = count;
	}
}

/// Entry for a sprite with its texture before batching.
struct SpriteEntry
{
	public SpriteInstance Instance;
	public ITextureView Texture;

	public this(SpriteInstance instance, ITextureView texture)
	{
		Instance = instance;
		Texture = texture;
	}
}

/// Cached bind groups for a texture.
class TextureBindGroupEntry
{
	public ITextureView Texture;
	public IBindGroup[FrameConfig.MAX_FRAMES_IN_FLIGHT] BindGroups;

	public this(ITextureView texture)
	{
		Texture = texture;
	}

	public ~this()
	{
		for (let bg in BindGroups)
			delete bg;
	}
}

/// Batched sprite renderer for efficient billboard rendering.
/// Supports multiple textures via automatic batching.
class SpriteRenderer
{

	private IDevice mDevice;
	private ShaderLibrary mShaderLibrary;

	// Buffers
	private IBuffer mInstanceBuffer;

	// Pipeline resources
	private IBindGroupLayout mBindGroupLayout ~ delete _;
	private IPipelineLayout mPipelineLayout ~ delete _;
	private IRenderPipeline mPipeline ~ delete _;
	private IRenderPipeline mNoDepthPipeline ~ delete _;  // For transparent pass without depth attachment

	// Per-frame camera buffers (references, not owned)
	private IBuffer[FrameConfig.MAX_FRAMES_IN_FLIGHT] mCameraBuffers;

	// Texture resources
	private ITexture mWhiteTexture ~ delete _;
	private ITextureView mWhiteTextureView ~ delete _;
	private ISampler mSampler ~ delete _;

	// Sprite data - entries before batching
	private List<SpriteEntry> mSpriteEntries = new .() ~ delete _;
	// Sorted sprite instances for GPU upload
	private List<SpriteInstance> mSortedSprites = new .() ~ delete _;
	// Batches after sorting
	private List<SpriteBatch> mBatches = new .() ~ delete _;
	// Cached bind groups per texture
	private List<TextureBindGroupEntry> mTextureBindGroups = new .() ~ DeleteContainerAndItems!(_);

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
		IBuffer[FrameConfig.MAX_FRAMES_IN_FLIGHT] cameraBuffers, TextureFormat colorFormat, TextureFormat depthFormat)
	{
		if (mDevice == null)
			return .Err;

		mShaderLibrary = shaderLibrary;
		mCameraBuffers = cameraBuffers;
		mColorFormat = colorFormat;
		mDepthFormat = depthFormat;

		// Create default white texture (1x1 white pixel)
		if (CreateDefaultTexture() case .Err)
			return .Err;

		// Create sampler
		if (CreateSampler() case .Err)
			return .Err;

		if (CreatePipeline() case .Err)
			return .Err;

		mInitialized = true;
		return .Ok;
	}

	private Result<void> CreateDefaultTexture()
	{
		// Create 1x1 white texture
		TextureDescriptor texDesc = TextureDescriptor.Texture2D(1, 1, .RGBA8Unorm, .Sampled | .CopyDst);
		if (mDevice.CreateTexture(&texDesc) not case .Ok(let tex))
			return .Err;
		mWhiteTexture = tex;

		// Upload white pixel
		uint8[4] whitePixel = .(255, 255, 255, 255);
		TextureDataLayout dataLayout = .() { Offset = 0, BytesPerRow = 4, RowsPerImage = 1 };
		Extent3D writeSize = .(1, 1, 1);
		mDevice.Queue.WriteTexture(mWhiteTexture, Span<uint8>(&whitePixel, 4), &dataLayout, &writeSize);

		// Create view
		TextureViewDescriptor viewDesc = .() { Format = .RGBA8Unorm };
		if (mDevice.CreateTextureView(mWhiteTexture, &viewDesc) not case .Ok(let view))
			return .Err;
		mWhiteTextureView = view;

		return .Ok;
	}

	private Result<void> CreateSampler()
	{
		SamplerDescriptor samplerDesc = .();
		// Default values are ClampToEdge and Linear filtering
		if (mDevice.CreateSampler(&samplerDesc) not case .Ok(let sampler))
			return .Err;
		mSampler = sampler;
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

		// Bind group layout: b0=camera uniforms, t0=texture, s0=sampler
		BindGroupLayoutEntry[3] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex),
			BindGroupLayoutEntry.SampledTexture(0, .Fragment),
			BindGroupLayoutEntry.Sampler(0, .Fragment)
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

		// Bind groups are created on-demand per texture in GetOrCreateBindGroups()

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

		// Depth state for pipeline with depth attachment
		DepthStencilState depthState = .();
		depthState.DepthTestEnabled = true;
		depthState.DepthWriteEnabled = false;
		depthState.DepthCompare = .Less;
		depthState.Format = mDepthFormat;

		// No-depth state for transparent pass
		DepthStencilState noDepthState = .();
		noDepthState.DepthTestEnabled = false;
		noDepthState.DepthWriteEnabled = false;
		noDepthState.Format = .Undefined;

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

		// Create no-depth pipeline variant
		pipelineDesc.DepthStencil = noDepthState;
		if (mDevice.CreateRenderPipeline(&pipelineDesc) not case .Ok(let noDepthPipeline))
			return .Err;
		mNoDepthPipeline = noDepthPipeline;

		return .Ok;
	}

	/// Renders all sprite batches.
	/// useNoDepth: Use pipeline without depth attachment (for transparent pass)
	public void Render(IRenderPassEncoder renderPass, int32 frameIndex, bool useNoDepth = false)
	{
		if (!mInitialized || mPipeline == null || mBatches.Count == 0)
			return;

		if (frameIndex < 0 || frameIndex >= FrameConfig.MAX_FRAMES_IN_FLIGHT)
			return;

		let pipeline = useNoDepth ? mNoDepthPipeline : mPipeline;
		renderPass.SetPipeline(pipeline);
		renderPass.SetVertexBuffer(0, mInstanceBuffer, 0);

		// Render each batch with its texture
		for (let batch in mBatches)
		{
			let bindGroups = GetOrCreateBindGroups(batch.Texture);
			renderPass.SetBindGroup(0, bindGroups[frameIndex]);
			// Draw 6 vertices per sprite (2 triangles), starting at the batch's offset
			renderPass.Draw(6, batch.Count, 0, batch.StartIndex);
		}
	}

	/// Clears all sprites for a new frame.
	public void Begin()
	{
		mSpriteEntries.Clear();
		mSortedSprites.Clear();
		mBatches.Clear();
		mDirty = true;
	}

	/// Adds a sprite with a specific texture.
	public void AddSprite(SpriteInstance sprite, ITextureView texture)
	{
		if (mSpriteEntries.Count < mMaxSprites)
		{
			mSpriteEntries.Add(.(sprite, texture));
			mDirty = true;
		}
	}

	/// Adds a sprite using the default white texture.
	public void AddSprite(SpriteInstance sprite)
	{
		AddSprite(sprite, null);
	}

	/// Adds a sprite with common parameters using the default white texture.
	public void AddSprite(Vector3 position, Vector2 size, Color color = .White)
	{
		AddSprite(.(position, size, color), null);
	}

	/// Sorts sprites by texture, builds batches, and uploads to GPU.
	public void End()
	{
		if (mSpriteEntries.Count == 0)
			return;

		if (!mDirty)
			return;

		// Sort entries by texture pointer for batching
		// Null textures (using white pixel) sort together at the beginning
		mSpriteEntries.Sort(scope (a, b) => {
			int ptrA = a.Texture != null ? (int)Internal.UnsafeCastToPtr(a.Texture) : 0;
			int ptrB = b.Texture != null ? (int)Internal.UnsafeCastToPtr(b.Texture) : 0;
			return ptrA <=> ptrB;
		});

		// Build sorted sprite list and batches
		mSortedSprites.Clear();
		mBatches.Clear();

		ITextureView currentTexture = null;
		uint32 batchStart = 0;
		uint32 batchCount = 0;
		bool firstSprite = true;

		for (let entry in mSpriteEntries)
		{
			if (firstSprite)
			{
				currentTexture = entry.Texture;
				firstSprite = false;
			}
			else if (entry.Texture != currentTexture)
			{
				// End current batch
				if (batchCount > 0)
					mBatches.Add(.(currentTexture, batchStart, batchCount));

				// Start new batch
				currentTexture = entry.Texture;
				batchStart = (uint32)mSortedSprites.Count;
				batchCount = 0;
			}

			mSortedSprites.Add(entry.Instance);
			batchCount++;
		}

		// Add final batch
		if (batchCount > 0)
			mBatches.Add(.(currentTexture, batchStart, batchCount));

		// Upload all sprite instances to GPU
		if (mSortedSprites.Count > 0)
		{
			let dataSize = (uint64)(sizeof(SpriteInstance) * mSortedSprites.Count);
			Span<uint8> data = .((uint8*)mSortedSprites.Ptr, (int)dataSize);
			mDevice.Queue.WriteBuffer(mInstanceBuffer, 0, data);
		}

		mDirty = false;
	}

	/// Gets or creates bind groups for a texture.
	private IBindGroup* GetOrCreateBindGroups(ITextureView texture)
	{
		// Use white texture if null
		let actualTexture = texture != null ? texture : mWhiteTextureView;

		// Look for existing entry
		for (let entry in mTextureBindGroups)
		{
			if (entry.Texture == actualTexture)
				return &entry.BindGroups;
		}

		// Create new entry with bind groups
		let entry = new TextureBindGroupEntry(actualTexture);
		for (int i = 0; i < FrameConfig.MAX_FRAMES_IN_FLIGHT; i++)
		{
			BindGroupEntry[3] entries = .(
				BindGroupEntry.Buffer(0, mCameraBuffers[i]),
				BindGroupEntry.Texture(0, actualTexture),
				BindGroupEntry.Sampler(0, mSampler)
			);
			BindGroupDescriptor bindGroupDesc = .(mBindGroupLayout, entries);
			if (mDevice.CreateBindGroup(&bindGroupDesc) case .Ok(let group))
				entry.BindGroups[i] = group;
		}

		mTextureBindGroups.Add(entry);
		return &entry.BindGroups;
	}

	/// Clears cached bind groups (call when textures are destroyed).
	public void ClearBindGroupCache()
	{
		DeleteContainerAndItems!(mTextureBindGroups);
		mTextureBindGroups = new .();
	}

	/// Returns the number of sprites added this frame.
	public int32 SpriteCount => (int32)mSpriteEntries.Count;

	/// Returns the number of texture batches.
	public int32 BatchCount => (int32)mBatches.Count;

	/// Gets the instance buffer for rendering.
	public IBuffer InstanceBuffer => mInstanceBuffer;

	/// Gets the default white texture view.
	public ITextureView WhiteTexture => mWhiteTextureView;

	/// Returns true if the renderer is fully initialized with pipeline.
	public bool IsInitialized => mInitialized && mPipeline != null;
}
