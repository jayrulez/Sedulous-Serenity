namespace Sedulous.Framework.Audio;

/// Interface for loaded audio data that can be played through an audio source.
interface IAudioClip
{
	/// Gets the duration of the audio clip in seconds.
	float Duration { get; }

	/// Gets the sample rate of the audio clip (e.g., 44100).
	int32 SampleRate { get; }

	/// Gets the number of channels (1 = mono, 2 = stereo).
	int32 Channels { get; }

	/// Gets whether the audio clip is fully loaded and ready to play.
	bool IsLoaded { get; }
}
