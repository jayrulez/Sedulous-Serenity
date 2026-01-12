namespace EngineAudio;

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
using Sedulous.UI.Renderer;
using Sedulous.Shell.Input;
using Sedulous.Shell.SDL3;
using Sedulous.Audio;
using Sedulous.Audio.SDL3;
using Sedulous.Audio.Decoders;

// Type aliases
typealias RHITexture = Sedulous.RHI.ITexture;
typealias DrawingTexture = Sedulous.Drawing.ITexture;

/// Clipboard adapter for UI.
class UIClipboardAdapter : Sedulous.UI.IClipboard
{
	private Sedulous.Shell.IClipboard mShellClipboard ~ delete _;

	public this()
	{
		mShellClipboard = new SDL3Clipboard();
	}

	public Result<void> GetText(String outText) => mShellClipboard.GetText(outText);
	public Result<void> SetText(StringView text) => mShellClipboard.SetText(text);
	public bool HasText => mShellClipboard.HasText;
}

/// Font service for UI.
class AudioFontService : IFontService
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
	public CachedFont GetFont(float pixelHeight) => mCachedFont;
	public CachedFont GetFont(StringView familyName, float pixelHeight) => mCachedFont;
	public DrawingTexture GetAtlasTexture(CachedFont font) => mFontTexture;
	public DrawingTexture GetAtlasTexture(StringView familyName, float pixelHeight) => mFontTexture;
	public void ReleaseFont(CachedFont font) { }
}

/// Audio track info.
class AudioTrack
{
	public String Name ~ delete _;
	public String Path ~ delete _;
	public AudioClip Clip;

	public this(StringView name, StringView path)
	{
		Name = new String(name);
		Path = new String(path);
	}
}

/// Engine Audio Sample - Audio Player with UI.
class EngineAudioSample : RHISampleApp
{
	// Audio system
	private SDL3AudioSystem mAudioSystem ~ delete _;
	private AudioDecoderFactory mDecoderFactory ~ delete _;
	private IAudioSource mCurrentSource;
	private List<AudioTrack> mTracks = new .() ~ DeleteContainerAndItems!(_);
	private int mCurrentTrackIndex = -1;
	private float mVolume = 0.7f;
	private bool mIsPlaying = false;

	// UI System
	private UIContext mUIContext ~ delete _;
	private UIClipboardAdapter mClipboard ~ delete _;
	private AudioFontService mFontService;
	private DarkTheme mTheme;
	private TooltipService mTooltipService;
	private delegate void(StringView) mTextInputDelegate;

	// Drawing
	private DrawContext mDrawContext = new .() ~ delete _;

	// Font resources
	private IFont mFont;
	private IFontAtlas mFontAtlas;
	private TextureRef mFontTextureRef ~ delete _;

	// UI Renderer
	private UIRenderer mUIRenderer;

	// GPU resources
	private RHITexture mAtlasTexture;
	private ITextureView mAtlasTextureView;

	// UI Elements (for updating)
	private TextBlock mNowPlayingLabel;
	private TextBlock mVolumeLabel;
	private StackPanel mTrackList;
	private Button mPlayPauseButton;

	public this() : base(.()
		{
			Title = "Engine Audio Player",
			Width = 800,
			Height = 600,
			ClearColor = .(0.1f, 0.1f, 0.15f, 1.0f)
		})
	{
	}

	protected override bool OnInitialize()
	{
		// Initialize audio
		if (!InitializeAudio())
			return false;

		// Initialize font
		if (!InitializeFont())
			return false;

		if (!CreateAtlasTexture())
			return false;

		// Initialize UI Renderer
		mUIRenderer = new UIRenderer();
		if (mUIRenderer.Initialize(Device, SwapChain.Format, MAX_FRAMES_IN_FLIGHT) case .Err)
		{
			Console.WriteLine("Failed to initialize UI renderer");
			return false;
		}
		mUIRenderer.SetTexture(mAtlasTextureView);

		let (u, v) = mFontAtlas.WhitePixelUV;
		mDrawContext.WhitePixelUV = .(u, v);

		// Initialize UI
		if (!InitializeUI())
			return false;

		// Load audio tracks
		LoadAudioTracks();

		return true;
	}

