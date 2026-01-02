using System;
using System.Collections;
using SDL3;
using SDL3_mixer;
using Sedulous.Mathematics;
using Sedulous.Framework.Audio;

namespace Sedulous.Framework.Audio.SDL3;

/// SDL3_mixer implementation of IAudioSystem.
class SDL3AudioSystem : IAudioSystem
{
	private MIX_Mixer* mMixer;
	private SDL3AudioListener mListener = new .() ~ delete _;
	private List<SDL3AudioSource> mSources = new .() ~ DeleteContainerAndItems!(_);
	private float mMasterVolume = 1.0f;
	private bool mOwnedAudioInit;
	private bool mMixerInitialized;

	/// Returns true if the audio system initialized successfully.
	public bool IsInitialized => mMixer != null;

	/// Creates an SDL3AudioSystem with default audio device and format.
	public this()
	{
		// Initialize SDL audio subsystem if not already initialized
		if (SDL3.SDL_WasInit(.SDL_INIT_AUDIO) == 0)
		{
			if (!SDL3.SDL_InitSubSystem(.SDL_INIT_AUDIO))
			{
				LogError("Failed to initialize SDL audio subsystem");
				return;
			}
			mOwnedAudioInit = true;
		}

		// Initialize SDL_mixer library
		if (!SDL3_mixer.MIX_Init())
		{
			LogError("Failed to initialize SDL_mixer");
			return;
		}
		mMixerInitialized = true;

		// Create mixer attached to default audio device
		mMixer = SDL3_mixer.MIX_CreateMixerDevice(SDL3.SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, null);
		if (mMixer == null)
		{
			LogError("Failed to create audio mixer device");
		}
	}

	public ~this()
	{
		Dispose();
	}

	public void Dispose()
	{
		// Clean up sources first
		for (let source in mSources)
			delete source;
		mSources.Clear();

		// Destroy mixer
		if (mMixer != null)
		{
			SDL3_mixer.MIX_DestroyMixer(mMixer);
			mMixer = null;
		}

		// Quit SDL_mixer library (reference counted, matches MIX_Init call)
		if (mMixerInitialized)
		{
			SDL3_mixer.MIX_Quit();
			mMixerInitialized = false;
		}

		// Quit audio subsystem if we initialized it
		if (mOwnedAudioInit)
		{
			SDL3.SDL_QuitSubSystem(.SDL_INIT_AUDIO);
			mOwnedAudioInit = false;
		}
	}

	public IAudioListener Listener => mListener;

	public float MasterVolume
	{
		get => mMasterVolume;
		set => mMasterVolume = Math.Clamp(value, 0.0f, 1.0f);
		// Note: SDL_mixer doesn't have a master volume per mixer.
		// We would apply this when setting individual track gains.
	}

	public IAudioSource CreateSource()
	{
		if (mMixer == null)
			return null;

		let track = SDL3_mixer.MIX_CreateTrack(mMixer);
		if (track == null)
			return null;

		let source = new SDL3AudioSource(track);
		mSources.Add(source);
		return source;
	}

	public void DestroySource(IAudioSource source)
	{
		if (let sdlSource = source as SDL3AudioSource)
		{
			mSources.Remove(sdlSource);
			delete sdlSource;
		}
	}

	public void PlayOneShot(IAudioClip clip, float volume)
	{
		if (mMixer == null)
			return;

		if (let sdlClip = clip as SDL3AudioClip)
		{
			if (sdlClip.IsLoaded)
				SDL3_mixer.MIX_PlayAudio(mMixer, sdlClip.Audio);
		}
	}

	public void PlayOneShot3D(IAudioClip clip, Vector3 position, float volume)
	{
		// For 3D fire-and-forget, we need a temporary source
		// This is a simplification - a more robust implementation would use
		// a pool of temporary sources
		let source = CreateSource();
		if (source != null)
		{
			source.Volume = volume;
			source.Position = position;
			source.Play(clip);
			// Note: We can't easily clean this up without a callback mechanism.
			// For a production implementation, we'd track these and clean up on Update.
		}
	}

	public Result<IAudioClip> LoadClip(Span<uint8> data)
	{
		if (mMixer == null)
			return .Err;

		// Create SDL_IOStream from memory
		let io = SDL3.SDL_IOFromConstMem(data.Ptr, (.)data.Length);
		if (io == null)
			return .Err;

		// Load audio (predecode=true for sound effects, closeio=true to close IOStream)
		let audio = SDL3_mixer.MIX_LoadAudio_IO(mMixer, io, true, true);
		if (audio == null)
			return .Err;

		return .Ok(new SDL3AudioClip(audio));
	}

	public void Update()
	{
		// Update all sources
		for (let source in mSources)
		{
			source.Update3DPosition(mListener);
			source.UpdateState();
		}
	}

	private void LogError(StringView message)
	{
		let sdlError = SDL3.SDL_GetError();
		if (sdlError != null && sdlError[0] != 0)
			Console.Error.WriteLine(scope $"[SDL3AudioSystem] {message}: {StringView(sdlError)}");
		else
			Console.Error.WriteLine(scope $"[SDL3AudioSystem] {message}");
	}
}
