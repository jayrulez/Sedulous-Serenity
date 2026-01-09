using System;
using SDL3;
using Sedulous.Audio;

namespace Sedulous.Audio.SDL3;

/// SDL3 implementation of IAudioClip storing decoded PCM audio data.
class SDL3AudioClip : IAudioClip
{
	private uint8* mAudioData;
	private uint32 mAudioLen;
	private SDL_AudioSpec mSpec;

	/// Gets the raw PCM audio data.
	public uint8* AudioData => mAudioData;

	/// Gets the length of the audio data in bytes.
	public uint32 AudioLen => mAudioLen;

	/// Gets the audio format specification.
	public SDL_AudioSpec Spec => mSpec;

	public this(uint8* audioData, uint32 audioLen, SDL_AudioSpec spec)
	{
		mAudioData = audioData;
		mAudioLen = audioLen;
		mSpec = spec;
	}

	public ~this()
	{
		if (mAudioData != null)
		{
			SDL3.SDL_free(mAudioData);
			mAudioData = null;
		}
	}

	public float Duration
	{
		get
		{
			if (mAudioData == null || mSpec.freq == 0)
				return 0;
			let frameSize = SDL3.SDL_AUDIO_FRAMESIZE(mSpec);
			if (frameSize == 0)
				return 0;
			let totalFrames = mAudioLen / frameSize;
			return (float)totalFrames / (float)mSpec.freq;
		}
	}

	public int32 SampleRate => mSpec.freq;

	public int32 Channels => mSpec.channels;

	public bool IsLoaded => mAudioData != null;
}
