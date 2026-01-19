namespace Sedulous.Framework.Audio;

using System;
using System.Collections;
using Sedulous.Audio;
using Sedulous.Framework.Core;
using Sedulous.Framework.Scenes;
using Sedulous.Mathematics;

/// Audio subsystem that manages audio playback and integrates with Sedulous.Audio.
/// Backend (e.g., SDL3AudioSystem) is injected via constructor.
/// Implements ISceneAware to automatically create AudioSceneModule for each scene.
public class AudioSubsystem : Subsystem, ISceneAware
{
	/// Audio updates after game logic, before rendering.
	public override int32 UpdateOrder => 200;

	private IAudioSystem mAudioSystem;
	private bool mOwnsAudioSystem;

	// Clip cache
	private Dictionary<String, AudioClip> mClipCache = new .() ~ DeleteDictionaryAndKeysAndValues!(_);

	// Active music streams
	private List<IAudioStream> mMusicStreams = new .() ~ DeleteContainerAndItems!(_);

	// Volume controls
	private float mMasterVolume = 1.0f;
	private float mMusicVolume = 1.0f;
	private float mSFXVolume = 1.0f;

	// ==================== Construction ====================

	/// Creates an AudioSubsystem with the given audio backend.
	/// @param audioSystem The audio backend (e.g., SDL3AudioSystem).
	/// @param takeOwnership If true, the subsystem will delete the audio system on shutdown.
	public this(IAudioSystem audioSystem, bool takeOwnership = true)
	{
		mAudioSystem = audioSystem;
		mOwnsAudioSystem = takeOwnership;
	}

	// ==================== Properties ====================

	/// Gets the underlying audio system.
	public IAudioSystem AudioSystem => mAudioSystem;

	/// Gets or sets the master volume (0.0 to 1.0).
	public float MasterVolume
	{
		get => mMasterVolume;
		set
		{
			mMasterVolume = Math.Clamp(value, 0.0f, 1.0f);
			if (mAudioSystem != null)
				mAudioSystem.MasterVolume = mMasterVolume;
			UpdateMusicVolumes();
		}
	}

	/// Gets or sets the music volume (0.0 to 1.0).
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
	public float SFXVolume
	{
		get => mSFXVolume;
		set => mSFXVolume = Math.Clamp(value, 0.0f, 1.0f);
	}

	/// Gets the effective SFX volume (Master * SFX).
	public float EffectiveSFXVolume => mMasterVolume * mSFXVolume;

	/// Gets the effective music volume (Master * Music).
	public float EffectiveMusicVolume => mMasterVolume * mMusicVolume;

	// ==================== Clip Management ====================

	/// Loads an audio clip from raw data and caches it by name.
	public Result<AudioClip> LoadClip(StringView name, Span<uint8> data)
	{
		if (mClipCache.TryGetValue(scope String(name), let existing))
			return .Ok(existing);

		if (mAudioSystem == null)
			return .Err;

		switch (mAudioSystem.LoadClip(data))
		{
		case .Ok(let clip):
			mClipCache[new String(name)] = clip;
			return .Ok(clip);
		case .Err:
			return .Err;
		}
	}

	/// Gets a previously loaded clip by name.
	public AudioClip GetClip(StringView name)
	{
		if (mClipCache.TryGetValue(scope String(name), let clip))
			return clip;
		return null;
	}

	/// Unloads a clip from the cache.
	public void UnloadClip(StringView name)
	{
		let key = scope String(name);
		if (mClipCache.TryGetValue(key, let clip))
		{
			for (let kv in mClipCache)
			{
				if (kv.key == key)
				{
					let actualKey = kv.key;
					mClipCache.Remove(actualKey);
					delete actualKey;
					delete clip;
					break;
				}
			}
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

	/// Plays an audio clip with fire-and-forget semantics (2D).
	public void PlayOneShot(AudioClip clip, float volume = 1.0f)
	{
		if (mAudioSystem == null || clip == null)
			return;
		mAudioSystem.PlayOneShot(clip, volume * EffectiveSFXVolume);
	}

	/// Plays a cached audio clip by name.
	public void PlayOneShot(StringView clipName, float volume = 1.0f)
	{
		if (let clip = GetClip(clipName))
			PlayOneShot(clip, volume);
	}

	/// Plays an audio clip at a 3D position.
	public void PlayOneShot3D(AudioClip clip, Vector3 position, float volume = 1.0f)
	{
		if (mAudioSystem == null || clip == null)
			return;
		mAudioSystem.PlayOneShot3D(clip, position, volume * EffectiveSFXVolume);
	}

	/// Plays a cached audio clip at a 3D position.
	public void PlayOneShot3D(StringView clipName, Vector3 position, float volume = 1.0f)
	{
		if (let clip = GetClip(clipName))
			PlayOneShot3D(clip, position, volume);
	}

	// ==================== Music Streaming ====================

	/// Opens and plays a music stream from a file path.
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

	// ==================== Subsystem Lifecycle ====================

	protected override void OnInit()
	{
		if (mAudioSystem != null)
			mAudioSystem.MasterVolume = mMasterVolume;
	}

	protected override void OnShutdown()
	{
		StopAllMusic();
		UnloadAllClips();

		if (mOwnsAudioSystem && mAudioSystem != null)
		{
			mAudioSystem.Dispose();
			delete mAudioSystem;
		}
		mAudioSystem = null;
	}

	public override void Update(float deltaTime)
	{
		if (mAudioSystem == null)
			return;

		mAudioSystem.Update();
		CleanupFinishedStreams();
	}

	// ==================== ISceneAware ====================

	public void OnSceneCreated(Scene scene)
	{
		if (mAudioSystem == null)
			return;

		let module = new AudioSceneModule(this);
		scene.AddModule(module);
	}

	public void OnSceneDestroyed(Scene scene)
	{
		// Scene will clean up its modules
	}

	// ==================== Private ====================

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
			if (stream.State == .Stopped && !stream.Loop)
			{
				delete stream;
				mMusicStreams.RemoveAt(i);
			}
		}
	}
}
