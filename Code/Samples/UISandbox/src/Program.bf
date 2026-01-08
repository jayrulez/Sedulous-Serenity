namespace UISandbox;

using System;
using System.Collections;
using System.IO;
using Sedulous.Mathematics;
using Sedulous.RHI;
using SampleFramework;
using Sedulous.Drawing;
using Sedulous.Fonts;
using Sedulous.Fonts.TTF;
using Sedulous.UI;
using Sedulous.Shell.Input;

// Type aliases to resolve ambiguity
typealias RHITexture = Sedulous.RHI.ITexture;
typealias DrawingTexture = Sedulous.Drawing.ITexture;

/// Dummy clipboard implementation using static storage.
/// Since Sedulous.Shell doesn't have clipboard support yet.
class DummyClipboard : IClipboard
{
	private static String sClipboardText = new .() ~ delete _;

	public Result<void> GetText(String outText)
	{
		outText.Set(sClipboardText);
		return .Ok;
	}

	public Result<void> SetText(StringView text)
	{
		sClipboardText.Set(text);
		return .Ok;
	}

	public bool HasText => !sClipboardText.IsEmpty;
}

/// Font service that provides access to loaded fonts.
class UISandboxFontService : IFontService
{
	private CachedFont mCachedFont;
	private DrawingTexture mFontTexture;
	private String mDefaultFontFamily = new .("Roboto") ~ delete _;

	public this(IFont font, IFontAtlas atlas, DrawingTexture texture)
	{
		mCachedFont = new CachedFont(font, atlas);
		mFontTexture = texture;
	}

	public ~this()
	{
		delete mCachedFont;
	}

	public StringView DefaultFontFamily => mDefaultFontFamily;

	public CachedFont GetFont(float pixelHeight)
	{
		// For now, only support a single font size
		return mCachedFont;
	}

	public CachedFont GetFont(StringView familyName, float pixelHeight)
	{
		// For now, only support the default font
		return mCachedFont;
	}

	public DrawingTexture GetAtlasTexture(CachedFont font)
	{
		return mFontTexture;
	}

	public DrawingTexture GetAtlasTexture(StringView familyName, float pixelHeight)
	{
		return mFontTexture;
	}

	public void ReleaseFont(CachedFont font)
	{
		// We manage the font lifetime ourselves
	}
}

/// Vertex structure matching DrawVertex layout for GPU rendering.
[CRepr]
struct RenderVertex
{
	public float[2] Position;
	public float[2] TexCoord;
	public float[4] Color;

	public this(DrawVertex v)
	{
		Position = .(v.Position.X, v.Position.Y);
		TexCoord = .(v.TexCoord.X, v.TexCoord.Y);
		Color = .(v.Color.R / 255.0f, v.Color.G / 255.0f, v.Color.B / 255.0f, v.Color.A / 255.0f);
	}
}

/// Uniform buffer data for the projection matrix.
[CRepr]
struct Uniforms
{
	public Matrix Projection;
}

/// UI Sandbox sample demonstrating the Sedulous.UI framework.
class UISandboxSample : RHISampleApp
{
	// UI System
	private UIContext mUIContext ~ delete _;
	private DummyClipboard mClipboard ~ delete _;
	private UISandboxFontService mFontService ~ delete _;
	private delegate void(StringView) mTextInputDelegate ~ delete _;

	// Drawing context
	private DrawContext mDrawContext = new .() ~ delete _;

	// Font resources
	private IFont mFont;
	private IFontAtlas mFontAtlas;
	private TextureRef mFontTextureRef ~ delete _;

	// GPU resources - double buffered
	private IBuffer[MAX_FRAMES_IN_FLIGHT] mVertexBuffers;
	private IBuffer[MAX_FRAMES_IN_FLIGHT] mIndexBuffers;
	private IBuffer[MAX_FRAMES_IN_FLIGHT] mUniformBuffers;
	private RHITexture mAtlasTexture;
	private ITextureView mAtlasTextureView;
	private ISampler mSampler;
	private IShaderModule mVertShader;
	private IShaderModule mFragShader;
	private IBindGroupLayout mBindGroupLayout;
	private IPipelineLayout mPipelineLayout;
	private IRenderPipeline mPipeline;
	private IBindGroup[MAX_FRAMES_IN_FLIGHT] mBindGroups;

