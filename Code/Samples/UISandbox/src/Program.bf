namespace UISandbox;

using System;
using System.Collections;
using System.IO;
using Sedulous.Mathematics;
using Sedulous.RHI;
using SampleFramework;
using Sedulous.Drawing;
using Sedulous.Fonts;
using Sedulous.UI;
using Sedulous.Drawing.Fonts;
using Sedulous.Drawing.Renderer;
using Sedulous.Shell.Input;
using Sedulous.UI.Shell;
using Sedulous.Shaders;

// Type alias to resolve ambiguity
typealias RHITexture = Sedulous.RHI.ITexture;

/// Uniform buffer data for the projection matrix (used by quad shader).
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
	private ShellClipboardAdapter mClipboard ~ delete _;
	private FontService mFontService;
	private TooltipService mTooltipService;
	private delegate void(StringView) mTextInputDelegate;

	// Drawing context (created after font service)
	private DrawContext mDrawContext ~ delete _;

	private DockPanel mUIRoot ~ delete _;

	// UI Renderer
	// NOTE: Must be cleaned up in OnCleanup(), not destructor, because Device is destroyed in Application.Cleanup()
	private DrawingRenderer mDrawingRenderer;

	// Shader system
	private NewShaderSystem mShaderSystem;

	// MSAA resources
	private const uint32 MSAA_SAMPLES = 4;
	private bool mUseMSAA = true;
	private RHITexture mMsaaTexture;
	private ITextureView mMsaaTextureView;
	private RHITexture mResolveTexture;
	private ITextureView mResolveTextureView;

	// Full-screen quad for displaying MSAA result
	private IBuffer mQuadVertexBuffer;
	private IShaderModule mQuadVertShader;
	private IShaderModule mQuadFragShader;
	private IBindGroupLayout mQuadBindGroupLayout;
	private IBindGroup mQuadBindGroup;
	private IPipelineLayout mQuadPipelineLayout;
	private IRenderPipeline mQuadPipeline;
	private ISampler mQuadSampler;

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
		if (!InitializeFonts())
			return false;

		// Initialize shader system
		mShaderSystem = new NewShaderSystem();
		String shaderPath = scope .();
		GetAssetPath("Render/shaders", shaderPath);
		if (mShaderSystem.Initialize(Device, scope StringView[](shaderPath)) case .Err)
		{
			Console.WriteLine("Failed to initialize shader system");
			return false;
		}

		// Create draw context with font service (auto-sets WhitePixelUV)
		mDrawContext = new DrawContext(mFontService);

		// Initialize UI Renderer
		mDrawingRenderer = new DrawingRenderer();
		if (mDrawingRenderer.Initialize(Device, SwapChain.Format, MAX_FRAMES_IN_FLIGHT, mShaderSystem) case .Err)
		{
			Console.WriteLine("Failed to initialize UI renderer");
			return false;
		}

		if (!CreateMsaaTargets())
			return false;

		if (!CreateQuadResources())
			return false;

		// Initialize UI
		if (!InitializeUI())
			return false;

		Console.WriteLine("Press F10 to toggle MSAA (currently ON)");
		return true;
	}

	private bool InitializeFonts()
	{
		mFontService = new FontService();

		String fontPath = scope .();
		GetAssetPath("framework/fonts/roboto/Roboto-Regular.ttf", fontPath);

		FontLoadOptions options = .ExtendedLatin;
		options.PixelHeight = 16;

		if (mFontService.LoadFont("Roboto", fontPath, options) case .Err)
		{
			Console.WriteLine(scope $"Failed to load font: {fontPath}");
			return false;
		}

		return true;
	}

	private bool CreateMsaaTargets()
	{
		// Create 4x MSAA render target
		TextureDescriptor msaaDesc = TextureDescriptor.Texture2D(
			SwapChain.Width, SwapChain.Height,
			SwapChain.Format, .RenderTarget | .CopySrc
		);
		msaaDesc.SampleCount = MSAA_SAMPLES;

		if (Device.CreateTexture(&msaaDesc) not case .Ok(let msaaTex))
		{
			Console.WriteLine("Failed to create MSAA texture");
			return false;
		}
		mMsaaTexture = msaaTex;

		TextureViewDescriptor viewDesc = .()
		{
			Format = SwapChain.Format,
			Dimension = .Texture2D,
			BaseMipLevel = 0,
			MipLevelCount = 1,
			BaseArrayLayer = 0,
			ArrayLayerCount = 1
		};
		if (Device.CreateTextureView(mMsaaTexture, &viewDesc) not case .Ok(let msaaView))
		{
			Console.WriteLine("Failed to create MSAA texture view");
			return false;
		}
		mMsaaTextureView = msaaView;

		// Create single-sample resolve target
		TextureDescriptor resolveDesc = TextureDescriptor.Texture2D(
			SwapChain.Width, SwapChain.Height,
			SwapChain.Format, .RenderTarget | .Sampled | .CopyDst
		);

		if (Device.CreateTexture(&resolveDesc) not case .Ok(let resolveTex))
		{
			Console.WriteLine("Failed to create resolve texture");
			return false;
		}
		mResolveTexture = resolveTex;

		if (Device.CreateTextureView(mResolveTexture, &viewDesc) not case .Ok(let resolveView))
		{
			Console.WriteLine("Failed to create resolve texture view");
			return false;
		}
		mResolveTextureView = resolveView;

		Console.WriteLine(scope $"MSAA targets created: {SwapChain.Width}x{SwapChain.Height}, {MSAA_SAMPLES}x samples");
		return true;
	}

	private void DestroyMsaaTargets()
	{
		if (mQuadBindGroup != null) { delete mQuadBindGroup; mQuadBindGroup = null; }
		if (mResolveTextureView != null) { delete mResolveTextureView; mResolveTextureView = null; }
		if (mResolveTexture != null) { delete mResolveTexture; mResolveTexture = null; }
		if (mMsaaTextureView != null) { delete mMsaaTextureView; mMsaaTextureView = null; }
		if (mMsaaTexture != null) { delete mMsaaTexture; mMsaaTexture = null; }
	}

	private bool RecreateMsaaTargets()
	{
		DestroyMsaaTargets();

		if (!CreateMsaaTargets())
			return false;

		// Recreate quad bind group with new resolve texture
		BindGroupEntry[2] quadBindEntries = .(
			BindGroupEntry.Texture(0, mResolveTextureView),
			BindGroupEntry.Sampler(0, mQuadSampler)
		);
		BindGroupDescriptor quadBindDesc = .(mQuadBindGroupLayout, quadBindEntries);
		if (Device.CreateBindGroup(&quadBindDesc) not case .Ok(let quadGroup))
			return false;
		mQuadBindGroup = quadGroup;

		return true;
	}

	private bool CreateQuadResources()
	{
		// Full-screen quad vertices (position + uv)
		// UV is flipped vertically to account for texture coordinate system
		float[24] quadVerts = .(
			-1.0f, -1.0f, 0.0f, 0.0f, // Bottom-left
			 1.0f, -1.0f, 1.0f, 0.0f, // Bottom-right
			 1.0f,  1.0f, 1.0f, 1.0f, // Top-right
			-1.0f, -1.0f, 0.0f, 0.0f, // Bottom-left
			 1.0f,  1.0f, 1.0f, 1.0f, // Top-right
			-1.0f,  1.0f, 0.0f, 1.0f  // Top-left
		);

		BufferDescriptor quadDesc = .()
		{
			Size = (uint64)(sizeof(float) * quadVerts.Count),
			Usage = .Vertex,
			MemoryAccess = .Upload
		};

		if (Device.CreateBuffer(&quadDesc) not case .Ok(let qvb))
			return false;
		mQuadVertexBuffer = qvb;
		Device.Queue.WriteBuffer(mQuadVertexBuffer, 0, .((uint8*)&quadVerts, (int)quadDesc.Size));

		// Quad shaders
		String quadVertSrc = """
			struct VSOutput {
			    float4 position : SV_Position;
			    float2 uv : TEXCOORD0;
			};
			VSOutput main(float2 pos : POSITION, float2 uv : TEXCOORD0) {
			    VSOutput output;
			    output.position = float4(pos, 0.0, 1.0);
			    output.uv = uv;
			    return output;
			}
			""";

		String quadFragSrc = """
			Texture2D tex : register(t0);
			SamplerState samp : register(s0);
			float4 main(float4 pos : SV_Position, float2 uv : TEXCOORD0) : SV_Target {
			    return tex.Sample(samp, uv);
			}
			""";

		if (ShaderUtils.CompileShader(Device, quadVertSrc, "main", .Vertex) not case .Ok(let qvs))
		{
			Console.WriteLine("Failed to compile quad vertex shader");
			return false;
		}
		mQuadVertShader = qvs;

		if (ShaderUtils.CompileShader(Device, quadFragSrc, "main", .Fragment) not case .Ok(let qfs))
		{
			Console.WriteLine("Failed to compile quad fragment shader");
			return false;
		}
		mQuadFragShader = qfs;

		// Sampler
		SamplerDescriptor samplerDesc = .();
		if (Device.CreateSampler(&samplerDesc) not case .Ok(let sampler))
			return false;
		mQuadSampler = sampler;

		// Bind group layout for texture+sampler
		BindGroupLayoutEntry[2] quadLayoutEntries = .(
			BindGroupLayoutEntry.SampledTexture(0, .Fragment),
			BindGroupLayoutEntry.Sampler(0, .Fragment)
		);
		BindGroupLayoutDescriptor quadLayoutDesc = .(quadLayoutEntries);
		if (Device.CreateBindGroupLayout(&quadLayoutDesc) not case .Ok(let quadLayout))
			return false;
		mQuadBindGroupLayout = quadLayout;

		// Bind group
		BindGroupEntry[2] quadBindEntries = .(
			BindGroupEntry.Texture(0, mResolveTextureView),
			BindGroupEntry.Sampler(0, mQuadSampler)
		);
		BindGroupDescriptor quadBindDesc = .(mQuadBindGroupLayout, quadBindEntries);
		if (Device.CreateBindGroup(&quadBindDesc) not case .Ok(let quadGroup))
			return false;
		mQuadBindGroup = quadGroup;

		// Pipeline layout
		IBindGroupLayout[1] quadLayouts = .(mQuadBindGroupLayout);
		PipelineLayoutDescriptor quadPipelineLayoutDesc = .(quadLayouts);
		if (Device.CreatePipelineLayout(&quadPipelineLayoutDesc) not case .Ok(let quadPipelineLayout))
			return false;
		mQuadPipelineLayout = quadPipelineLayout;

		// Vertex layout
		VertexAttribute[2] quadAttributes = .(
			.(VertexFormat.Float2, 0, 0),
			.(VertexFormat.Float2, 8, 1)
		);
		VertexBufferLayout[1] quadVertexBuffers = .(
			.((uint64)(sizeof(float) * 4), quadAttributes)
		);

		// Quad pipeline
		ColorTargetState[1] quadColorTargets = .(.(SwapChain.Format));
		RenderPipelineDescriptor quadPipelineDesc = .()
		{
			Layout = mQuadPipelineLayout,
			Vertex = .()
			{
				Shader = .(mQuadVertShader, "main"),
				Buffers = quadVertexBuffers
			},
			Fragment = .()
			{
				Shader = .(mQuadFragShader, "main"),
				Targets = quadColorTargets
			},
			Primitive = .() { Topology = .TriangleList, CullMode = .None },
			Multisample = .() { Count = 1, Mask = uint32.MaxValue }
		};

		if (Device.CreateRenderPipeline(&quadPipelineDesc) not case .Ok(let quadPipeline))
			return false;
		mQuadPipeline = quadPipeline;

		return true;
	}

	private bool InitializeUI()
	{
		mUIContext = new UIContext();

		mUIContext.DebugSettings.ShowLayoutBounds = false;
		mUIContext.DebugSettings.ShowMargins = mUIContext.DebugSettings.ShowLayoutBounds;
		mUIContext.DebugSettings.ShowPadding = mUIContext.DebugSettings.ShowLayoutBounds;
		mUIContext.DebugSettings.ShowFocused = mUIContext.DebugSettings.ShowLayoutBounds;

		// Register clipboard (using SDL3 system clipboard)
		mClipboard = new ShellClipboardAdapter(Shell.Clipboard);
		mUIContext.RegisterClipboard(mClipboard);

		// Register font service
		mUIContext.RegisterService<IFontService>(mFontService);

		// Register theme
		let theme = new DefaultTheme();
		mUIContext.RegisterService<ITheme>(theme);

		// Register tooltip service
		mTooltipService = new TooltipService();
		mUIContext.RegisterService<ITooltipService>(mTooltipService);

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
		mUIRoot = new DockPanel();
		mUIRoot.Background = Color(30, 30, 40, 255);

		// Header
		let header = new StackPanel();
		header.Orientation = .Horizontal;
		header.Background = Color(50, 50, 70, 255);
		header.Padding = Thickness(10, 5, 10, 5);
		mUIRoot.SetDock(header, .Top);

		let title = new TextBlock();
		title.Text = "Sedulous UI Sandbox";
		title.Foreground = Color.White;
		title.VerticalAlignment = .Center;
		header.AddChild(title);

		// Spacer
		let spacer = new Border();
		spacer.Width = 40;
		header.AddChild(spacer);

		// Theme selector label
		let themeLabel = new TextBlock();
		themeLabel.Text = "Theme:";
		themeLabel.Foreground = Color(180, 180, 180);
		themeLabel.VerticalAlignment = .Center;
		themeLabel.Margin = Thickness(0, 0, 10, 0);
		header.AddChild(themeLabel);

		// Theme radio buttons
		let lightRadio = new RadioButton("Light", "theme");
		lightRadio.Foreground = Color.White;
		lightRadio.IsChecked = true;
		lightRadio.VerticalAlignment = .Center;
		lightRadio.Margin = Thickness(0, 0, 15, 0);
		lightRadio.Click.Subscribe(new (sender) => {
			mUIContext.SetTheme(new DefaultTheme());
		});
		header.AddChild(lightRadio);

		let darkRadio = new RadioButton("Dark", "theme");
		darkRadio.Foreground = Color.White;
		darkRadio.VerticalAlignment = .Center;
		darkRadio.Margin = Thickness(0, 0, 15, 0);
		darkRadio.Click.Subscribe(new (sender) => {
			mUIContext.SetTheme(new DarkTheme());
		});
		header.AddChild(darkRadio);

		let gameRadio = new RadioButton("Game", "theme");
		gameRadio.Foreground = Color.White;
		gameRadio.VerticalAlignment = .Center;
		gameRadio.Click.Subscribe(new (sender) => {
			mUIContext.SetTheme(new GameTheme());
		});
		header.AddChild(gameRadio);

		// Scale selector spacer
		let scaleSpacer = new Border();
		scaleSpacer.Width = 40;
		header.AddChild(scaleSpacer);

		// Scale selector label
		let scaleLabel = new TextBlock();
		scaleLabel.Text = "Scale:";
		scaleLabel.Foreground = Color(180, 180, 180);
		scaleLabel.VerticalAlignment = .Center;
		scaleLabel.Margin = Thickness(0, 0, 10, 0);
		header.AddChild(scaleLabel);

		// Scale radio buttons
		let scale08Radio = new RadioButton("0.8x", "scale");
		scale08Radio.Foreground = Color.White;
		scale08Radio.VerticalAlignment = .Center;
		scale08Radio.Margin = Thickness(0, 0, 15, 0);
		scale08Radio.Click.Subscribe(new (sender) => {
			mUIContext.Scale = 0.8f;
		});
		header.AddChild(scale08Radio);

		let scale10Radio = new RadioButton("1.0x", "scale");
		scale10Radio.Foreground = Color.White;
		scale10Radio.IsChecked = true;
		scale10Radio.VerticalAlignment = .Center;
		scale10Radio.Margin = Thickness(0, 0, 15, 0);
		scale10Radio.Click.Subscribe(new (sender) => {
			mUIContext.Scale = 1.0f;
		});
		header.AddChild(scale10Radio);

		let scale15Radio = new RadioButton("1.5x", "scale");
		scale15Radio.Foreground = Color.White;
		scale15Radio.VerticalAlignment = .Center;
		scale15Radio.Click.Subscribe(new (sender) => {
			mUIContext.Scale = 1.5f;
		});
		header.AddChild(scale15Radio);

		mUIRoot.AddChild(header);

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

		// Section: Context Menu
		AddSection(content, "Context Menu", scope (panel) => {
			let desc = new TextBlock();
			desc.Text = "Right-click the area below:";
			desc.Foreground = Color(150, 150, 150);
			panel.AddChild(desc);

			let contextArea = new ContextMenuArea(mUIContext);
			contextArea.Width = 300;
			contextArea.Height = 60;
			contextArea.Background = Color(50, 60, 70);
			contextArea.CornerRadius = 4;

			let areaLabel = new TextBlock();
			areaLabel.Text = "Right-click here";
			areaLabel.Foreground = Color(200, 200, 200);
			areaLabel.TextAlignment = .Center;
			areaLabel.HorizontalAlignment = .Stretch;
			areaLabel.VerticalAlignment = .Center;
			contextArea.Child = areaLabel;

			panel.AddChild(contextArea);
		});

		// Section: Drag and Drop
		AddSection(content, "Drag and Drop", scope (panel) => {
			let desc = new TextBlock();
			desc.Text = "Drag colored boxes to the drop area:";
			desc.Foreground = Color(150, 150, 150);
			panel.AddChild(desc);

			// Drag sources row
			let dragRow = new StackPanel();
			dragRow.Orientation = .Horizontal;
			dragRow.Spacing = 10;

			let redDrag = new DraggableBox(mUIContext, "Red", Color(180, 60, 60));
			redDrag.Width = 60;
			redDrag.Height = 40;
			dragRow.AddChild(redDrag);

			let greenDrag = new DraggableBox(mUIContext, "Green", Color(60, 180, 60));
			greenDrag.Width = 60;
			greenDrag.Height = 40;
			dragRow.AddChild(greenDrag);

			let blueDrag = new DraggableBox(mUIContext, "Blue", Color(60, 60, 180));
			blueDrag.Width = 60;
			blueDrag.Height = 40;
			dragRow.AddChild(blueDrag);

			panel.AddChild(dragRow);

			// Drop target
			let dropTarget = new DropTargetBox();
			dropTarget.Width = 300;
			dropTarget.Height = 60;
			dropTarget.Margin = Thickness(0, 10, 0, 0);
			panel.AddChild(dropTarget);
		});

		// Section: ListBox
		AddSection(content, "ListBox", scope (panel) => {
			let desc = new TextBlock();
			desc.Text = "Select items (supports multi-select with Ctrl/Shift):";
			desc.Foreground = Color(150, 150, 150);
			panel.AddChild(desc);

			let listBox = new ListBox();
			listBox.Width = 300;
			listBox.Height = 120;
			listBox.SelectionMode = .Extended;
			listBox.AddItem("Item 1 - Apple");
			listBox.AddItem("Item 2 - Banana");
			listBox.AddItem("Item 3 - Cherry");
			listBox.AddItem("Item 4 - Date");
			listBox.AddItem("Item 5 - Elderberry");
			listBox.AddItem("Item 6 - Fig");
			listBox.AddItem("Item 7 - Grape");
			listBox.SelectedIndex = 0;
			listBox.SelectionChanged.Subscribe(new (lb, oldIdx, newIdx) => {
				Console.WriteLine(scope $"ListBox selection: {oldIdx} -> {newIdx}");
			});
			panel.AddChild(listBox);
		});

		// Section: ComboBox
		AddSection(content, "ComboBox", scope (panel) => {
			let desc = new TextBlock();
			desc.Text = "Dropdown selection:";
			desc.Foreground = Color(150, 150, 150);
			panel.AddChild(desc);

			let combo = new ComboBox();
			combo.Width = 200;
			combo.PlaceholderText = "Select a fruit...";
			combo.AddItem("Apple");
			combo.AddItem("Banana");
			combo.AddItem("Cherry");
			combo.AddItem("Date");
			combo.AddItem("Elderberry");
			combo.SelectionChanged.Subscribe(new (cb, oldIdx, newIdx) => {
				Console.WriteLine(scope $"ComboBox selection: {cb.SelectedItem}");
			});
			panel.AddChild(combo);
		});

		// Section: Tooltip
		AddSection(content, "Tooltip", scope (panel) => {
			let desc = new TextBlock();
			desc.Text = "Hover over buttons for tooltips:";
			desc.Foreground = Color(150, 150, 150);
			panel.AddChild(desc);

			let hstack = new StackPanel();
			hstack.Orientation = .Horizontal;
			hstack.Spacing = 10;

			let btn1 = new Button();
			btn1.ContentText = "Save";
			btn1.Padding = Thickness(15, 8, 15, 8);
			mTooltipService.SetTooltip(btn1, "Save the current document (Ctrl+S)");
			hstack.AddChild(btn1);

			let btn2 = new Button();
			btn2.ContentText = "Open";
			btn2.Padding = Thickness(15, 8, 15, 8);
			mTooltipService.SetTooltip(btn2, "Open an existing document (Ctrl+O)");
			hstack.AddChild(btn2);

			let btn3 = new Button();
			btn3.ContentText = "Help";
			btn3.Padding = Thickness(15, 8, 15, 8);
			mTooltipService.SetTooltip(btn3, "Show help and documentation (F1)");
			hstack.AddChild(btn3);

			panel.AddChild(hstack);
		});

		// Section: MessageBox/Dialog
		AddSection(content, "Dialog & MessageBox", scope (panel) => {
			let desc = new TextBlock();
			desc.Text = "Click buttons to show dialogs:";
			desc.Foreground = Color(150, 150, 150);
			panel.AddChild(desc);

			let hstack = new StackPanel();
			hstack.Orientation = .Horizontal;
			hstack.Spacing = 10;

			let infoBtn = new Button();
			infoBtn.ContentText = "Info";
			infoBtn.Padding = Thickness(15, 8, 15, 8);
			infoBtn.Click.Subscribe(new [&](sender) => {
				MessageBox.Show(mUIContext, "This is an informational message.", "Information", .OK);
			});
			hstack.AddChild(infoBtn);

			let questionBtn = new Button();
			questionBtn.ContentText = "Question";
			questionBtn.Padding = Thickness(15, 8, 15, 8);
			questionBtn.Click.Subscribe(new [&](sender) => {
				MessageBox.ShowQuestion(mUIContext, "Do you want to proceed with this action?");
			});
			hstack.AddChild(questionBtn);

			let errorBtn = new Button();
			errorBtn.ContentText = "Error";
			errorBtn.Padding = Thickness(15, 8, 15, 8);
			errorBtn.Click.Subscribe(new [&](sender) => {
				MessageBox.ShowError(mUIContext, "An error has occurred while processing your request.");
			});
			hstack.AddChild(errorBtn);

			panel.AddChild(hstack);
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
			cell00.Child = label00;
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
			cell01.Child = label01;
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
			cell02.Child = label02;
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
			cell10.Child = label10;
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
			cell20.Child = label20;
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
			cell21.Child = label21;
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
			topDock.Child = topLabel;
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
			bottomDock.Child = bottomLabel;
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
			leftDock.Child = leftLabel;
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
			rightDock.Child = rightLabel;
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
			centerDock.Child = centerLabel;
			dockPanel.AddChild(centerDock);

			panel.AddChild(dockPanel);
		});

		// Section: SplitPanel (middle column)
		AddSection(middleColumn, "SplitPanel", scope (panel) => {
			let desc = new TextBlock();
			desc.Text = "Drag the splitter to resize panels:";
			desc.Foreground = Color(150, 150, 150);
			panel.AddChild(desc);

			// Horizontal split
			let hSplit = new SplitPanel();
			hSplit.Width = 300;
			hSplit.Height = 80;
			hSplit.Orientation = .Horizontal;
			hSplit.SplitterPosition = 120;

			let leftPane = new Border();
			leftPane.Background = Color(80, 60, 100);
			let leftLabel = new TextBlock();
			leftLabel.Text = "Left";
			leftLabel.Foreground = Color.White;
			leftLabel.HorizontalAlignment = .Center;
			leftLabel.VerticalAlignment = .Center;
			leftPane.Child = leftLabel;
			hSplit.Panel1 = leftPane;

			let rightPane = new Border();
			rightPane.Background = Color(60, 100, 80);
			let rightLabel = new TextBlock();
			rightLabel.Text = "Right";
			rightLabel.Foreground = Color.White;
			rightLabel.HorizontalAlignment = .Center;
			rightLabel.VerticalAlignment = .Center;
			rightPane.Child = rightLabel;
			hSplit.Panel2 = rightPane;

			panel.AddChild(hSplit);

			// Vertical split
			let vDesc = new TextBlock();
			vDesc.Text = "Vertical split:";
			vDesc.Foreground = Color(150, 150, 150);
			vDesc.Margin = Thickness(0, 10, 0, 0);
			panel.AddChild(vDesc);

			let vSplit = new SplitPanel();
			vSplit.Width = 300;
			vSplit.Height = 100;
			vSplit.Orientation = .Vertical;
			vSplit.SplitterPosition = 40;

			let topPane = new Border();
			topPane.Background = Color(100, 80, 60);
			let topLabel = new TextBlock();
			topLabel.Text = "Top";
			topLabel.Foreground = Color.White;
			topLabel.HorizontalAlignment = .Center;
			topLabel.VerticalAlignment = .Center;
			topPane.Child = topLabel;
			vSplit.Panel1 = topPane;

			let bottomPane = new Border();
			bottomPane.Background = Color(60, 80, 100);
			let bottomLabel = new TextBlock();
			bottomLabel.Text = "Bottom";
			bottomLabel.Foreground = Color.White;
			bottomLabel.HorizontalAlignment = .Center;
			bottomLabel.VerticalAlignment = .Center;
			bottomPane.Child = bottomLabel;
			vSplit.Panel2 = bottomPane;

			panel.AddChild(vSplit);
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

		// Section: Dockable Panels (right column)
		AddSection(rightColumn, "Dockable Panels", scope (panel) => {
			let desc = new TextBlock();
			desc.Text = "DockManager with dockable panels:";
			desc.Foreground = Color(150, 150, 150);
			panel.AddChild(desc);

			// Create a mini dock manager demo
			let dockManager = new DockManager();
			dockManager.Width = 350;
			dockManager.Height = 200;

			// Center content
			let centerContent = new Border();
			centerContent.Background = Color(50, 50, 60);
			let centerLabel = new TextBlock();
			centerLabel.Text = "Main Content Area";
			centerLabel.Foreground = Color.White;
			centerLabel.HorizontalAlignment = .Center;
			centerLabel.VerticalAlignment = .Center;
			centerContent.Child = centerLabel;
			dockManager.CenterContent = centerContent;

			// Left docked panel
			let leftPanel = new DockablePanel();
			leftPanel.Title = "Explorer";
			leftPanel.Width = .Fixed(100);
			let leftContent = new TextBlock();
			leftContent.Text = "Files";
			leftContent.Foreground = Color(180, 180, 180);
			leftContent.HorizontalAlignment = .Center;
			leftContent.VerticalAlignment = .Center;
			leftPanel.PanelContent = leftContent;
			dockManager.Dock(leftPanel, .Left);

			// Bottom docked panel
			let bottomPanel = new DockablePanel();
			bottomPanel.Title = "Output";
			bottomPanel.Height = .Fixed(50);
			let bottomContent = new TextBlock();
			bottomContent.Text = "Console output...";
			bottomContent.Foreground = Color(180, 180, 180);
			bottomContent.Padding = Thickness(5);
			bottomPanel.PanelContent = bottomContent;
			dockManager.Dock(bottomPanel, .Bottom);

			panel.AddChild(dockManager);

			// Float button
			let floatBtn = new Button();
			floatBtn.ContentText = "Float Left Panel";
			floatBtn.Padding = Thickness(10, 5, 10, 5);
			floatBtn.Margin = Thickness(0, 10, 0, 0);
			floatBtn.Click.Subscribe(new [=](sender) => {
				if (leftPanel.IsDocked)
				{
					// Set size for floating panel
					leftPanel.Width = .Fixed(120);
					leftPanel.Height = .Fixed(100);
					dockManager.Float(leftPanel, 120, 50);
				}
				else
				{
					// Reset size for docked panel
					leftPanel.Width = .Fixed(100);
					leftPanel.Height = .Auto;
					dockManager.Dock(leftPanel, .Left);
				}
			});
			panel.AddChild(floatBtn);
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
			skewText.TextAlignment = .Center;
			skewText.HorizontalAlignment = .Stretch;
			skewText.VerticalAlignment = .Center;
			skewedBorder.Child = skewText;
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
			combinedText.TextAlignment = .Center;
			combinedText.HorizontalAlignment = .Stretch;
			combinedText.VerticalAlignment = .Center;
			combinedBorder.Child = combinedText;
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
			spinText.TextAlignment = .Center;
			spinText.HorizontalAlignment = .Stretch;
			spinText.VerticalAlignment = .Center;
			spinText.RenderTransform = Matrix.CreateRotationZ(Math.PI_f / 2.0f); // 90 degrees - vertical text
			spinText.RenderTransformOrigin = .(0.5f, 0.5f); // Center origin
			spinBox.Child = spinText;
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
		mUIRoot.AddChild(scrollViewer);

		mUIContext.RootElement = mUIRoot;
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

		// Update tooltip system
		mTooltipService.Update(mUIContext, deltaTime);
	}

	private void RouteInput()
	{
		let input = Shell.InputManager;

		// Get keyboard modifiers for mouse events
		let mods = GetModifiers(input.Keyboard);

		// Mouse position
		mUIContext.ProcessMouseMove(input.Mouse.X, input.Mouse.Y, mods);

		// Update cursor based on hovered element
		UpdateCursor(input.Mouse);

		// Mouse buttons - pass modifiers for Ctrl/Shift+Click support
		if (input.Mouse.IsButtonPressed(.Left))
			mUIContext.ProcessMouseDown(.Left, input.Mouse.X, input.Mouse.Y, mods);
		if (input.Mouse.IsButtonReleased(.Left))
			mUIContext.ProcessMouseUp(.Left, input.Mouse.X, input.Mouse.Y, mods);

		if (input.Mouse.IsButtonPressed(.Right))
			mUIContext.ProcessMouseDown(.Right, input.Mouse.X, input.Mouse.Y, mods);
		if (input.Mouse.IsButtonReleased(.Right))
			mUIContext.ProcessMouseUp(.Right, input.Mouse.X, input.Mouse.Y, mods);

		// Mouse wheel
		if (input.Mouse.ScrollY != 0)
			mUIContext.ProcessMouseWheel(input.Mouse.ScrollX, input.Mouse.ScrollY, input.Mouse.X, input.Mouse.Y, mods);

		// Keyboard - check each key
		for (int key = 0; key < (int)Sedulous.Shell.Input.KeyCode.Count; key++)
		{
			let shellKey = (Sedulous.Shell.Input.KeyCode)key;
			if (input.Keyboard.IsKeyPressed(shellKey))
			{
				mUIContext.ProcessKeyDown(MapKey(shellKey), 0, mods);

				// Generate text input for printable keys (fallback since SDL_StartTextInput not called)
				// Skip when Ctrl or Alt are held - those are shortcuts, not text input
				if (!mods.HasFlag(.Ctrl) && !mods.HasFlag(.Alt))
				{
					let c = KeyToChar(shellKey, mods.HasFlag(.Shift));
					if (c != '\0')
						mUIContext.ProcessTextInput(c);
				}
			}
			if (input.Keyboard.IsKeyReleased(shellKey))
				mUIContext.ProcessKeyUp(MapKey(shellKey), 0, mods);
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

	/// Converts a key code to a character (fallback for when SDL text input isn't active).
	/// Returns '\0' if the key doesn't produce a printable character.
	private static char32 KeyToChar(Sedulous.Shell.Input.KeyCode key, bool shift)
	{
		// Letters A-Z
		if (key >= .A && key <= .Z)
		{
			let baseChar = 'a' + (int)(key - .A);
			return shift ? (char32)((int)'A' + (int)(key - .A)) : (char32)baseChar;
		}

		// Common punctuation and numbers (US keyboard layout)
		switch (key)
		{
		// Top row numbers (keys are in 1-9,0 order)
		case .Num1: return shift ? '!' : '1';
		case .Num2: return shift ? '@' : '2';
		case .Num3: return shift ? '#' : '3';
		case .Num4: return shift ? '$' : '4';
		case .Num5: return shift ? '%' : '5';
		case .Num6: return shift ? '^' : '6';
		case .Num7: return shift ? '&' : '7';
		case .Num8: return shift ? '*' : '8';
		case .Num9: return shift ? '(' : '9';
		case .Num0: return shift ? ')' : '0';

		// Keypad numbers
		case .Keypad0: return '0';
		case .Keypad1: return '1';
		case .Keypad2: return '2';
		case .Keypad3: return '3';
		case .Keypad4: return '4';
		case .Keypad5: return '5';
		case .Keypad6: return '6';
		case .Keypad7: return '7';
		case .Keypad8: return '8';
		case .Keypad9: return '9';

		// Keypad operators
		case .KeypadDivide:   return '/';
		case .KeypadMultiply: return '*';
		case .KeypadMinus:    return '-';
		case .KeypadPlus:     return '+';
		case .KeypadPeriod:   return '.';

		// Punctuation
		case .Space:        return ' ';
		case .Tab:          return '\t';
		case .Minus:        return shift ? '_' : '-';
		case .Equals:       return shift ? '+' : '=';
		case .LeftBracket:  return shift ? '{' : '[';
		case .RightBracket: return shift ? '}' : ']';
		case .Backslash:    return shift ? '|' : '\\';
		case .Semicolon:    return shift ? ':' : ';';
		case .Apostrophe:   return shift ? '"' : '\'';
		case .Grave:        return shift ? '~' : '`';
		case .Comma:        return shift ? '<' : ',';
		case .Period:       return shift ? '>' : '.';
		case .Slash:        return shift ? '?' : '/';

		default:            return '\0';
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
		BuildDrawCommands();

		// Update DrawingRenderer with current frame data
		mDrawingRenderer.UpdateProjection(SwapChain.Width, SwapChain.Height, frameIndex);
		mDrawingRenderer.Prepare(mDrawContext.GetBatch(), frameIndex);
	}

	private void BuildDrawCommands()
	{
		mDrawContext.Clear();

		// Render UI
		mUIContext.Render(mDrawContext);

		// FPS overlay (top-right)
		float screenWidth = (float)SwapChain.Width;
		float screenHeight = (float)SwapChain.Height;
		let cachedFont = mFontService.GetFont(16);
		let atlasTexture = mFontService.GetAtlasTexture(cachedFont);
		let fpsText = scope $"FPS: {mCurrentFps}";
		mDrawContext.DrawText(fpsText, cachedFont.Atlas, atlasTexture, .(screenWidth - 80, 10 + cachedFont.Font.Metrics.Ascent), Color.Lime);

		// Debug toggle hint (bottom-left)
		float debugTextY = screenHeight - 10;
		if (mUIContext.DebugSettings.ShowLayoutBounds)
			mDrawContext.DrawText("F11: Debug ON", cachedFont.Atlas, atlasTexture, .(10, debugTextY), Color.Yellow);
		else
			mDrawContext.DrawText("F11: Debug OFF", cachedFont.Atlas, atlasTexture, .(10, debugTextY), Color.Gray);
	}

	protected override bool OnRenderFrame(ICommandEncoder encoder, int32 frameIndex)
	{
		if (mUseMSAA)
		{
			// Render to MSAA target using DrawingRenderer
			RenderPassColorAttachment[1] msaaAttachments = .(.(mMsaaTextureView)
				{
					LoadOp = .Clear,
					StoreOp = .Store,
					ClearValue = .(0.15f, 0.15f, 0.2f, 1.0f)
				});
			RenderPassDescriptor msaaPassDesc = .(msaaAttachments);

			let msaaPass = encoder.BeginRenderPass(&msaaPassDesc);
			if (msaaPass != null)
			{
				mDrawingRenderer.Render(msaaPass, SwapChain.Width, SwapChain.Height, frameIndex, useMsaa: true);
				msaaPass.End();
				delete msaaPass;
			}

			// Resolve MSAA to single-sample texture
			encoder.ResolveTexture(mMsaaTexture, mResolveTexture);

			// Draw resolved texture to swap chain
			let swapTextureView = SwapChain.CurrentTextureView;
			RenderPassColorAttachment[1] finalAttachments = .(.(swapTextureView)
				{
					LoadOp = .Clear,
					StoreOp = .Store,
					ClearValue = .(0.0f, 0.0f, 0.0f, 1.0f)
				});
			RenderPassDescriptor finalPassDesc = .(finalAttachments);

			let finalPass = encoder.BeginRenderPass(&finalPassDesc);
			if (finalPass != null)
			{
				finalPass.SetViewport(0, 0, SwapChain.Width, SwapChain.Height, 0, 1);
				finalPass.SetScissorRect(0, 0, SwapChain.Width, SwapChain.Height);
				finalPass.SetPipeline(mQuadPipeline);
				finalPass.SetBindGroup(0, mQuadBindGroup);
				finalPass.SetVertexBuffer(0, mQuadVertexBuffer, 0);
				finalPass.Draw(6, 1, 0, 0);
				finalPass.End();
				delete finalPass;
			}
		}
		else
		{
			// Render directly to swap chain (no MSAA)
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
				mDrawingRenderer.Render(renderPass, SwapChain.Width, SwapChain.Height, frameIndex, useMsaa: false);
				renderPass.End();
				delete renderPass;
			}
		}

		return true;
	}

	protected override void OnRender(IRenderPassEncoder renderPass)
	{
		// Not used - we use OnRenderFrame
	}

	protected override void OnKeyDown(Sedulous.Shell.Input.KeyCode key)
	{
		// Toggle MSAA with F10
		if (key == .F10)
		{
			mUseMSAA = !mUseMSAA;
			Console.WriteLine(scope $"MSAA: {mUseMSAA ? "ON (4x samples)" : "OFF"}");
		}

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

		// Recreate MSAA targets at new size
		RecreateMsaaTargets();
	}

	protected override void OnCleanup()
	{
		// Unsubscribe from text input events
		if (mTextInputDelegate != null)
		{
			Shell.InputManager.Keyboard.OnTextInput.Unsubscribe(mTextInputDelegate, false);
			delete mTextInputDelegate;
			mTextInputDelegate = null;
		}

		// Clean up services (registered with UIContext, but owned by us)
		if (mUIContext.GetService<ITheme>() case .Ok(let theme))
			delete theme;
		if (mTooltipService != null)
			delete mTooltipService;

		// Clean up MSAA quad resources
		if (mQuadPipeline != null) delete mQuadPipeline;
		if (mQuadPipelineLayout != null) delete mQuadPipelineLayout;
		if (mQuadBindGroup != null) delete mQuadBindGroup;
		if (mQuadBindGroupLayout != null) delete mQuadBindGroupLayout;
		if (mQuadFragShader != null) delete mQuadFragShader;
		if (mQuadVertShader != null) delete mQuadVertShader;
		if (mQuadVertexBuffer != null) delete mQuadVertexBuffer;
		if (mQuadSampler != null) delete mQuadSampler;

		// Clean up MSAA targets
		if (mResolveTextureView != null) delete mResolveTextureView;
		if (mResolveTexture != null) delete mResolveTexture;
		if (mMsaaTextureView != null) delete mMsaaTextureView;
		if (mMsaaTexture != null) delete mMsaaTexture;

		// Clean up UI Renderer (must be done before Device is destroyed in Application.Cleanup())
		if (mDrawingRenderer != null)
		{
			mDrawingRenderer.Dispose();
			delete mDrawingRenderer;
			mDrawingRenderer = null;
		}

		// Clean up font service (owns GPU atlas texture, delete after DrawingRenderer)
		if (mFontService != null)
			delete mFontService;

		// Clean up shader system
		if (mShaderSystem != null)
		{
			mShaderSystem.Dispose();
			delete mShaderSystem;
		}
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
