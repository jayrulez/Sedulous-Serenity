# Sedulous Audio Library

The Sedulous audio library provides cross-platform audio playback with 3D spatialization, supporting multiple audio formats through a modular decoder system.

## Architecture

The audio system is split into multiple projects:

- **Sedulous.Audio** - Core interfaces and types (backend-agnostic)
- **Sedulous.Audio.SDL3** - SDL3 implementation with 3D audio
- **Sedulous.Audio.Decoders** - Standalone audio file decoders (FLAC, OGG, MP3, WAV)

## Quick Start

```beef
using Sedulous.Audio;
using Sedulous.Audio.SDL3;
using Sedulous.Audio.Decoders;

// Create audio system
let audioSystem = new SDL3AudioSystem();
defer delete audioSystem;

if (!audioSystem.IsInitialized)
    return; // Audio not available

// Create decoder factory
let decoderFactory = new AudioDecoderFactory();
defer delete decoderFactory;
decoderFactory.RegisterDefaultDecoders();

// Load and decode audio file
if (decoderFactory.DecodeFile("sound.ogg") case .Ok(let clip))
{
    defer delete clip;

    // Play one-shot (fire-and-forget)
    audioSystem.PlayOneShot(clip, volume: 0.8f);

    // Or create a source for controlled playback
    let source = audioSystem.CreateSource();
    source.Volume = 0.7f;
    source.Loop = true;
    source.Play(clip);

    // Update each frame
    while (playing)
    {
        audioSystem.Update();
    }

    source.Stop();
    audioSystem.DestroySource(source);
}
```

## Core Types

### AudioClip

Represents decoded PCM audio data ready for playback.

```beef
class AudioClip : IDisposable
{
    uint8* Data { get; }           // Raw PCM data pointer
    int DataLength { get; }        // Data size in bytes
    int32 SampleRate { get; }      // Sample rate (e.g., 44100, 48000)
    int32 Channels { get; }        // Channel count (1=mono, 2=stereo)
    AudioFormat Format { get; }    // Sample format (Int16, Int32, Float32)
    float Duration { get; }        // Duration in seconds
    int FrameCount { get; }        // Total PCM frames
    int BytesPerFrame { get; }     // Bytes per frame
    bool IsLoaded { get; }         // True if data is valid
}
```

### AudioFormat

PCM sample formats:

| Format | Description | Bytes per Sample |
|--------|-------------|------------------|
| `Int16` | 16-bit signed integer | 2 |
| `Int32` | 32-bit signed integer | 4 |
| `Float32` | 32-bit floating point | 4 |

### IAudioSystem

Main audio system interface:

```beef
interface IAudioSystem : IDisposable
{
    bool IsInitialized { get; }
    IAudioListener Listener { get; }
    float MasterVolume { get; set; }

    IAudioSource CreateSource();
    void DestroySource(IAudioSource source);

    void PlayOneShot(AudioClip clip, float volume = 1.0f);
    void PlayOneShot3D(AudioClip clip, Vector3 position, float volume = 1.0f);

    Result<AudioClip> LoadClip(Span<uint8> data);  // WAV only
    Result<IAudioStream> OpenStream(StringView filePath);

    void PauseAll();
    void ResumeAll();
    void Update();
}
```

### IAudioSource

Controlled audio playback with 3D positioning:

```beef
interface IAudioSource
{
    AudioSourceState State { get; }  // Playing, Paused, Stopped
    float Volume { get; set; }       // 0.0 to 1.0
    float Pitch { get; set; }        // 1.0 = normal speed
    bool Loop { get; set; }
    Vector3 Position { get; set; }   // 3D world position
    float MinDistance { get; set; }  // Full volume distance
    float MaxDistance { get; set; }  // Silence distance

    void Play(AudioClip clip);
    void Pause();
    void Resume();
    void Stop();
}
```

### IAudioListener

3D audio listener (typically the camera):

```beef
interface IAudioListener
{
    Vector3 Position { get; set; }
    Vector3 Forward { get; set; }
    Vector3 Up { get; set; }
}
```

