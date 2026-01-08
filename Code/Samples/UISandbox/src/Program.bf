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

	// Cursor tracking
	private Sedulous.UI.CursorType mLastUICursor = .Default;

	public this() : base(.()
		{
			Title = "UI Sandbox",
			Width = 1366,
			Height = 768,
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

		// Three-column layout
		let columns = new StackPanel();
		columns.Orientation = .Horizontal;
		columns.Spacing = 40;

		// Left column - Controls
		let leftColumn = new StackPanel();
		leftColumn.Orientation = .Vertical;
		leftColumn.Spacing = 20;

		// Middle column - Layout demos
		let middleColumn = new StackPanel();
		middleColumn.Orientation = .Vertical;
		middleColumn.Spacing = 20;

		// Right column - Transform demos
		let rightColumn = new StackPanel();
		rightColumn.Orientation = .Vertical;
		rightColumn.Spacing = 20;

		// Use leftColumn for basic controls
		let content = leftColumn;

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

		// Section: Layout Demos (middle column)
		AddSection(middleColumn, "Layout Demos", scope (panel) => {
			// === Grid Demo ===
			let gridLabel = new TextBlock();
			gridLabel.Text = "Grid (3x3 with Star/Auto sizing):";
			gridLabel.Foreground = Color(150, 150, 150);
			panel.AddChild(gridLabel);

			let grid = new Grid();
			grid.Width = 300;
			grid.Height = 120;
			grid.Background = Color(40, 40, 50);

			// Define rows: Auto, Star(1), Star(2)
			let row0 = new RowDefinition();
			row0.Height = .Auto;
			grid.RowDefinitions.Add(row0);
			let row1 = new RowDefinition();
			row1.Height = .Star;
			grid.RowDefinitions.Add(row1);
			let row2 = new RowDefinition();
			row2.Height = GridLength.StarWeight(2);
			grid.RowDefinitions.Add(row2);

			// Define columns: Fixed(80), Star(1), Star(1)
			let col0 = new ColumnDefinition();
			col0.Width = GridLength.Pixel(80);
			grid.ColumnDefinitions.Add(col0);
			let col1 = new ColumnDefinition();
			col1.Width = .Star;
			grid.ColumnDefinitions.Add(col1);
			let col2 = new ColumnDefinition();
			col2.Width = .Star;
			grid.ColumnDefinitions.Add(col2);

			// Add cells with different colors
			let cell00 = new Border();
			cell00.Background = Color(100, 60, 60);
			cell00.Margin = Thickness(2);
			let label00 = new TextBlock();
			label00.Text = "R0,C0";
			label00.Foreground = Color.White;
			label00.HorizontalAlignment = .Center;
			label00.VerticalAlignment = .Center;
			cell00.AddChild(label00);
			grid.SetRow(cell00, 0);
			grid.SetColumn(cell00, 0);
			grid.AddChild(cell00);

			let cell01 = new Border();
			cell01.Background = Color(60, 100, 60);
			cell01.Margin = Thickness(2);
			let label01 = new TextBlock();
			label01.Text = "R0,C1";
			label01.Foreground = Color.White;
			label01.HorizontalAlignment = .Center;
			label01.VerticalAlignment = .Center;
			cell01.AddChild(label01);
			grid.SetRow(cell01, 0);
			grid.SetColumn(cell01, 1);
			grid.AddChild(cell01);

			let cell02 = new Border();
			cell02.Background = Color(60, 60, 100);
			cell02.Margin = Thickness(2);
			let label02 = new TextBlock();
			label02.Text = "R0,C2";
			label02.Foreground = Color.White;
			label02.HorizontalAlignment = .Center;
			label02.VerticalAlignment = .Center;
			cell02.AddChild(label02);
			grid.SetRow(cell02, 0);
			grid.SetColumn(cell02, 2);
			grid.AddChild(cell02);

			// Row 1 - spans all columns
			let cell10 = new Border();
			cell10.Background = Color(100, 80, 60);
			cell10.Margin = Thickness(2);
			let label10 = new TextBlock();
			label10.Text = "Row 1 (ColSpan=3)";
			label10.Foreground = Color.White;
			label10.HorizontalAlignment = .Center;
			label10.VerticalAlignment = .Center;
			cell10.AddChild(label10);
			grid.SetRow(cell10, 1);
			grid.SetColumn(cell10, 0);
			grid.SetColumnSpan(cell10, 3);
			grid.AddChild(cell10);

			// Row 2
			let cell20 = new Border();
			cell20.Background = Color(80, 60, 100);
			cell20.Margin = Thickness(2);
			let label20 = new TextBlock();
			label20.Text = "R2,C0";
			label20.Foreground = Color.White;
			label20.HorizontalAlignment = .Center;
			label20.VerticalAlignment = .Center;
			cell20.AddChild(label20);
			grid.SetRow(cell20, 2);
			grid.SetColumn(cell20, 0);
			grid.AddChild(cell20);

			let cell21 = new Border();
			cell21.Background = Color(60, 100, 100);
			cell21.Margin = Thickness(2);
			let label21 = new TextBlock();
			label21.Text = "R2,C1-2 (ColSpan=2)";
			label21.Foreground = Color.White;
			label21.HorizontalAlignment = .Center;
			label21.VerticalAlignment = .Center;
			cell21.AddChild(label21);
			grid.SetRow(cell21, 2);
			grid.SetColumn(cell21, 1);
			grid.SetColumnSpan(cell21, 2);
			grid.AddChild(cell21);

			panel.AddChild(grid);

			// === Canvas Demo ===
			let canvasLabel = new TextBlock();
			canvasLabel.Text = "Canvas (Absolute positioning):";
			canvasLabel.Foreground = Color(150, 150, 150);
			canvasLabel.Margin = Thickness(0, 15, 0, 0);
			panel.AddChild(canvasLabel);

			let canvas = new Canvas();
			canvas.Width = 300;
			canvas.Height = 100;
			canvas.Background = Color(40, 40, 50);

			// Add positioned elements
			let box1 = new Border();
			box1.Width = 50;
			box1.Height = 30;
			box1.Background = Color(200, 80, 80);
			box1.CornerRadius = 4;
			canvas.SetLeft(box1, 10);
			canvas.SetTop(box1, 10);
			canvas.AddChild(box1);

			let box2 = new Border();
			box2.Width = 60;
			box2.Height = 40;
			box2.Background = Color(80, 200, 80);
			box2.CornerRadius = 4;
			canvas.SetLeft(box2, 80);
			canvas.SetTop(box2, 30);
			canvas.AddChild(box2);

			let box3 = new Border();
			box3.Width = 70;
			box3.Height = 35;
			box3.Background = Color(80, 80, 200);
			box3.CornerRadius = 4;
			canvas.SetLeft(box3, 160);
			canvas.SetTop(box3, 15);
			canvas.AddChild(box3);

			let box4 = new Border();
			box4.Width = 40;
			box4.Height = 50;
			box4.Background = Color(200, 200, 80);
			box4.CornerRadius = 4;
			canvas.SetRight(box4, 10);
			canvas.SetBottom(box4, 10);
			canvas.AddChild(box4);

			panel.AddChild(canvas);

			// === WrapPanel Demo ===
			let wrapLabel = new TextBlock();
			wrapLabel.Text = "WrapPanel (Items wrap to next line):";
			wrapLabel.Foreground = Color(150, 150, 150);
			wrapLabel.Margin = Thickness(0, 15, 0, 0);
			panel.AddChild(wrapLabel);

			let wrapPanel = new WrapPanel();
			wrapPanel.Width = 300;
			wrapPanel.Background = Color(40, 40, 50);
			wrapPanel.Padding = Thickness(5);

			// Add multiple items that will wrap
			Color[?] colors = .(
				Color(180, 80, 80), Color(80, 180, 80), Color(80, 80, 180),
				Color(180, 180, 80), Color(180, 80, 180), Color(80, 180, 180),
				Color(140, 100, 80), Color(80, 140, 100), Color(100, 80, 140),
				Color(160, 120, 80), Color(80, 160, 120)
			);

			for (int i = 0; i < colors.Count; i++)
			{
				let item = new Border();
				item.Width = 50 + (i % 3) * 10; // Varying widths
				item.Height = 25;
				item.Background = colors[i];
				item.Margin = Thickness(3);
				item.CornerRadius = 3;
				wrapPanel.AddChild(item);
			}

			panel.AddChild(wrapPanel);

			// === DockPanel Demo ===
			let dockLabel = new TextBlock();
			dockLabel.Text = "DockPanel (Dock to edges):";
			dockLabel.Foreground = Color(150, 150, 150);
			dockLabel.Margin = Thickness(0, 15, 0, 0);
			panel.AddChild(dockLabel);

			let dockPanel = new DockPanel();
			dockPanel.Width = 300;
			dockPanel.Height = 120;
			dockPanel.Background = Color(40, 40, 50);

			let topDock = new Border();
			topDock.Height = 25;
			topDock.Background = Color(180, 80, 80);
			let topLabel = new TextBlock();
			topLabel.Text = "Top";
			topLabel.Foreground = Color.White;
			topLabel.HorizontalAlignment = .Center;
			topLabel.VerticalAlignment = .Center;
			topDock.AddChild(topLabel);
			dockPanel.SetDock(topDock, .Top);
			dockPanel.AddChild(topDock);

			let bottomDock = new Border();
			bottomDock.Height = 25;
			bottomDock.Background = Color(80, 80, 180);
			let bottomLabel = new TextBlock();
			bottomLabel.Text = "Bottom";
			bottomLabel.Foreground = Color.White;
			bottomLabel.HorizontalAlignment = .Center;
			bottomLabel.VerticalAlignment = .Center;
			bottomDock.AddChild(bottomLabel);
			dockPanel.SetDock(bottomDock, .Bottom);
			dockPanel.AddChild(bottomDock);

			let leftDock = new Border();
			leftDock.Width = 50;
			leftDock.Background = Color(80, 180, 80);
			let leftLabel = new TextBlock();
			leftLabel.Text = "Left";
			leftLabel.Foreground = Color.White;
			leftLabel.HorizontalAlignment = .Center;
			leftLabel.VerticalAlignment = .Center;
			leftDock.AddChild(leftLabel);
			dockPanel.SetDock(leftDock, .Left);
			dockPanel.AddChild(leftDock);

			let rightDock = new Border();
			rightDock.Width = 50;
			rightDock.Background = Color(180, 180, 80);
			let rightLabel = new TextBlock();
			rightLabel.Text = "Right";
			rightLabel.Foreground = Color.White;
			rightLabel.HorizontalAlignment = .Center;
			rightLabel.VerticalAlignment = .Center;
			rightDock.AddChild(rightLabel);
			dockPanel.SetDock(rightDock, .Right);
			dockPanel.AddChild(rightDock);

			// Center (fills remaining space)
			let centerDock = new Border();
			centerDock.Background = Color(120, 120, 120);
			let centerLabel = new TextBlock();
			centerLabel.Text = "Fill";
			centerLabel.Foreground = Color.White;
			centerLabel.HorizontalAlignment = .Center;
			centerLabel.VerticalAlignment = .Center;
			centerDock.AddChild(centerLabel);
			dockPanel.AddChild(centerDock);

			panel.AddChild(dockPanel);
		});

		// Section: Animations (middle column)
		AddSection(middleColumn, "Animations", scope (panel) => {
			// First row of animation buttons
			let hstack1 = new StackPanel();
			hstack1.Orientation = .Horizontal;
			hstack1.Spacing = 10;

			// Animated box that will be the target
			let animBox = new Border();
			animBox.Width = 80;
			animBox.Height = 40;
			animBox.Background = Color(0, 120, 215);
			animBox.CornerRadius = 4;

			// Fade button - animates opacity
			let fadeBtn = new Button();
			fadeBtn.ContentText = "Fade";
			fadeBtn.Padding = Thickness(12, 6, 12, 6);
			fadeBtn.Click.Subscribe(new (sender) => {
				let fadeOut = UIElementAnimations.FadeOpacity(animBox, 1.0f, 0.0f, 0.5f, .QuadraticOut);
				fadeOut.Completed.Subscribe(new (anim) => {
					let fadeIn = UIElementAnimations.FadeOpacity(animBox, 0.0f, 1.0f, 0.5f, .QuadraticIn);
					mUIContext.Animations.Add(fadeIn);
				});
				mUIContext.Animations.Add(fadeOut);
			});
			hstack1.AddChild(fadeBtn);

			// Slide button - horizontal slide animation
			let slideBtn = new Button();
			slideBtn.ContentText = "Slide";
			slideBtn.Padding = Thickness(12, 6, 12, 6);
			slideBtn.Click.Subscribe(new (sender) => {
				let currentMargin = animBox.Margin;
				let slideOut = UIElementAnimations.AnimateMargin(
					animBox, currentMargin,
					Thickness(currentMargin.Left + 60, currentMargin.Top, currentMargin.Right, currentMargin.Bottom),
					0.3f, .QuadraticOut
				);
				slideOut.Completed.Subscribe(new (anim) => {
					let slideBack = UIElementAnimations.AnimateMargin(
						animBox,
						Thickness(currentMargin.Left + 60, currentMargin.Top, currentMargin.Right, currentMargin.Bottom),
						currentMargin,
						0.3f, .QuadraticIn
					);
					mUIContext.Animations.Add(slideBack);
				});
				mUIContext.Animations.Add(slideOut);
			});
			hstack1.AddChild(slideBtn);

			// Pulse button (width animation)
			let pulseBtn = new Button();
			pulseBtn.ContentText = "Pulse";
			pulseBtn.Padding = Thickness(12, 6, 12, 6);
			pulseBtn.Click.Subscribe(new (sender) => {
				let grow = UIElementAnimations.AnimateWidth(animBox, 80, 120, 0.2f, .QuadraticOut);
				grow.Completed.Subscribe(new (anim) => {
					let shrink = UIElementAnimations.AnimateWidth(animBox, 120, 80, 0.2f, .QuadraticIn);
					mUIContext.Animations.Add(shrink);
				});
				mUIContext.Animations.Add(grow);
			});
			hstack1.AddChild(pulseBtn);

			// Bounce button (using bounce easing)
			let bounceBtn = new Button();
			bounceBtn.ContentText = "Bounce";
			bounceBtn.Padding = Thickness(12, 6, 12, 6);
			bounceBtn.Click.Subscribe(new (sender) => {
				let currentMargin = animBox.Margin;
				animBox.Margin = Thickness(currentMargin.Left, currentMargin.Top - 30, currentMargin.Right, currentMargin.Bottom);
				let bounceAnim = UIElementAnimations.AnimateMargin(
					animBox,
					Thickness(currentMargin.Left, currentMargin.Top - 30, currentMargin.Right, currentMargin.Bottom),
					currentMargin,
					0.8f,
					.BounceOut
				);
				mUIContext.Animations.Add(bounceAnim);
			});
			hstack1.AddChild(bounceBtn);

			hstack1.AddChild(animBox);
			panel.AddChild(hstack1);

			// Second row of animation buttons
			let hstack2 = new StackPanel();
			hstack2.Orientation = .Horizontal;
			hstack2.Spacing = 10;
			hstack2.Margin = Thickness(0, 5, 0, 0);

			// Scale button - grow both width and height
			let scaleBtn = new Button();
			scaleBtn.ContentText = "Scale";
			scaleBtn.Padding = Thickness(12, 6, 12, 6);
			scaleBtn.Click.Subscribe(new (sender) => {
				// Grow width and height simultaneously
				let growW = UIElementAnimations.AnimateWidth(animBox, 80, 130, 0.3f, .BackOut);
				let growH = UIElementAnimations.AnimateHeight(animBox, 40, 65, 0.3f, .BackOut);
				growW.Completed.Subscribe(new (anim) => {
					let shrinkW = UIElementAnimations.AnimateWidth(animBox, 130, 80, 0.3f, .BackIn);
					let shrinkH = UIElementAnimations.AnimateHeight(animBox, 65, 40, 0.3f, .BackIn);
					mUIContext.Animations.Add(shrinkW);
					mUIContext.Animations.Add(shrinkH);
				});
				mUIContext.Animations.Add(growW);
				mUIContext.Animations.Add(growH);
			});
			hstack2.AddChild(scaleBtn);

			// Shake button - rapid horizontal movement
			let shakeBtn = new Button();
			shakeBtn.ContentText = "Shake";
			shakeBtn.Padding = Thickness(12, 6, 12, 6);
			shakeBtn.Click.Subscribe(new (sender) => {
				let currentMargin = animBox.Margin;
				// Quick shake left
				let shake1 = UIElementAnimations.AnimateMargin(animBox, currentMargin,
					Thickness(currentMargin.Left - 10, currentMargin.Top, currentMargin.Right, currentMargin.Bottom),
					0.05f, .Linear);
				shake1.Completed.Subscribe(new (anim) => {
					// Shake right
					let shake2 = UIElementAnimations.AnimateMargin(animBox,
						Thickness(currentMargin.Left - 10, currentMargin.Top, currentMargin.Right, currentMargin.Bottom),
						Thickness(currentMargin.Left + 10, currentMargin.Top, currentMargin.Right, currentMargin.Bottom),
						0.1f, .Linear);
					shake2.Completed.Subscribe(new (anim2) => {
						// Shake left again
						let shake3 = UIElementAnimations.AnimateMargin(animBox,
							Thickness(currentMargin.Left + 10, currentMargin.Top, currentMargin.Right, currentMargin.Bottom),
							Thickness(currentMargin.Left - 8, currentMargin.Top, currentMargin.Right, currentMargin.Bottom),
							0.1f, .Linear);
						shake3.Completed.Subscribe(new (anim3) => {
							// Shake right smaller
							let shake4 = UIElementAnimations.AnimateMargin(animBox,
								Thickness(currentMargin.Left - 8, currentMargin.Top, currentMargin.Right, currentMargin.Bottom),
								Thickness(currentMargin.Left + 5, currentMargin.Top, currentMargin.Right, currentMargin.Bottom),
								0.08f, .Linear);
							shake4.Completed.Subscribe(new (anim4) => {
								// Return to center
								let shake5 = UIElementAnimations.AnimateMargin(animBox,
									Thickness(currentMargin.Left + 5, currentMargin.Top, currentMargin.Right, currentMargin.Bottom),
									currentMargin, 0.07f, .Linear);
								mUIContext.Animations.Add(shake5);
							});
							mUIContext.Animations.Add(shake4);
						});
						mUIContext.Animations.Add(shake3);
					});
					mUIContext.Animations.Add(shake2);
				});
				mUIContext.Animations.Add(shake1);
			});
			hstack2.AddChild(shakeBtn);

			// Elastic button - elastic overshoot effect
			let elasticBtn = new Button();
			elasticBtn.ContentText = "Elastic";
			elasticBtn.Padding = Thickness(12, 6, 12, 6);
			elasticBtn.Click.Subscribe(new (sender) => {
				let currentMargin = animBox.Margin;
				animBox.Margin = Thickness(currentMargin.Left, currentMargin.Top - 40, currentMargin.Right, currentMargin.Bottom);
				let elasticAnim = UIElementAnimations.AnimateMargin(
					animBox,
					Thickness(currentMargin.Left, currentMargin.Top - 40, currentMargin.Right, currentMargin.Bottom),
					currentMargin,
					1.0f,
					.ElasticOut
				);
				mUIContext.Animations.Add(elasticAnim);
			});
			hstack2.AddChild(elasticBtn);

			// Wobble button - combined scale + fade
			let wobbleBtn = new Button();
			wobbleBtn.ContentText = "Wobble";
			wobbleBtn.Padding = Thickness(12, 6, 12, 6);
			wobbleBtn.Click.Subscribe(new (sender) => {
				// Squish horizontally while stretching vertically
				let squishW = UIElementAnimations.AnimateWidth(animBox, 80, 60, 0.15f, .QuadraticOut);
				let stretchH = UIElementAnimations.AnimateHeight(animBox, 40, 55, 0.15f, .QuadraticOut);
				squishW.Completed.Subscribe(new (anim) => {
					// Stretch horizontally while squishing vertically
					let stretchW = UIElementAnimations.AnimateWidth(animBox, 60, 100, 0.15f, .QuadraticOut);
					let squishH = UIElementAnimations.AnimateHeight(animBox, 55, 32, 0.15f, .QuadraticOut);
					stretchW.Completed.Subscribe(new (anim2) => {
						// Return to normal
						let normalW = UIElementAnimations.AnimateWidth(animBox, 100, 80, 0.2f, .QuadraticInOut);
						let normalH = UIElementAnimations.AnimateHeight(animBox, 32, 40, 0.2f, .QuadraticInOut);
						mUIContext.Animations.Add(normalW);
						mUIContext.Animations.Add(normalH);
					});
					mUIContext.Animations.Add(stretchW);
					mUIContext.Animations.Add(squishH);
				});
				mUIContext.Animations.Add(squishW);
				mUIContext.Animations.Add(stretchH);
			});
			hstack2.AddChild(wobbleBtn);

			panel.AddChild(hstack2);

			// Animated progress bar
			let progressLabel = new TextBlock();
			progressLabel.Text = "Animated Progress:";
			progressLabel.Foreground = Color(180, 180, 180);
			progressLabel.Margin = Thickness(0, 10, 0, 5);
			panel.AddChild(progressLabel);

			let animProgress = new ProgressBar();
			animProgress.Width = 300;
			animProgress.Height = 20;
			animProgress.Value = 0;

			// Start button for progress animation
			let startBtn = new Button();
			startBtn.ContentText = "Animate Progress";
			startBtn.Padding = Thickness(12, 6, 12, 6);
			startBtn.Margin = Thickness(0, 5, 0, 0);
			startBtn.Click.Subscribe(new (sender) => {
				animProgress.Value = 0; // Reset first
				let progressAnim = new FloatAnimation(0, 100);
				progressAnim.Duration = 2.0f;
				progressAnim.Easing = .QuadraticInOut;
				progressAnim.OnValueChanged = new (value) => { animProgress.Value = value; };
				mUIContext.Animations.Add(progressAnim);
			});

			panel.AddChild(animProgress);
			panel.AddChild(startBtn);
		});

		// Section: Transforms (right column)
		AddSection(rightColumn, "Transforms", scope (panel) => {
			let desc = new TextBlock();
			desc.Text = "RenderTransform applied to elements:";
			desc.Foreground = Color(150, 150, 150);
			panel.AddChild(desc);

			// Container for transformed elements with extra spacing
			let transformContainer = new StackPanel();
			transformContainer.Spacing = 25;
			transformContainer.Margin = Thickness(0, 10, 0, 0);

			// === Rotated Button ===
			let rotateLabel = new TextBlock();
			rotateLabel.Text = "Rotation (15°):";
			rotateLabel.Foreground = Color(180, 180, 180);
			transformContainer.AddChild(rotateLabel);

			let rotatedBtn = new Button();
			rotatedBtn.ContentText = "Rotated";
			rotatedBtn.Padding = Thickness(20, 10, 20, 10);
			rotatedBtn.RenderTransform = Matrix.CreateRotationZ(15.0f * (Math.PI_f / 180.0f));
			rotatedBtn.Margin = Thickness(20, 0, 0, 0);
			transformContainer.AddChild(rotatedBtn);

			// === Scaled Checkbox ===
			let scaleLabel = new TextBlock();
			scaleLabel.Text = "Scale (1.5x):";
			scaleLabel.Foreground = Color(180, 180, 180);
			transformContainer.AddChild(scaleLabel);

			let scaledCb = new CheckBox();
			scaledCb.ContentText = "Scaled Up";
			scaledCb.IsChecked = true;
			scaledCb.RenderTransform = Matrix.CreateScale(1.5f, 1.5f, 1.0f);
			scaledCb.RenderTransformOrigin = .(0, 0.5f); // Left-center origin
			scaledCb.Margin = Thickness(10, 0, 0, 0);
			transformContainer.AddChild(scaledCb);

			// === Skewed Border ===
			let skewLabel = new TextBlock();
			skewLabel.Text = "Skew (shear X):";
			skewLabel.Foreground = Color(180, 180, 180);
			transformContainer.AddChild(skewLabel);

			let skewedBorder = new Border();
			skewedBorder.Width = 120;
			skewedBorder.Height = 40;
			skewedBorder.Background = Color(100, 60, 140);
			skewedBorder.CornerRadius = 4;
			// Skew matrix: shear X by 0.3
			var skewMatrix = Matrix.Identity;
			skewMatrix.M21 = 0.3f;
			skewedBorder.RenderTransform = skewMatrix;
			skewedBorder.Margin = Thickness(20, 0, 0, 0);
			let skewText = new TextBlock();
			skewText.Text = "Skewed";
			skewText.Foreground = Color.White;
			skewText.HorizontalAlignment = .Center;
			skewText.VerticalAlignment = .Center;
			skewedBorder.AddChild(skewText);
			transformContainer.AddChild(skewedBorder);

			// === Flipped (mirrored) ===
			let flipLabel = new TextBlock();
			flipLabel.Text = "Flip (mirror X):";
			flipLabel.Foreground = Color(180, 180, 180);
			transformContainer.AddChild(flipLabel);

			let flippedBtn = new Button();
			flippedBtn.ContentText = "Flipped";
			flippedBtn.Padding = Thickness(20, 10, 20, 10);
			flippedBtn.RenderTransform = Matrix.CreateScale(-1.0f, 1.0f, 1.0f);
			flippedBtn.Margin = Thickness(100, 0, 0, 0); // Offset since it flips around center
			transformContainer.AddChild(flippedBtn);

			// === Combined Transform ===
			let combinedLabel = new TextBlock();
			combinedLabel.Text = "Combined (rotate + scale):";
			combinedLabel.Foreground = Color(180, 180, 180);
			transformContainer.AddChild(combinedLabel);

			let combinedBorder = new Border();
			combinedBorder.Width = 80;
			combinedBorder.Height = 50;
			combinedBorder.Background = Color(60, 120, 100);
			combinedBorder.CornerRadius = 6;
			// Combine rotation and scale
			let rotateMatrix = Matrix.CreateRotationZ(-10.0f * (Math.PI_f / 180.0f));
			let scaleMatrix = Matrix.CreateScale(1.3f, 1.3f, 1.0f);
			combinedBorder.RenderTransform = rotateMatrix * scaleMatrix;
			combinedBorder.Margin = Thickness(30, 0, 0, 0);
			let combinedText = new TextBlock();
			combinedText.Text = "Both";
			combinedText.Foreground = Color.White;
			combinedText.HorizontalAlignment = .Center;
			combinedText.VerticalAlignment = .Center;
			combinedBorder.AddChild(combinedText);
			transformContainer.AddChild(combinedBorder);

			// === Animated rotation ===
			let animLabel = new TextBlock();
			animLabel.Text = "Animated rotation:";
			animLabel.Foreground = Color(180, 180, 180);
			transformContainer.AddChild(animLabel);

			let animRow = new StackPanel();
			animRow.Orientation = .Horizontal;
			animRow.Spacing = 15;

			let spinBox = new Border();
			spinBox.Width = 50;
			spinBox.Height = 50;
			spinBox.Background = Color(200, 100, 50);
			spinBox.CornerRadius = 8;
			let spinText = new TextBlock();
			spinText.Text = "Spin";
			spinText.Foreground = Color.White;
			spinText.HorizontalAlignment = .Center;
			spinText.VerticalAlignment = .Center;
			spinBox.AddChild(spinText);
			spinBox.Margin = Thickness(30, 0, 0, 0);

			let spinBtn = new Button();
			spinBtn.ContentText = "Spin 360°";
			spinBtn.Padding = Thickness(12, 6, 12, 6);
			spinBtn.Click.Subscribe(new (sender) => {
				let spinAnim = new FloatAnimation(0, 360);
				spinAnim.Duration = 1.0f;
				spinAnim.Easing = .QuadraticInOut;
				spinAnim.OnValueChanged = new (value) => {
					spinBox.RenderTransform = Matrix.CreateRotationZ(value * (Math.PI_f / 180.0f));
				};
				spinAnim.Completed.Subscribe(new (anim) => {
					spinBox.RenderTransform = Matrix.Identity; // Reset
				});
				mUIContext.Animations.Add(spinAnim);
			});

			animRow.AddChild(spinBtn);
			animRow.AddChild(spinBox);
			transformContainer.AddChild(animRow);

			panel.AddChild(transformContainer);
		});

		// Assemble columns
		columns.AddChild(leftColumn);
		columns.AddChild(middleColumn);
		columns.AddChild(rightColumn);
		scrollViewer.Content = columns;
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

		// Update cursor based on hovered element
		UpdateCursor(input.Mouse);

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

	/// Updates the mouse cursor based on the hovered UI element.
	private void UpdateCursor(Sedulous.Shell.Input.IMouse mouse)
	{
		let uiCursor = mUIContext.CurrentCursor;
		if (uiCursor != mLastUICursor)
		{
			mLastUICursor = uiCursor;
			mouse.Cursor = MapCursor(uiCursor);
		}
	}

	/// Maps UI CursorType to Shell CursorType.
	private static Sedulous.Shell.Input.CursorType MapCursor(Sedulous.UI.CursorType uiCursor)
	{
		switch (uiCursor)
		{
		case .Default:    return .Default;
		case .Text:       return .Text;
		case .Wait:       return .Wait;
		case .Crosshair:  return .Crosshair;
		case .Progress:   return .Progress;
		case .Move:       return .Move;
		case .NotAllowed: return .NotAllowed;
		case .Pointer:    return .Pointer;
		case .ResizeEW:   return .ResizeEW;
		case .ResizeNS:   return .ResizeNS;
		case .ResizeNWSE: return .ResizeNWSE;
		case .ResizeNESW: return .ResizeNESW;
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
			mUIContext.DebugSettings.TransformDebugOverlay = mUIContext.DebugSettings.ShowLayoutBounds;
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
