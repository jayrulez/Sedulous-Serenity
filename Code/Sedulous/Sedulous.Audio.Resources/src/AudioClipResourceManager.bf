using System;
using System.IO;
using System.Collections;
using Sedulous.Audio;
using Sedulous.Resources;

namespace Sedulous.Audio.Resources;

/// Resource manager for loading audio clips through the ResourceSystem.
/// Requires an IAudioSystem to create backend-specific audio clips.
class AudioClipResourceManager : ResourceManager<AudioClipResource>
{
	private IAudioSystem mAudioSystem;

	/// Creates an AudioClipResourceManager with the specified audio system for clip loading.
	public this(IAudioSystem audioSystem)
	{
		mAudioSystem = audioSystem;
	}

	protected override Result<AudioClipResource, ResourceLoadError> LoadFromMemory(MemoryStream memory)
	{
		// Read memory stream into a buffer
		let buffer = scope List<uint8>((int)memory.Length);
		buffer.Count = (int)memory.Length;
		memory.Position = 0;
		if (memory.TryRead(buffer) case .Err)
			return .Err(.ReadError);

		let data = Span<uint8>(buffer.Ptr, buffer.Count);
		switch (mAudioSystem.LoadClip(data))
		{
		case .Ok(let clip):
			let resource = new AudioClipResource();
			resource.Clip = clip;
			return .Ok(resource);
		case .Err:
			return .Err(.InvalidFormat);
		}
	}

	public override void Unload(AudioClipResource resource)
	{
		// Resource destructor handles clip cleanup
	}
}
