using System;
using Sedulous.Mathematics;

namespace Sedulous.Framework.Audio;

/// Main audio system interface providing clip loading, source management, and 3D audio.
interface IAudioSystem : IDisposable
{
	/// Gets the 3D audio listener.
	IAudioListener Listener { get; }

	/// Gets or sets the master volume affecting all audio (0.0 to 1.0).
	float MasterVolume { get; set; }

	/// Creates a new audio source for controlled playback.
	IAudioSource CreateSource();

	/// Destroys an audio source, stopping any playing audio and freeing resources.
	void DestroySource(IAudioSource source);

	/// Plays an audio clip with fire-and-forget semantics (no source management needed).
	void PlayOneShot(IAudioClip clip, float volume = 1.0f);

	/// Plays an audio clip at a 3D position with fire-and-forget semantics.
	void PlayOneShot3D(IAudioClip clip, Vector3 position, float volume = 1.0f);

	/// Loads an audio clip from raw audio file data.
	/// The data format is auto-detected (WAV, OGG, MP3, FLAC, etc.).
	Result<IAudioClip> LoadClip(Span<uint8> data);

	/// Updates the audio system, processing 3D spatialization.
	/// Should be called once per frame.
	void Update();
}
