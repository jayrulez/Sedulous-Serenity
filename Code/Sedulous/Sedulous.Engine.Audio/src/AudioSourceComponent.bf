namespace Sedulous.Engine.Audio;

using System;
using Sedulous.Audio;
using Sedulous.Engine.Core;
using Sedulous.Serialization;

/// Entity component for 3D positional audio playback.
/// Attach to entities to play sounds at their world position.
/// The audio source position is automatically synced with the entity transform.
class AudioSourceComponent : IEntityComponent
{
	private Entity mEntity;
	private AudioSceneComponent mAudioScene;
	private IAudioSource mSource;

	// Audio properties (synced to IAudioSource when attached)
	private float mVolume = 1.0f;
	private float mPitch = 1.0f;
	private bool mLoop = false;
	private float mMinDistance = 1.0f;
	private float mMaxDistance = 100.0f;

	// Default clip to play
	private AudioClip mClip;

	// Play on attach flag
	private bool mPlayOnAttach = false;

	// ==================== Properties ====================

	/// Gets the entity this component is attached to.
	public Entity Entity => mEntity;

	/// Gets the underlying audio source.
	public IAudioSource Source => mSource;

	/// Gets the current playback state.
	public AudioSourceState State => mSource?.State ?? .Stopped;

	/// Gets or sets the volume (0.0 to 1.0).
	/// This is multiplied with the AudioService's SFX volume.
	public float Volume
	{
		get => mVolume;
		set
		{
			mVolume = Math.Clamp(value, 0.0f, 1.0f);
			if (mSource != null)
				mSource.Volume = mVolume;
		}
	}

	/// Gets or sets the pitch multiplier (1.0 = normal speed).
	public float Pitch
	{
		get => mPitch;
		set
		{
			mPitch = Math.Max(0.01f, value);
			if (mSource != null)
				mSource.Pitch = mPitch;
		}
	}

	/// Gets or sets whether the audio should loop.
	public bool Loop
	{
		get => mLoop;
		set
		{
			mLoop = value;
			if (mSource != null)
				mSource.Loop = mLoop;
		}
	}

	/// Gets or sets the minimum distance where attenuation begins.
	/// Below this distance, sound plays at full volume.
	public float MinDistance
	{
		get => mMinDistance;
		set
		{
			mMinDistance = Math.Max(0.0f, value);
			if (mSource != null)
				mSource.MinDistance = mMinDistance;
		}
	}

	/// Gets or sets the maximum distance for sound attenuation.
	/// Beyond this distance, the sound is inaudible.
	public float MaxDistance
	{
		get => mMaxDistance;
		set
		{
			mMaxDistance = Math.Max(0.0f, value);
			if (mSource != null)
				mSource.MaxDistance = mMaxDistance;
		}
	}

	/// Gets or sets the default clip to play.
	public AudioClip Clip
	{
		get => mClip;
		set => mClip = value;
	}

	/// Gets or sets whether to automatically play when attached.
	public bool PlayOnAttach
	{
		get => mPlayOnAttach;
		set => mPlayOnAttach = value;
	}

	// ==================== IEntityComponent Implementation ====================

	/// Called when the component is attached to an entity.
	public void OnAttach(Entity entity)
	{
		mEntity = entity;

		// Get the AudioSceneComponent from the scene
		mAudioScene = entity.Scene?.GetSceneComponent<AudioSceneComponent>();
		if (mAudioScene == null)
			return;

		// Create audio source
		mSource = mAudioScene.CreateSource(entity);
		if (mSource == null)
			return;

		// Apply settings
		mSource.Volume = mVolume;
		mSource.Pitch = mPitch;
		mSource.Loop = mLoop;
		mSource.MinDistance = mMinDistance;
		mSource.MaxDistance = mMaxDistance;

		// Auto-play if configured
		if (mPlayOnAttach && mClip != null)
			Play();
	}

	/// Called when the component is detached from an entity.
	public void OnDetach()
	{
		if (mSource != null)
		{
			mSource.Stop();
			mAudioScene?.DestroySource(mEntity);
			mSource = null;
		}

		mAudioScene = null;
		mEntity = null;
	}

	/// Called each frame to update the component.
	/// Position sync is handled by AudioSceneComponent, not here.
	public void OnUpdate(float deltaTime)
	{
		// Position syncing is done by AudioSceneComponent.SyncSources()
	}

	// ==================== Playback Controls ====================

	/// Plays the default clip.
	public void Play()
	{
		if (mClip != null)
			Play(mClip);
	}

	/// Plays a specific audio clip.
	public void Play(AudioClip clip)
	{
		if (mSource == null || clip == null)
			return;

		mSource.Play(clip);
	}

	/// Plays a clip by name from the AudioService cache.
	public void Play(StringView clipName)
	{
		if (mAudioScene?.AudioService == null)
			return;

		let clip = mAudioScene.AudioService.GetClip(clipName);
		if (clip != null)
			Play(clip);
	}

	/// Pauses playback.
	public void Pause()
	{
		mSource?.Pause();
	}

	/// Resumes playback from the paused position.
	public void Resume()
	{
		mSource?.Resume();
	}

	/// Stops playback and resets to the beginning.
	public void Stop()
	{
		mSource?.Stop();
	}

	// ==================== ISerializable Implementation ====================

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer serializer)
	{
		var version = SerializationVersion;
		var result = serializer.Version(ref version);
		if (result != .Ok)
			return result;

		// Serialize audio properties
		result = serializer.Float("volume", ref mVolume);
		if (result != .Ok) return result;

		result = serializer.Float("pitch", ref mPitch);
		if (result != .Ok) return result;

		result = serializer.Bool("loop", ref mLoop);
		if (result != .Ok) return result;

		result = serializer.Float("minDistance", ref mMinDistance);
		if (result != .Ok) return result;

		result = serializer.Float("maxDistance", ref mMaxDistance);
		if (result != .Ok) return result;

		result = serializer.Bool("playOnAttach", ref mPlayOnAttach);
		if (result != .Ok) return result;

		// Note: We don't serialize the clip - it must be set up by the application
		// after deserialization, typically using a clip name reference

		return .Ok;
	}
}
