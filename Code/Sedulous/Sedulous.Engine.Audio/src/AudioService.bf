namespace Sedulous.Engine.Audio;

using System;
using System.Collections;
using Sedulous.Audio;
using Sedulous.Engine.Core;
using Sedulous.Mathematics;

/// Context service that manages audio playback across all scenes.
/// Register this service with the Context to enable entity-based audio.
/// Automatically creates AudioSceneComponent for each scene.
///
/// Owns:
/// - IAudioSystem (audio backend)
/// - Clip cache (loaded audio clips by name)
/// - Music streams (background music)
///
/// Note: Per-scene audio source management is handled by AudioSceneComponent.
class AudioService : ContextService, IDisposable
{
	private Context mContext;
	private IAudioSystem mAudioSystem;
	private bool mOwnsAudioSystem = false;
	private bool mInitialized = false;

	// Clip cache (name → clip)
	private Dictionary<String, AudioClip> mClipCache = new .() ~ DeleteDictionaryAndKeysAndValues!(_);

	// Active music streams
	private List<IAudioStream> mMusicStreams = new .() ~ DeleteContainerAndItems!(_);

	// Track created scene components
	private List<AudioSceneComponent> mSceneComponents = new .() ~ delete _;

	// Volume levels
	private float mMasterVolume = 1.0f;
	private float mMusicVolume = 1.0f;
	private float mSFXVolume = 1.0f;

	// ==================== Properties ====================

	/// Gets the underlying audio system.
	public IAudioSystem AudioSystem => mAudioSystem;

	/// Gets the context this service is registered with.
	public Context Context => mContext;

	/// Gets whether the service has been initialized.
	public bool IsInitialized => mInitialized;

	/// Gets or sets the master volume (0.0 to 1.0).
	/// Affects all audio (SFX + music).
	public float MasterVolume
	{
		get => mMasterVolume;
		set
		{
			mMasterVolume = Math.Clamp(value, 0.0f, 1.0f);
			UpdateMasterVolume();
		}
	}

	/// Gets or sets the music volume (0.0 to 1.0).
	/// Multiplied with master volume for music streams.
	public float MusicVolume
	{
		get => mMusicVolume;
		set
		{
			mMusicVolume = Math.Clamp(value, 0.0f, 1.0f);
			UpdateMusicVolumes();
		}
	}

	/// Gets or sets the SFX volume (0.0 to 1.0).
	/// Multiplied with master volume for one-shots and source components.
	public float SFXVolume
	{
		get => mSFXVolume;
		set => mSFXVolume = Math.Clamp(value, 0.0f, 1.0f);
	}

	/// Gets the effective SFX volume (Master * SFX).
	public float EffectiveSFXVolume => mMasterVolume * mSFXVolume;

	/// Gets the effective music volume (Master * Music).
	public float EffectiveMusicVolume => mMasterVolume * mMusicVolume;

	// ==================== Initialization ====================

	/// Initializes the audio service with an audio system.
	/// The service takes ownership of the audio system and will dispose it on shutdown.
	public Result<void> Initialize(IAudioSystem audioSystem, bool takeOwnership = true)
	{
		if (audioSystem == null)
			return .Err;

		if (!audioSystem.IsInitialized)
			return .Err;

		mAudioSystem = audioSystem;
		mOwnsAudioSystem = takeOwnership;
		mInitialized = true;

		// Apply master volume
		UpdateMasterVolume();

		return .Ok;
	}

	// ==================== Clip Management ====================

	/// Loads an audio clip from raw data and caches it by name.
	/// Returns the cached clip if already loaded.
	public Result<AudioClip> LoadClip(StringView name, Span<uint8> data)
	{
		// Check cache first
		String nameKey = scope String(name);
		if (mClipCache.TryGetValue(nameKey, let existing))
			return .Ok(existing);

		if (mAudioSystem == null)
			return .Err;

		// Load clip
		switch (mAudioSystem.LoadClip(data))
		{
		case .Ok(let clip):
			let key = new String(name);
			mClipCache[key] = clip;
			return .Ok(clip);
		case .Err:
			return .Err;
		}
	}

	/// Gets a previously loaded clip by name.
	/// Returns null if not found.
	public AudioClip GetClip(StringView name)
	{
		String nameKey = scope String(name);
		if (mClipCache.TryGetValue(nameKey, let clip))
			return clip;
		return null;
	}

	/// Unloads a clip from the cache.
	public void UnloadClip(StringView name)
	{
		String nameKey = scope String(name);
		if (mClipCache.TryGetValue(nameKey, let clip))
		{
			delete clip;
			mClipCache.Remove(nameKey);
		}
	}

	/// Unloads all clips from the cache.
	public void UnloadAllClips()
	{
		for (let (key, clip) in mClipCache)
		{
			delete key;
			delete clip;
		}
		mClipCache.Clear();
	}

	// ==================== One-Shot Playback ====================

	/// Plays an audio clip with fire-and-forget semantics (2D, no positioning).
	public void PlayOneShot(AudioClip clip, float volume = 1.0f)
	{
		if (mAudioSystem == null || clip == null)
			return;

		mAudioSystem.PlayOneShot(clip, volume * EffectiveSFXVolume);
	}

	/// Plays a cached audio clip by name with fire-and-forget semantics.
	public void PlayOneShot(StringView clipName, float volume = 1.0f)
	{
		let clip = GetClip(clipName);
		if (clip != null)
			PlayOneShot(clip, volume);
	}