### IAudioStream

Streaming playback for music and long audio:

```beef
interface IAudioStream
{
    AudioSourceState State { get; }
    float Duration { get; }
    int32 SampleRate { get; }
    int32 Channels { get; }
    float Volume { get; set; }
    bool Loop { get; set; }

    void Play();
    void Pause();
    void Resume();
    void Stop();
    void Seek(float timeInSeconds);
}
```

## Audio Decoders

The `Sedulous.Audio.Decoders` library provides format-independent audio decoding.

### Supported Formats

| Format | Extensions | Library | Notes |
|--------|------------|---------|-------|
| FLAC | .flac | dr_flac | Lossless compression |
| OGG Vorbis | .ogg | stb_vorbis | Lossy compression |
| MP3 | .mp3 | dr_mp3 | Lossy compression, ID3 tags supported |
| WAV | .wav, .wave | dr_wav | RIFF, RIFX, RF64, W64, AIFF containers |

### AudioDecoderFactory

Automatically detects format and decodes audio:

```beef
let factory = new AudioDecoderFactory();
defer delete factory;

// Register all built-in decoders
factory.RegisterDefaultDecoders();

// Decode from file
if (factory.DecodeFile("music.mp3") case .Ok(let clip))
{
    defer delete clip;
    // Use clip...
}

// Decode from memory
let fileData = scope List<uint8>();
File.ReadAll("sound.ogg", fileData);

if (factory.Decode(fileData, ".ogg") case .Ok(let clip))
{
    defer delete clip;
    // Use clip...
}
```

### IAudioDecoder

Interface for individual decoders:

```beef
interface IAudioDecoder
{
    StringView Name { get; }
    void GetSupportedExtensions(List<StringView> outExtensions);
    bool CanDecode(Span<uint8> header);  // Header-based detection
    Result<AudioClip> Decode(Span<uint8> data);
}
```

### Custom Decoders

Register custom decoders for additional formats:

```beef
class MyCustomDecoder : IAudioDecoder
{
    public StringView Name => "Custom";

    public void GetSupportedExtensions(List<StringView> outExtensions)
    {
        outExtensions.Add(".custom");
    }

    public bool CanDecode(Span<uint8> header)
    {
        // Check magic bytes
        return header.Length >= 4 && header[0] == 'C' && header[1] == 'U';
    }

    public Result<AudioClip> Decode(Span<uint8> data)
    {
        // Decode to PCM...
        return .Ok(new AudioClip(pcmData, dataLen, sampleRate, channels, .Int16));
    }
}

// Register
factory.RegisterDecoder(new MyCustomDecoder());
```

## 3D Audio

The audio system supports 3D spatialization with distance attenuation and stereo panning.

### Setting Up the Listener

```beef
// Position listener at camera location
audioSystem.Listener.Position = camera.Position;
audioSystem.Listener.Forward = camera.Forward;
audioSystem.Listener.Up = camera.Up;
```

### 3D Sound Sources

```beef
let source = audioSystem.CreateSource();
source.Position = .(10, 0, 5);    // World position
source.MinDistance = 2.0f;         // Full volume within 2 units
source.MaxDistance = 50.0f;        // Silence beyond 50 units
source.Play(clip);
```

### One-Shot 3D Sounds

```beef
// Play explosion at position (no source management needed)
audioSystem.PlayOneShot3D(explosionClip, enemyPosition, volume: 1.0f);
```

### Distance Attenuation

Sound volume is calculated using linear attenuation:

- Distance ≤ MinDistance: Full volume
- Distance ≥ MaxDistance: Silent
- Between: Linear interpolation

### Stereo Panning

Sounds are panned based on their position relative to the listener:
- Sounds to the left play louder in the left speaker
- Sounds to the right play louder in the right speaker
- Uses constant-power panning for smooth transitions

## Music Streaming

For long audio files (music, ambient), use streaming to avoid loading entire files into memory:

```beef
if (audioSystem.OpenStream("music/background.wav") case .Ok(let stream))
{
    stream.Volume = 0.5f;
    stream.Loop = true;
    stream.Play();

    // Later...
    stream.Seek(30.0f);  // Seek to 30 seconds

    // When done
    stream.Stop();
    delete stream;
}
```

## Volume Control

### Master Volume

Affects all audio output:

```beef
audioSystem.MasterVolume = 0.8f;  // 80% volume
```

### Source Volume

Individual source volume is multiplied with master:

```beef
source.Volume = 0.5f;  // Effective = 0.5 * MasterVolume
```

### Pause/Resume All

```beef
// Pause everything (e.g., when game paused)
audioSystem.PauseAll();

// Resume
audioSystem.ResumeAll();
```

## Pitch Control

Adjust playback speed:

```beef
source.Pitch = 1.0f;   // Normal speed
source.Pitch = 1.5f;   // 50% faster (higher pitch)
source.Pitch = 0.5f;   // 50% slower (lower pitch)
```

## Complete Example

```beef
class GameAudio
{
    private SDL3AudioSystem mAudioSystem ~ delete _;
    private AudioDecoderFactory mDecoderFactory ~ delete _;
    private Dictionary<String, AudioClip> mClipCache = new .() ~ DeleteDictionaryAndKeysAndValues!(_);
    private IAudioSource mMusicSource;

    public bool Initialize()
    {
        mAudioSystem = new SDL3AudioSystem();
        if (!mAudioSystem.IsInitialized)
            return false;

        mDecoderFactory = new AudioDecoderFactory();
        mDecoderFactory.RegisterDefaultDecoders();

        return true;
    }

    public Result<AudioClip> LoadClip(StringView name, StringView path)
    {
        // Check cache
        let nameStr = scope String(name);
        if (mClipCache.TryGetValue(nameStr, let existing))
            return .Ok(existing);

        // Decode file
        if (mDecoderFactory.DecodeFile(path) case .Ok(let clip))
        {
            mClipCache[new String(name)] = clip;
            return .Ok(clip);
        }

        return .Err;
    }

    public void PlaySound(StringView name, float volume = 1.0f)
    {
        let nameStr = scope String(name);
        if (mClipCache.TryGetValue(nameStr, let clip))
            mAudioSystem.PlayOneShot(clip, volume);
    }

    public void PlaySound3D(StringView name, Vector3 position, float volume = 1.0f)
    {
        let nameStr = scope String(name);
        if (mClipCache.TryGetValue(nameStr, let clip))
            mAudioSystem.PlayOneShot3D(clip, position, volume);
    }

    public void PlayMusic(StringView path)
    {
        StopMusic();

        if (mAudioSystem.OpenStream(path) case .Ok(let stream))
        {
            mMusicSource = stream;
            stream.Loop = true;
            stream.Volume = 0.6f;
            stream.Play();
        }
    }

    public void StopMusic()
    {
        if (mMusicSource != null)
        {
            mMusicSource.Stop();
            delete mMusicSource;
            mMusicSource = null;
        }
    }

    public void UpdateListener(Vector3 position, Vector3 forward, Vector3 up)
    {
        mAudioSystem.Listener.Position = position;
        mAudioSystem.Listener.Forward = forward;
        mAudioSystem.Listener.Up = up;
    }

    public void Update()
    {
        mAudioSystem.Update();
    }

    public void Shutdown()
    {
        StopMusic();
        // Clips cleaned up by destructor
    }
}
```

## Performance Tips

1. **Preload audio clips** - Load clips during initialization, not during gameplay
2. **Use streaming for music** - Don't load large files entirely into memory
3. **Limit simultaneous sources** - Many concurrent sounds can cause audio glitches
4. **Call Update() every frame** - Required for 3D audio calculations and one-shot cleanup
5. **Cache decoded clips** - Avoid decoding the same file multiple times
6. **Use appropriate formats**:
   - **WAV** - Best for short sound effects (no decode overhead)
   - **OGG** - Good balance of quality and size for sound effects
   - **MP3** - Wide compatibility, good for music
   - **FLAC** - Lossless quality for music (larger files)