	private bool InitializeAudio()
	{
		Console.WriteLine("Initializing audio system...");

		mAudioSystem = new SDL3AudioSystem();
		if (!mAudioSystem.IsInitialized)
		{
			Console.WriteLine("ERROR: Failed to initialize audio system!");
			return false;
		}

		mDecoderFactory = new AudioDecoderFactory();
		mDecoderFactory.RegisterDefaultDecoders();

		Console.WriteLine($"Audio system initialized. Decoders: {mDecoderFactory.DecoderCount}");
		return true;
	}

	private bool InitializeFont()
	{
		String fontPath = scope .();
		GetAssetPath("framework/fonts/roboto/Roboto-Regular.ttf", fontPath);

		if (!File.Exists(fontPath))
		{
			Console.WriteLine($"Font not found: {fontPath}");
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
			mFontAtlas = atlas;
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
		return true;
	}

	private bool InitializeUI()
	{
		mUIContext = new UIContext();
		mUIContext.DebugSettings.ShowLayoutBounds = false;

		mClipboard = new UIClipboardAdapter();
		mUIContext.RegisterClipboard(mClipboard);

		mFontService = new AudioFontService(mFont, mFontAtlas, mFontTextureRef);
		mUIContext.RegisterService<IFontService>(mFontService);

		mTheme = new DarkTheme();
		mUIContext.RegisterService<ITheme>(mTheme);

		mTooltipService = new TooltipService();
		mUIContext.RegisterService<ITooltipService>(mTooltipService);

		mUIContext.SetViewportSize((float)SwapChain.Width, (float)SwapChain.Height);

		mTextInputDelegate = new => OnTextInput;
		Shell.InputManager.Keyboard.OnTextInput.Subscribe(mTextInputDelegate);

		BuildUI();
		return true;
	}

	private void OnTextInput(StringView text)
	{
		for (let c in text.DecodedChars)
			mUIContext.ProcessTextInput(c);
	}

	private void BuildUI()
	{
		let root = new DockPanel();
		root.Background = Color(25, 25, 35, 255);

		// Header
		let header = new Border();
		header.Background = Color(40, 40, 55, 255);
		header.Padding = Thickness(20, 15, 20, 15);
		root.SetDock(header, .Top);

		let headerContent = new StackPanel();
		headerContent.Orientation = .Vertical;
		headerContent.Spacing = 5;
		header.Child = headerContent;

		let title = new TextBlock();
		title.Text = "Audio Player";
		title.Foreground = Color.White;
		title.FontSize = 20;
		headerContent.AddChild(title);

		mNowPlayingLabel = new TextBlock();
		mNowPlayingLabel.Text = "No track selected";
		mNowPlayingLabel.Foreground = Color(150, 150, 160);
		headerContent.AddChild(mNowPlayingLabel);

		root.AddChild(header);

		// Controls bar
		let controlsBar = new Border();
		controlsBar.Background = Color(35, 35, 50, 255);
		controlsBar.Padding = Thickness(20, 10, 20, 10);
		root.SetDock(controlsBar, .Bottom);

		let controls = new StackPanel();
		controls.Orientation = .Horizontal;
		controls.Spacing = 15;
		controls.HorizontalAlignment = .Center;
		controlsBar.Child = controls;

		// Play/Pause button
		mPlayPauseButton = new Button();
		mPlayPauseButton.ContentText = "Play";
		mPlayPauseButton.Padding = Thickness(20, 8, 20, 8);
		mPlayPauseButton.Click.Subscribe(new (sender) => TogglePlayPause());
		controls.AddChild(mPlayPauseButton);

		// Stop button
		let stopBtn = new Button();
		stopBtn.ContentText = "Stop";
		stopBtn.Padding = Thickness(20, 8, 20, 8);
		stopBtn.Click.Subscribe(new (sender) => StopPlayback());
		controls.AddChild(stopBtn);

		// Separator
		let sep = new Border();
		sep.Width = 20;
		controls.AddChild(sep);

		// Volume down
		let volDown = new Button();
		volDown.ContentText = "-";
		volDown.Padding = Thickness(12, 8, 12, 8);
		volDown.Click.Subscribe(new (sender) => AdjustVolume(-0.1f));
		controls.AddChild(volDown);

		// Volume label
		mVolumeLabel = new TextBlock();
		mVolumeLabel.Text = "70%";
		mVolumeLabel.Foreground = Color.White;
		mVolumeLabel.VerticalAlignment = .Center;
		mVolumeLabel.Width = 50;
		mVolumeLabel.TextAlignment = .Center;
		controls.AddChild(mVolumeLabel);

		// Volume up
		let volUp = new Button();
		volUp.ContentText = "+";
		volUp.Padding = Thickness(12, 8, 12, 8);
		volUp.Click.Subscribe(new (sender) => AdjustVolume(0.1f));
		controls.AddChild(volUp);

		root.AddChild(controlsBar);

		// Track list
		let scrollViewer = new ScrollViewer();
		scrollViewer.Padding = Thickness(10);

		mTrackList = new StackPanel();
		mTrackList.Orientation = .Vertical;
		mTrackList.Spacing = 2;
		scrollViewer.Content = mTrackList;

		root.AddChild(scrollViewer);

		mUIContext.RootElement = root;
	}

	private void LoadAudioTracks()
	{
		String audioDir = scope .();
		GetAssetPath("samples/audio/kenney_rpg-audio/Audio", audioDir);

		Console.WriteLine($"Loading audio from: {audioDir}");

		if (!Directory.Exists(audioDir))
		{
			Console.WriteLine("Audio directory not found!");
			return;
		}

		// Find all OGG files
		for (let entry in Directory.EnumerateFiles(audioDir, "*.ogg"))
		{
			String fileName = scope .();
			entry.GetFileName(fileName);

			String fullPath = scope .();
			entry.GetFilePath(fullPath);

			let track = new AudioTrack(fileName, fullPath);
			mTracks.Add(track);
		}

		Console.WriteLine($"Found {mTracks.Count} audio files");

		// Build track list UI
		for (int i = 0; i < mTracks.Count; i++)
		{
			let track = mTracks[i];
			let trackIndex = i;

			let trackBtn = new Button();
			trackBtn.ContentText = track.Name;
			trackBtn.Padding = Thickness(10, 6, 10, 6);
			trackBtn.HorizontalAlignment = .Stretch;
			trackBtn.Click.Subscribe(new (sender) => { this.SelectTrack(trackIndex); });

			mTrackList.AddChild(trackBtn);
		}
	}

	private void SelectTrack(int index)
	{
		if (index < 0 || index >= mTracks.Count)
			return;

		mCurrentTrackIndex = index;
		let track = mTracks[index];

		Console.WriteLine($"Selected: {track.Name}");

		// Load clip if not already loaded
		if (track.Clip == null)
		{
			Console.WriteLine($"Decoding: {track.Path}");
			if (mDecoderFactory.DecodeFile(track.Path) case .Ok(let clip))
			{
				track.Clip = clip;
				Console.WriteLine($"Decoded: {clip.Duration:F2}s, {clip.SampleRate}Hz, {clip.Channels}ch");
			}
			else
			{
				Console.WriteLine("Failed to decode audio file!");
				return;
			}
		}

		// Update now playing label
		mNowPlayingLabel.Text = track.Name;

		// Auto-play
		PlayCurrentTrack();
	}

	private void PlayCurrentTrack()
	{
		if (mCurrentTrackIndex < 0 || mCurrentTrackIndex >= mTracks.Count)
			return;

		let track = mTracks[mCurrentTrackIndex];
		if (track.Clip == null)
			return;

		// Stop current playback
		StopPlayback();

		// Create new source and play
		mCurrentSource = mAudioSystem.CreateSource();
		if (mCurrentSource != null)
		{
			mCurrentSource.Volume = mVolume;
			mCurrentSource.Play(track.Clip);
			mIsPlaying = true;
			mPlayPauseButton.ContentText = "Pause";
		}
	}

	private void TogglePlayPause()
	{
		if (mCurrentSource == null)
		{
			// Nothing playing, try to play current track
			if (mCurrentTrackIndex >= 0)
				PlayCurrentTrack();
			return;
		}

		if (mIsPlaying)
		{
			mCurrentSource.Pause();
			mIsPlaying = false;
			mPlayPauseButton.ContentText = "Play";
		}
		else
		{
			mCurrentSource.Resume();
			mIsPlaying = true;
			mPlayPauseButton.ContentText = "Pause";
		}
	}

	private void StopPlayback()
	{
		if (mCurrentSource != null)
		{
			mCurrentSource.Stop();
			mAudioSystem.DestroySource(mCurrentSource);
			mCurrentSource = null;
		}
		mIsPlaying = false;
		mPlayPauseButton.ContentText = "Play";
	}

	private void AdjustVolume(float delta)
	{
		mVolume = Math.Clamp(mVolume + delta, 0.0f, 1.0f);

		if (mCurrentSource != null)
			mCurrentSource.Volume = mVolume;

		let pct = (int)(mVolume * 100);
		mVolumeLabel.Text = scope:: $"{pct}%";
	}

	protected override void OnUpdate(float deltaTime, float totalTime)
	{
		// Update audio system
		mAudioSystem.Update();

		// Check if track finished
		if (mCurrentSource != null && mCurrentSource.State == .Stopped && mIsPlaying)
		{
			mIsPlaying = false;
			mPlayPauseButton.ContentText = "Play";
		}

		// Process UI input
		ProcessUIInput();

		// Update UI
		mUIContext.Update(deltaTime, totalTime);
	}

	private void ProcessUIInput()
	{
		let mouse = Shell.InputManager.Mouse;
		let kb = Shell.InputManager.Keyboard;

		// Mouse position
		mUIContext.ProcessMouseMove(mouse.X, mouse.Y);

		// Mouse buttons
		if (mouse.IsButtonPressed(.Left))
			mUIContext.ProcessMouseDown(.Left, mouse.X, mouse.Y);
		if (mouse.IsButtonReleased(.Left))
			mUIContext.ProcessMouseUp(.Left, mouse.X, mouse.Y);

		// Mouse wheel
		if (mouse.ScrollX != 0 || mouse.ScrollY != 0)
			mUIContext.ProcessMouseWheel(mouse.ScrollX, mouse.ScrollY, mouse.X, mouse.Y);

		// Keyboard
		if (kb.IsKeyPressed(.Space))
			TogglePlayPause();
	}

	protected override bool OnRenderFrame(ICommandEncoder encoder, int32 frameIndex)
	{
		// Update UI and render to draw context
		mUIContext.Render(mDrawContext);

		// Prepare UI renderer
		let batch = mDrawContext.GetBatch();
		mUIRenderer.Prepare(batch, frameIndex);
		mUIRenderer.UpdateProjection(SwapChain.Width, SwapChain.Height, frameIndex);

		// Create render pass
		RenderPassColorAttachment[1] colorAttachments = .(.()
		{
			View = SwapChain.CurrentTextureView,
			LoadOp = .Clear,
			StoreOp = .Store,
			ClearValue = mConfig.ClearColor
		});

		RenderPassDescriptor renderPassDesc = .(colorAttachments);
		let renderPass = encoder.BeginRenderPass(&renderPassDesc);
		if (renderPass == null)
		{
			mDrawContext.Clear();
			return true;
		}
		defer delete renderPass;

		renderPass.SetViewport(0, 0, SwapChain.Width, SwapChain.Height, 0, 1);
		renderPass.SetScissorRect(0, 0, SwapChain.Width, SwapChain.Height);

		// Render UI
		mUIRenderer.Render(renderPass, SwapChain.Width, SwapChain.Height, frameIndex);

		renderPass.End();
		mDrawContext.Clear();

		return true; // We handled rendering
	}

	protected override void OnResize(uint32 width, uint32 height)
	{
		mUIContext?.SetViewportSize((float)width, (float)height);
	}

	protected override void OnCleanup()
	{
		StopPlayback();

		// Clean up tracks (clips are owned by tracks)
		for (let track in mTracks)
		{
			if (track.Clip != null)
				delete track.Clip;
		}

		if (mTextInputDelegate != null)
		{
			Shell.InputManager.Keyboard.OnTextInput.Unsubscribe(mTextInputDelegate);
			//delete mTextInputDelegate;
			//mTextInputDelegate = null;
		}

		// Dispose and delete UI renderer (must call Dispose to release GPU resources)
		if (mUIRenderer != null)
		{
			mUIRenderer.Dispose();
			delete mUIRenderer;
			mUIRenderer = null;
		}

		// Delete UI services (registered with UIContext but we own them)
		if (mFontService != null) { delete mFontService; mFontService = null; }
		if (mTheme != null) { delete mTheme; mTheme = null; }
		if (mTooltipService != null) { delete mTooltipService; mTooltipService = null; }

		if (mAtlasTextureView != null) { delete mAtlasTextureView; mAtlasTextureView = null; }
		if (mAtlasTexture != null) { delete mAtlasTexture; mAtlasTexture = null; }
		//if (mFontAtlas != null) { delete mFontAtlas; mFontAtlas = null; }
		//if (mFont != null) { delete mFont; mFont = null; }
	}
}

class Program
{
	public static int Main(String[] args)
	{
		let app = scope EngineAudioSample();
		app.Run();
		return 0;
	}
}