	// Per-frame vertex/index data
	private List<RenderVertex> mVertices = new .() ~ delete _;
	private List<uint16> mIndices = new .() ~ delete _;
	private List<DrawCommand> mDrawCommands = new .() ~ delete _;
	private int mMaxQuads = 8192;

	// Animation state
	private float mAnimationTime = 0;

	// FPS tracking
	private int mFrameCount = 0;
	private float mFpsTimer = 0;
	private int mCurrentFps = 0;

	public this() : base(.()
		{
			Title = "UI Sandbox",
			Width = 1280,
			Height = 720,
			ClearColor = .(0.15f, 0.15f, 0.2f, 1.0f)
		})
	{
	}

	protected override bool OnInitialize()
	{
		if (!InitializeFont())
			return false;

		if (!CreateAtlasTexture())
			return false;

		if (!CreateBuffers())
			return false;

		if (!CreateBindings())
			return false;

		if (!CreatePipeline())
			return false;

		// Set white pixel UV from the font atlas
		let (u, v) = mFontAtlas.WhitePixelUV;
		mDrawContext.WhitePixelUV = .(u, v);

		// Initialize UI
		if (!InitializeUI())
			return false;

		return true;
	}

	private bool InitializeFont()
	{
		String fontPath = scope .();
		GetAssetPath("framework/fonts/roboto/Roboto-Regular.ttf", fontPath);

		if (!File.Exists(fontPath))
		{
			Console.WriteLine(scope $"Font not found: {fontPath}");
			return false;
		}

		TrueTypeFonts.Initialize();

		FontLoadOptions options = .ExtendedLatin;
		options.PixelHeight = 16;

		if (FontLoaderFactory.LoadFont(fontPath, options) case .Ok(let font))
			mFont = font;
		else
		{
			Console.WriteLine("Failed to load font");
			return false;
		}

		if (FontLoaderFactory.CreateAtlas(mFont, options) case .Ok(let atlas))
		{
			mFontAtlas = atlas;
			Console.WriteLine(scope $"Font atlas created: {mFontAtlas.Width}x{mFontAtlas.Height}");
		}
		else
		{
			Console.WriteLine("Failed to create font atlas");
			return false;
		}

		return true;
	}

	private bool CreateAtlasTexture()
	{
		let atlasWidth = mFontAtlas.Width;
		let atlasHeight = mFontAtlas.Height;
		let r8Data = mFontAtlas.PixelData;

		// Convert R8 to RGBA8
		uint8[] rgba8Data = new uint8[atlasWidth * atlasHeight * 4];
		defer delete rgba8Data;

		for (uint32 i = 0; i < atlasWidth * atlasHeight; i++)
		{
			let alpha = r8Data[i];
			rgba8Data[i * 4 + 0] = 255;
			rgba8Data[i * 4 + 1] = 255;
			rgba8Data[i * 4 + 2] = 255;
			rgba8Data[i * 4 + 3] = alpha;
		}

		TextureDescriptor textureDesc = TextureDescriptor.Texture2D(
			atlasWidth, atlasHeight, .RGBA8Unorm, .Sampled | .CopyDst
		);

		if (Device.CreateTexture(&textureDesc) not case .Ok(let texture))
		{
			Console.WriteLine("Failed to create atlas texture");
			return false;
		}
		mAtlasTexture = texture;

		TextureDataLayout dataLayout = .()
		{
			Offset = 0,
			BytesPerRow = atlasWidth * 4,
			RowsPerImage = atlasHeight
		};
		Extent3D writeSize = .(atlasWidth, atlasHeight, 1);
		Device.Queue.WriteTexture(mAtlasTexture, Span<uint8>(rgba8Data.Ptr, rgba8Data.Count), &dataLayout, &writeSize);

		TextureViewDescriptor viewDesc = .() { Format = .RGBA8Unorm };
		if (Device.CreateTextureView(mAtlasTexture, &viewDesc) not case .Ok(let view))
		{
			Console.WriteLine("Failed to create atlas texture view");
			return false;
		}
		mAtlasTextureView = view;

		mFontTextureRef = new TextureRef(mAtlasTexture, atlasWidth, atlasHeight);

		SamplerDescriptor samplerDesc = .()
		{
			AddressModeU = .ClampToEdge,
			AddressModeV = .ClampToEdge,
			AddressModeW = .ClampToEdge,
			MagFilter = .Linear,
			MinFilter = .Linear,
			MipmapFilter = .Linear
		};
		if (Device.CreateSampler(&samplerDesc) not case .Ok(let sampler))
		{
			Console.WriteLine("Failed to create sampler");
			return false;
		}
		mSampler = sampler;

		return true;
	}

