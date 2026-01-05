# AudioSample

Demonstrates the Sedulous audio system using SDL3_mixer.

## Features

- Audio system initialization
- WAV file loading from disk
- Procedural sine wave generation (fallback when no WAV file)
- Audio clip playback via AudioSource
- PlayOneShot for fire-and-forget sounds

## Usage

```bash
# Run with a WAV file
AudioSample.exe path/to/sound.wav

# Run without arguments (generates a 440Hz sine wave)
AudioSample.exe
```

## Technical Details

- Uses `SDL3AudioSystem` implementation
- Demonstrates `IAudioClip` and `IAudioSource` interfaces
- Shows audio clip properties: duration, sample rate, channels
- Includes WAV file generation code for testing without external files

## Dependencies

- Sedulous.Framework.Audio
- Sedulous.Framework.Audio.SDL3
- Sedulous.Mathematics