	/// Plays an audio clip at a 3D position with fire-and-forget semantics.
	public void PlayOneShot3D(AudioClip clip, Vector3 position, float volume = 1.0f)
	{
		if (mAudioSystem == null || clip == null)
			return;

		mAudioSystem.PlayOneShot3D(clip, position, volume * EffectiveSFXVolume);
	}

	/// Plays a cached audio clip at a 3D position with fire-and-forget semantics.
	public void PlayOneShot3D(StringView clipName, Vector3 position, float volume = 1.0f)
	{
		let clip = GetClip(clipName);
		if (clip != null)
			PlayOneShot3D(clip, position, volume);
	}

	// ==================== Music Streaming ====================

	/// Opens and plays a music stream from a file path.
	/// Returns the stream for volume/loop control.
	public Result<IAudioStream> PlayMusic(StringView filePath, bool loop = true, float volume = 1.0f)
	{
		if (mAudioSystem == null)
			return .Err;

		switch (mAudioSystem.OpenStream(filePath))
		{
		case .Ok(let stream):
			stream.Loop = loop;
			stream.Volume = volume * EffectiveMusicVolume;
			stream.Play();
			mMusicStreams.Add(stream);
			return .Ok(stream);
		case .Err:
			return .Err;
		}
	}

	/// Stops and removes a music stream.
	public void StopMusic(IAudioStream stream)
	{
		if (stream == null)
			return;

		stream.Stop();
		mMusicStreams.Remove(stream);
		delete stream;
	}

	/// Stops all music streams.
	public void StopAllMusic()
	{
		for (let stream in mMusicStreams)
		{
			stream.Stop();
			delete stream;
		}
		mMusicStreams.Clear();
	}

	/// Pauses all music streams.
	public void PauseAllMusic()
	{
		for (let stream in mMusicStreams)
			stream.Pause();
	}

	/// Resumes all music streams.
	public void ResumeAllMusic()
	{
		for (let stream in mMusicStreams)
			stream.Resume();
	}

	// ==================== Global Controls ====================

	/// Pauses all audio (SFX + music).
	public void PauseAll()
	{
		mAudioSystem?.PauseAll();
		PauseAllMusic();
	}

	/// Resumes all audio (SFX + music).
	public void ResumeAll()
	{
		mAudioSystem?.ResumeAll();
		ResumeAllMusic();
	}

	// ==================== ContextService Implementation ====================

	/// Called when the service is registered with the context.
	public override void OnRegister(Context context)
	{
		mContext = context;
	}

	/// Called when the service is unregistered from the context.
	public override void OnUnregister()
	{
		mContext = null;
	}

	/// Called during context startup.
	public override void Startup()
	{
		// Nothing to do - Initialize() must be called separately
	}

	/// Called during context shutdown.
	public override void Shutdown()
	{
		// Stop all audio
		StopAllMusic();
		UnloadAllClips();

		// Clean up audio system
		if (mOwnsAudioSystem && mAudioSystem != null)
		{
			mAudioSystem.Dispose();
			delete mAudioSystem;
		}
		mAudioSystem = null;
		mInitialized = false;
	}

	/// Called each frame during context update.
	public override void Update(float deltaTime)
	{
		if (mAudioSystem == null)
			return;

		// Update audio system (processes 3D spatialization, cleans up finished one-shots)
		mAudioSystem.Update();

		// Clean up finished music streams
		CleanupFinishedStreams();
	}

	/// Called when a scene is created.
	/// Automatically adds AudioSceneComponent to the scene.
	public override void OnSceneCreated(Scene scene)
	{
		if (!mInitialized || mAudioSystem == null)
		{
			mContext?.Logger?.LogWarning("AudioService: Not initialized, skipping AudioSceneComponent for '{}'", scene.Name);
			return;
		}

		let component = new AudioSceneComponent(this);
		scene.AddSceneComponent(component);
		mSceneComponents.Add(component);

		mContext?.Logger?.LogDebug("AudioService: Added AudioSceneComponent to scene '{}'", scene.Name);
	}

	/// Called when a scene is being destroyed.
	public override void OnSceneDestroyed(Scene scene)
	{
		// Find and remove component belonging to this scene
		for (int i = mSceneComponents.Count - 1; i >= 0; i--)
		{
			let component = mSceneComponents[i];
			if (component.Scene == scene)
			{
				mSceneComponents.RemoveAt(i);
				// Note: Scene will delete the component via RemoveSceneComponent
				break;
			}
		}
	}

	/// Gets all AudioSceneComponents created by this service.
	public Span<AudioSceneComponent> SceneComponents => mSceneComponents;

	// ==================== IDisposable Implementation ====================

	public void Dispose()
	{
		Shutdown();
	}

	// ==================== Private Methods ====================

	private void UpdateMasterVolume()
	{
		if (mAudioSystem != null)
			mAudioSystem.MasterVolume = mMasterVolume;

		UpdateMusicVolumes();
	}

	private void UpdateMusicVolumes()
	{
		let effectiveVolume = EffectiveMusicVolume;
		for (let stream in mMusicStreams)
			stream.Volume = effectiveVolume;
	}

	private void CleanupFinishedStreams()
	{
		for (int i = mMusicStreams.Count - 1; i >= 0; i--)
		{
			let stream = mMusicStreams[i];
			// Remove streams that have finished and aren't looping
			if (stream.State == .Stopped && !stream.Loop)
			{
				delete stream;
				mMusicStreams.RemoveAt(i);
			}
		}
	}
}
