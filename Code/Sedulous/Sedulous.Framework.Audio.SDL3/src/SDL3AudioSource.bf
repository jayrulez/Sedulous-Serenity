using System;
using SDL3_mixer;
using Sedulous.Mathematics;
using Sedulous.Framework.Audio;

namespace Sedulous.Framework.Audio.SDL3;

/// SDL3_mixer implementation of IAudioSource using MIX_Track.
class SDL3AudioSource : IAudioSource
{
	private MIX_Track* mTrack;
	private SDL3AudioClip mCurrentClip;
	private AudioSourceState mState = .Stopped;
	private float mVolume = 1.0f;
	private float mPitch = 1.0f;
	private bool mLoop;
	private Vector3 mPosition = .Zero;
	private float mMinDistance = 1.0f;
	private float mMaxDistance = 100.0f;
	private bool m3DEnabled;

	/// Creates an audio source wrapping the specified MIX_Track.
	public this(MIX_Track* track)
	{
		mTrack = track;
	}

	public ~this()
	{
		if (mTrack != null)
		{
			SDL3_mixer.MIX_DestroyTrack(mTrack);
			mTrack = null;
		}
	}

	public AudioSourceState State => mState;

	public float Volume
	{
		get => mVolume;
		set
		{
			mVolume = Math.Clamp(value, 0.0f, 1.0f);
			UpdateTrackGain();
		}
	}

	public float Pitch
	{
		get => mPitch;
		set => mPitch = Math.Max(value, 0.01f);
		// Note: SDL_mixer doesn't directly support pitch adjustment
		// This would require resampling or stream manipulation
	}

	public bool Loop
	{
		get => mLoop;
		set => mLoop = value;
	}

	public Vector3 Position
	{
		get => mPosition;
		set
		{
			mPosition = value;
			m3DEnabled = true;
		}
	}

	public float MinDistance
	{
		get => mMinDistance;
		set => mMinDistance = Math.Max(value, 0.01f);
	}

	public float MaxDistance
	{
		get => mMaxDistance;
		set => mMaxDistance = Math.Max(value, mMinDistance);
	}

	public void Play(IAudioClip clip)
	{
		if (mTrack == null)
			return;

		mCurrentClip = clip as SDL3AudioClip;
		if (mCurrentClip == null || !mCurrentClip.IsLoaded)
			return;

		// Set the audio on the track
		SDL3_mixer.MIX_SetTrackAudio(mTrack, mCurrentClip.Audio);

		// Play the track
		SDL3_mixer.MIX_PlayTrack(mTrack, 0);  // 0 = default properties
		mState = .Playing;
	}

	public void Pause()
	{
		if (mTrack != null && mState == .Playing)
		{
			SDL3_mixer.MIX_PauseTrack(mTrack);
			mState = .Paused;
		}
	}

	public void Resume()
	{
		if (mTrack != null && mState == .Paused)
		{
			SDL3_mixer.MIX_ResumeTrack(mTrack);
			mState = .Playing;
		}
	}

	public void Stop()
	{
		if (mTrack != null)
		{
			SDL3_mixer.MIX_StopTrack(mTrack, 0);  // 0 = immediate stop
			mState = .Stopped;
		}
	}

	/// Updates the track's 3D position relative to the listener.
	public void Update3DPosition(SDL3AudioListener listener)
	{
		if (mTrack == null || !m3DEnabled)
			return;

		// Transform world position to listener-local coordinates
		let localPos = listener.WorldToLocal(mPosition);

		// Calculate distance for attenuation
		let distance = localPos.Length();

		// Apply distance-based gain (linear attenuation between min and max distance)
		float distanceGain = 1.0f;
		if (distance > mMinDistance)
		{
			if (distance >= mMaxDistance)
				distanceGain = 0.0f;
			else
				distanceGain = 1.0f - (distance - mMinDistance) / (mMaxDistance - mMinDistance);
		}

		// Combine volume and distance gain
		SDL3_mixer.MIX_SetTrackGain(mTrack, mVolume * distanceGain);

		// Set 3D position for spatialization
		SDL3_mixer.MIX_Point3D point = .() {
			x = localPos.X,
			y = localPos.Y,
			z = localPos.Z
		};
		SDL3_mixer.MIX_SetTrack3DPosition(mTrack, &point);
	}

	/// Updates the state by checking if the track is still playing.
	public void UpdateState()
	{
		if (mTrack != null && mState == .Playing)
		{
			if (!SDL3_mixer.MIX_TrackPlaying(mTrack))
				mState = .Stopped;
		}
	}

	private void UpdateTrackGain()
	{
		if (mTrack != null && !m3DEnabled)
		{
			SDL3_mixer.MIX_SetTrackGain(mTrack, mVolume);
		}
	}
}
