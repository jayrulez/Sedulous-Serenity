using System;
using SDL3_mixer;
using Sedulous.Framework.Audio;

namespace Sedulous.Framework.Audio.SDL3;

/// SDL3_mixer implementation of IAudioClip wrapping MIX_Audio.
class SDL3AudioClip : IAudioClip
{
	private MIX_Audio* mAudio;
	private int32 mSampleRate;
	private int32 mChannels;

	/// Gets the native MIX_Audio pointer.
	public MIX_Audio* Audio => mAudio;

	public this(MIX_Audio* audio)
	{
		mAudio = audio;

		// Query audio format
		SDL3.SDL_AudioSpec spec = default;
		if (SDL3_mixer.MIX_GetAudioFormat(mAudio, &spec))
		{
			mSampleRate = spec.freq;
			mChannels = spec.channels;
		}
	}

	public ~this()
	{
		if (mAudio != null)
		{
			SDL3_mixer.MIX_DestroyAudio(mAudio);
			mAudio = null;
		}
	}

	public float Duration
	{
		get
		{
			if (mAudio == null || mSampleRate == 0)
				return 0;
			let frames = SDL3_mixer.MIX_GetAudioDuration(mAudio);
			return (float)frames / (float)mSampleRate;
		}
	}

	public int32 SampleRate => mSampleRate;

	public int32 Channels => mChannels;

	public bool IsLoaded => mAudio != null;
}