	private bool CreateBuffers()
	{
		uint64 vertexBufferSize = (uint64)(sizeof(RenderVertex) * mMaxQuads * 4);
		uint64 indexBufferSize = (uint64)(sizeof(uint16) * mMaxQuads * 6);

		for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++)
		{
			BufferDescriptor vertexDesc = .()
			{
				Size = vertexBufferSize,
				Usage = .Vertex,
				MemoryAccess = .Upload
			};
			if (Device.CreateBuffer(&vertexDesc) not case .Ok(let vb))
				return false;
			mVertexBuffers[i] = vb;

			BufferDescriptor indexDesc = .()
			{
				Size = indexBufferSize,
				Usage = .Index,
				MemoryAccess = .Upload
			};
			if (Device.CreateBuffer(&indexDesc) not case .Ok(let ib))
				return false;
			mIndexBuffers[i] = ib;

			BufferDescriptor uniformDesc = .()
			{
				Size = (uint64)sizeof(Uniforms),
				Usage = .Uniform,
				MemoryAccess = .Upload
			};
			if (Device.CreateBuffer(&uniformDesc) not case .Ok(let ub))
				return false;
			mUniformBuffers[i] = ub;
		}

		return true;
	}

	private bool CreateBindings()
	{
		let shaderResult = ShaderUtils.LoadShaderPair(Device, GetAssetPath("samples/DrawingSandbox/shaders/draw", .. scope .()));
		if (shaderResult case .Err)
		{
			Console.WriteLine("Failed to load shaders");
			return false;
		}
		(mVertShader, mFragShader) = shaderResult.Get();

		BindGroupLayoutEntry[3] layoutEntries = .(
			BindGroupLayoutEntry.UniformBuffer(0, .Vertex),
			BindGroupLayoutEntry.SampledTexture(0, .Fragment),
			BindGroupLayoutEntry.Sampler(0, .Fragment)
		);
		BindGroupLayoutDescriptor bindGroupLayoutDesc = .(layoutEntries);
		if (Device.CreateBindGroupLayout(&bindGroupLayoutDesc) not case .Ok(let layout))
			return false;
		mBindGroupLayout = layout;

		for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++)
		{
			BindGroupEntry[3] bindGroupEntries = .(
				BindGroupEntry.Buffer(0, mUniformBuffers[i]),
				BindGroupEntry.Texture(0, mAtlasTextureView),
				BindGroupEntry.Sampler(0, mSampler)
			);
			BindGroupDescriptor bindGroupDesc = .(mBindGroupLayout, bindGroupEntries);
			if (Device.CreateBindGroup(&bindGroupDesc) not case .Ok(let group))
				return false;
			mBindGroups[i] = group;
		}

		IBindGroupLayout[1] layouts = .(mBindGroupLayout);
		PipelineLayoutDescriptor pipelineLayoutDesc = .(layouts);
		if (Device.CreatePipelineLayout(&pipelineLayoutDesc) not case .Ok(let pipelineLayout))
			return false;
		mPipelineLayout = pipelineLayout;

		return true;
	}

	private bool CreatePipeline()
	{
		VertexAttribute[3] vertexAttributes = .(
			.(VertexFormat.Float2, 0, 0),
			.(VertexFormat.Float2, 8, 1),
			.(VertexFormat.Float4, 16, 2)
		);
		VertexBufferLayout[1] vertexBuffers = .(
			.((uint64)sizeof(RenderVertex), vertexAttributes)
		);

		ColorTargetState[1] colorTargets = .(.(SwapChain.Format, .AlphaBlend));

		RenderPipelineDescriptor pipelineDesc = .()
		{
			Layout = mPipelineLayout,
			Vertex = .()
			{
				Shader = .(mVertShader, "main"),
				Buffers = vertexBuffers
			},
			Fragment = .()
			{
				Shader = .(mFragShader, "main"),
				Targets = colorTargets
			},
			Primitive = .()
			{
				Topology = .TriangleList,
				FrontFace = .CCW,
				CullMode = .None
			},
			DepthStencil = null,
			Multisample = .()
			{
				Count = 1,
				Mask = uint32.MaxValue,
				AlphaToCoverageEnabled = false
			}
		};

		if (Device.CreateRenderPipeline(&pipelineDesc) not case .Ok(let pipeline))
			return false;
		mPipeline = pipeline;

		return true;
	}

	private bool InitializeUI()
	{
		mUIContext = new UIContext();

		mUIContext.DebugSettings.ShowLayoutBounds = false;
		mUIContext.DebugSettings.ShowMargins = mUIContext.DebugSettings.ShowLayoutBounds;
		mUIContext.DebugSettings.ShowPadding = mUIContext.DebugSettings.ShowLayoutBounds;
		mUIContext.DebugSettings.ShowFocused = mUIContext.DebugSettings.ShowLayoutBounds;

		// Register clipboard
		mClipboard = new DummyClipboard();
		mUIContext.RegisterClipboard(mClipboard);

		// Register font service
		mFontService = new UISandboxFontService(mFont, mFontAtlas, mFontTextureRef);
		mUIContext.RegisterService<IFontService>(mFontService);

		// Register theme
		let theme = new DefaultTheme();
		mUIContext.RegisterService<ITheme>(theme);

		// Set viewport
		mUIContext.SetViewportSize((float)SwapChain.Width, (float)SwapChain.Height);

		// Subscribe to text input events
		mTextInputDelegate = new => OnTextInput;
		Shell.InputManager.Keyboard.OnTextInput.Subscribe(mTextInputDelegate);

		// Build UI
		BuildUI();

		return true;
	}

	private void OnTextInput(StringView text)
	{
		// Forward each character to the UI context
		for (let c in text.DecodedChars)
		{
			mUIContext.ProcessTextInput(c);
		}
	}

	private void BuildUI()
	{
		// Create root layout
		let root = new DockPanel();
		root.Background = Color(30, 30, 40, 255);

		// Header
		let header = new StackPanel();
		header.Orientation = .Horizontal;
		header.Background = Color(50, 50, 70, 255);
		header.Padding = Thickness(10, 5, 10, 5);
		root.SetDock(header, .Top);

		let title = new TextBlock();
		title.Text = "Sedulous UI Sandbox";
		title.Foreground = Color.White;
		title.VerticalAlignment = .Center;
		header.AddChild(title);

		root.AddChild(header);

		// Main content area with scroll
		let scrollViewer = new ScrollViewer();
		scrollViewer.Padding = Thickness(20);

		let content = new StackPanel();
		content.Orientation = .Vertical;
		content.Spacing = 20;

		// Section: Buttons
		AddSection(content, "Buttons", scope (panel) => {
			let hstack = new StackPanel();
			hstack.Orientation = .Horizontal;
			hstack.Spacing = 10;

			let btn1 = new Button();
			btn1.ContentText = "Click Me";
			btn1.Padding = Thickness(15, 8, 15, 8);
			hstack.AddChild(btn1);

			let btn2 = new Button();
			btn2.ContentText = "Disabled";
			btn2.Padding = Thickness(15, 8, 15, 8);
			btn2.IsEnabled = false;
			hstack.AddChild(btn2);

			panel.AddChild(hstack);
		});

		// Section: Checkboxes
		AddSection(content, "Checkboxes", scope (panel) => {
			let cb1 = new CheckBox();
			cb1.ContentText = "Option 1";
			cb1.IsChecked = true;
			panel.AddChild(cb1);

			let cb2 = new CheckBox();
			cb2.ContentText = "Option 2";
			panel.AddChild(cb2);

			let cb3 = new CheckBox();
			cb3.ContentText = "Option 3 (Disabled)";
			cb3.IsEnabled = false;
			panel.AddChild(cb3);
		});

		// Section: Radio Buttons
		AddSection(content, "Radio Buttons", scope (panel) => {
			let rb1 = new RadioButton();
			rb1.ContentText = "Choice A";
			rb1.GroupName = "choices";
			rb1.IsChecked = true;
			panel.AddChild(rb1);

			let rb2 = new RadioButton();
			rb2.ContentText = "Choice B";
			rb2.GroupName = "choices";
			panel.AddChild(rb2);

			let rb3 = new RadioButton();
			rb3.ContentText = "Choice C";
			rb3.GroupName = "choices";
			panel.AddChild(rb3);
		});

		// Section: Text Input
		AddSection(content, "Text Input", scope (panel) => {
			let textBox = new TextBox();
			textBox.Width = 300;
			textBox.Placeholder = "Enter text here...";
			panel.AddChild(textBox);
		});

		// Section: Progress Bar
		AddSection(content, "Progress Bar", scope (panel) => {
			let progress = new ProgressBar();
			progress.Width = 300;
			progress.Height = 20;
			progress.Value = 0.65f;
			panel.AddChild(progress);
		});

		// Section: Slider
		AddSection(content, "Slider", scope (panel) => {
			let slider = new Slider();
			slider.Width = 300;
			slider.Value = 0.5f;
			panel.AddChild(slider);
		});

		scrollViewer.Content = content;
		root.AddChild(scrollViewer);

		mUIContext.RootElement = root;
	}

	private void AddSection(StackPanel parent, StringView title, delegate void(StackPanel) buildContent)
	{
		let section = new StackPanel();
		section.Spacing = 8;

		let header = new TextBlock();
		header.Text = title;
		header.Foreground = Color(200, 200, 255, 255);
		section.AddChild(header);

		let contentPanel = new StackPanel();
		contentPanel.Spacing = 5;
		contentPanel.Margin = Thickness(10, 0, 0, 0);
		buildContent(contentPanel);
		section.AddChild(contentPanel);

		parent.AddChild(section);
	}

	protected override void OnUpdate(float deltaTime, float totalTime)
	{
		mAnimationTime = totalTime;

		// FPS calculation
		mFrameCount++;
		mFpsTimer += deltaTime;
		if (mFpsTimer >= 1.0f)
		{
			mCurrentFps = mFrameCount;
			mFrameCount = 0;
			mFpsTimer -= 1.0f;
		}

		// Route input to UI
		RouteInput();

		// Update UI
		mUIContext.Update(deltaTime, (double)totalTime);
	}

	private void RouteInput()
	{
		let input = Shell.InputManager;

		// Mouse position
		mUIContext.ProcessMouseMove(input.Mouse.X, input.Mouse.Y);

		// Mouse buttons
		if (input.Mouse.IsButtonPressed(.Left))
			mUIContext.ProcessMouseDown(.Left, input.Mouse.X, input.Mouse.Y);
		if (input.Mouse.IsButtonReleased(.Left))
			mUIContext.ProcessMouseUp(.Left, input.Mouse.X, input.Mouse.Y);

		if (input.Mouse.IsButtonPressed(.Right))
			mUIContext.ProcessMouseDown(.Right, input.Mouse.X, input.Mouse.Y);
		if (input.Mouse.IsButtonReleased(.Right))
			mUIContext.ProcessMouseUp(.Right, input.Mouse.X, input.Mouse.Y);

		// Mouse wheel
		if (input.Mouse.ScrollY != 0)
			mUIContext.ProcessMouseWheel(input.Mouse.ScrollX, input.Mouse.ScrollY, input.Mouse.X, input.Mouse.Y);

		// Keyboard - check each key
		for (int key = 0; key < (int)Sedulous.Shell.Input.KeyCode.Count; key++)
		{
			let shellKey = (Sedulous.Shell.Input.KeyCode)key;
			if (input.Keyboard.IsKeyPressed(shellKey))
				mUIContext.ProcessKeyDown(MapKey(shellKey), 0, GetModifiers(input.Keyboard));
			if (input.Keyboard.IsKeyReleased(shellKey))
				mUIContext.ProcessKeyUp(MapKey(shellKey), 0, GetModifiers(input.Keyboard));
		}
	}

	/// Maps a Shell KeyCode to UI KeyCode.
	/// Since both enums use the same values, this is a direct cast.
	private static Sedulous.UI.KeyCode MapKey(Sedulous.Shell.Input.KeyCode shellKey)
	{
		return (Sedulous.UI.KeyCode)(int32)shellKey;
	}

	private Sedulous.UI.KeyModifiers GetModifiers(IKeyboard keyboard)
	{
		var mods = Sedulous.UI.KeyModifiers.None;
		let shellMods = keyboard.Modifiers;

		if (shellMods.HasFlag(.LeftShift) || shellMods.HasFlag(.RightShift))
			mods |= .Shift;
		if (shellMods.HasFlag(.LeftCtrl) || shellMods.HasFlag(.RightCtrl))
			mods |= .Ctrl;
		if (shellMods.HasFlag(.LeftAlt) || shellMods.HasFlag(.RightAlt))
			mods |= .Alt;

		return mods;
	}

	protected override void OnPrepareFrame(int32 frameIndex)
	{
		UpdateProjection(frameIndex);
		BuildDrawCommands();
		ConvertBatchToRenderData(frameIndex);
	}

	private void UpdateProjection(int32 frameIndex)
	{
		float width = (float)SwapChain.Width;
		float height = (float)SwapChain.Height;

		Matrix projection;
		if (Device.FlipProjectionRequired)
			projection = Matrix.CreateOrthographicOffCenter(0, width, 0, height, -1, 1);
		else
			projection = Matrix.CreateOrthographicOffCenter(0, width, height, 0, -1, 1);

		Uniforms uniforms = .() { Projection = projection };
		Span<uint8> uniformData = .((uint8*)&uniforms, sizeof(Uniforms));
		var buf = mUniformBuffers[frameIndex];
		Device.Queue.WriteBuffer(buf, 0, uniformData);
	}

	private void BuildDrawCommands()
	{
		mDrawContext.Clear();

		// Render UI
		mUIContext.Render(mDrawContext);

		// FPS overlay (top-right)
		float screenWidth = (float)SwapChain.Width;
		float screenHeight = (float)SwapChain.Height;
		let fpsText = scope $"FPS: {mCurrentFps}";
		mDrawContext.DrawText(fpsText, mFontAtlas, mFontTextureRef, .(screenWidth - 80, 10 + mFont.Metrics.Ascent), Color.Lime);

		// Debug toggle hint (bottom-left)
		float debugTextY = screenHeight - 10;
		if (mUIContext.DebugSettings.ShowLayoutBounds)
			mDrawContext.DrawText("F11: Debug ON", mFontAtlas, mFontTextureRef, .(10, debugTextY), Color.Yellow);
		else
			mDrawContext.DrawText("F11: Debug OFF", mFontAtlas, mFontTextureRef, .(10, debugTextY), Color.Gray);
	}

	private void ConvertBatchToRenderData(int32 frameIndex)
	{
		let batch = mDrawContext.GetBatch();

		mVertices.Clear();
		mIndices.Clear();
		mDrawCommands.Clear();

		for (let v in batch.Vertices)
			mVertices.Add(.(v));

		for (let i in batch.Indices)
			mIndices.Add(i);

		for (let cmd in batch.Commands)
			mDrawCommands.Add(cmd);

		if (mVertices.Count > 0)
		{
			let vertexData = Span<uint8>((uint8*)mVertices.Ptr, mVertices.Count * sizeof(RenderVertex));
			var vbuf = mVertexBuffers[frameIndex];
			Device.Queue.WriteBuffer(vbuf, 0, vertexData);

			let indexData = Span<uint8>((uint8*)mIndices.Ptr, mIndices.Count * sizeof(uint16));
			var ibuf = mIndexBuffers[frameIndex];
			Device.Queue.WriteBuffer(ibuf, 0, indexData);
		}
	}

	protected override bool OnRenderFrame(ICommandEncoder encoder, int32 frameIndex)
	{
		if (mIndices.Count == 0 || mDrawCommands.Count == 0)
			return true;

		let swapTextureView = SwapChain.CurrentTextureView;
		RenderPassColorAttachment[1] colorAttachments = .(.(swapTextureView)
			{
				LoadOp = .Clear,
				StoreOp = .Store,
				ClearValue = .(0.15f, 0.15f, 0.2f, 1.0f)
			});
		RenderPassDescriptor passDesc = .(colorAttachments);

		let renderPass = encoder.BeginRenderPass(&passDesc);
		if (renderPass != null)
		{
			renderPass.SetViewport(0, 0, SwapChain.Width, SwapChain.Height, 0, 1);
			renderPass.SetPipeline(mPipeline);
			renderPass.SetBindGroup(0, mBindGroups[frameIndex]);
			renderPass.SetVertexBuffer(0, mVertexBuffers[frameIndex], 0);
			renderPass.SetIndexBuffer(mIndexBuffers[frameIndex], .UInt16, 0);

			// Process each draw command with its own scissor rect
			for (let cmd in mDrawCommands)
			{
				if (cmd.IndexCount == 0)
					continue;

				// Set scissor rect based on clip mode
				if (cmd.ClipMode == .Scissor && cmd.ClipRect.Width > 0 && cmd.ClipRect.Height > 0)
				{
					// Clamp scissor to screen bounds
					let x = (int32)Math.Max(0, cmd.ClipRect.X);
					let y = (int32)Math.Max(0, cmd.ClipRect.Y);
					let w = (uint32)Math.Max(0, Math.Min(cmd.ClipRect.Width, (int32)SwapChain.Width - x));
					let h = (uint32)Math.Max(0, Math.Min(cmd.ClipRect.Height, (int32)SwapChain.Height - y));
					renderPass.SetScissorRect(x, y, w, h);
				}
				else
				{
					// No clipping - use full screen
					renderPass.SetScissorRect(0, 0, SwapChain.Width, SwapChain.Height);
				}

				renderPass.DrawIndexed((uint32)cmd.IndexCount, 1, (uint32)cmd.StartIndex, 0, 0);
			}

			renderPass.End();
			delete renderPass;
		}

		return true;
	}

	protected override void OnRender(IRenderPassEncoder renderPass)
	{
		// Not used - we use OnRenderFrame
	}

	protected override void OnKeyDown(Sedulous.Shell.Input.KeyCode key)
	{
		// Toggle debug visualization with F11
		if (key == .F11)
		{
			mUIContext.DebugSettings.ShowLayoutBounds = !mUIContext.DebugSettings.ShowLayoutBounds;
			mUIContext.DebugSettings.ShowMargins = mUIContext.DebugSettings.ShowLayoutBounds;
			mUIContext.DebugSettings.ShowPadding = mUIContext.DebugSettings.ShowLayoutBounds;
			mUIContext.DebugSettings.ShowFocused = mUIContext.DebugSettings.ShowLayoutBounds;
		}
	}

	protected override void OnResize(uint32 width, uint32 height)
	{
		mUIContext.SetViewportSize((float)width, (float)height);
	}

	protected override void OnCleanup()
	{
		// Unsubscribe from text input events
		if (mTextInputDelegate != null)
			Shell.InputManager.Keyboard.OnTextInput.Unsubscribe(mTextInputDelegate, false);

		// Clean up theme (registered as service, owned by us)
		if (mUIContext.GetService<ITheme>() case .Ok(let theme))
			delete theme;

		if (mPipeline != null) delete mPipeline;
		if (mPipelineLayout != null) delete mPipelineLayout;
		if (mBindGroupLayout != null) delete mBindGroupLayout;
		if (mFragShader != null) delete mFragShader;
		if (mVertShader != null) delete mVertShader;
		if (mSampler != null) delete mSampler;
		if (mAtlasTextureView != null) delete mAtlasTextureView;
		if (mAtlasTexture != null) delete mAtlasTexture;

		for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++)
		{
			if (mBindGroups[i] != null) delete mBindGroups[i];
			if (mUniformBuffers[i] != null) delete mUniformBuffers[i];
			if (mIndexBuffers[i] != null) delete mIndexBuffers[i];
			if (mVertexBuffers[i] != null) delete mVertexBuffers[i];
		}

		//if (mFontAtlas != null) delete (Object)mFontAtlas;
		//if (mFont != null) delete (Object)mFont;

		TrueTypeFonts.Shutdown();
	}
}

class Program
{
	public static int Main(String[] args)
	{
		let app = scope UISandboxSample();
		return app.Run();
	}
}
