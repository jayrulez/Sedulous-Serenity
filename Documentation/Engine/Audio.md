# Sedulous Engine Audio

The `Sedulous.Engine.Audio` library integrates the low-level audio system with the engine's Context/Scene/Entity architecture, providing entity-based 3D audio with automatic position synchronization.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                          Context                                 │
│  └── AudioService (owns IAudioSystem)                           │
│      ├── Audio clip loading/caching                             │
│      ├── Global volume controls (Master, Music, SFX)            │
│      ├── Music stream management                                │
│      └── Auto-creates AudioSceneComponent per scene             │
├─────────────────────────────────────────────────────────────────┤
│                          Scene                                   │
│  └── AudioSceneComponent (per-scene audio)                      │
│      ├── Entity → IAudioSource mappings                         │
│      ├── Auto-syncs entity positions to sources                 │
│      └── Syncs listener with camera or explicit entity          │
├─────────────────────────────────────────────────────────────────┤
│                         Entities                                 │
│  └── Entity                                                     │
│      ├── Transform (position synced to audio)                   │
│      ├── AudioSourceComponent → 3D positional audio             │
│      └── AudioListenerComponent → audio listener                │
└─────────────────────────────────────────────────────────────────┘
```

## Quick Start

```beef
using Sedulous.Audio;
using Sedulous.Audio.SDL3;
using Sedulous.Engine.Audio;
using Sedulous.Engine.Core;

// 1. Create and register AudioService
let audioSystem = new SDL3AudioSystem();
let audioService = new AudioService();
audioService.Initialize(audioSystem);
context.RegisterService<AudioService>(audioService);

// 2. Load audio clips
audioService.LoadClip("explosion", explosionData);
audioService.LoadClip("footstep", footstepData);

// 3. Play sounds
audioService.PlayOneShot("explosion");                    // 2D
audioService.PlayOneShot3D("explosion", enemyPos);        // 3D

// 4. Create scene (AudioSceneComponent auto-added)
let scene = context.SceneManager.CreateScene("Game");

// 5. Add audio to entities
let enemy = scene.CreateEntity("Enemy");
let audioSource = new AudioSourceComponent();
audioSource.Volume = 0.8f;
audioSource.MinDistance = 2.0f;
audioSource.MaxDistance = 50.0f;
enemy.AddComponent(audioSource);

// Play sound at entity position
audioSource.Play("footstep");
```

## AudioService

Context service that manages the audio system, clip caching, and music streaming.

### Registration

```beef
// Create audio backend
let audioSystem = new SDL3AudioSystem();
if (!audioSystem.IsInitialized)
{
    delete audioSystem;
    return .Err;
}

// Create and initialize service
let audioService = new AudioService();
audioService.Initialize(audioSystem, takeOwnership: true);

// Register with context
context.RegisterService<AudioService>(audioService);
```

### Clip Management

Load clips once, play them anywhere:

```beef
// Load from raw data
if (audioService.LoadClip("laser", laserData) case .Ok(let clip))
    Console.WriteLine($"Loaded: {clip.Duration}s");

// Get cached clip
let clip = audioService.GetClip("laser");

// Unload when no longer needed
audioService.UnloadClip("laser");

// Unload all
audioService.UnloadAllClips();
```

### One-Shot Playback

Fire-and-forget sounds (UI clicks, explosions, impacts):

```beef
// 2D sound (no spatialization)
audioService.PlayOneShot("click", volume: 0.5f);
audioService.PlayOneShot(clickClip, volume: 0.5f);

// 3D sound at world position
audioService.PlayOneShot3D("explosion", enemyPosition);
audioService.PlayOneShot3D(explosionClip, enemyPosition, volume: 1.0f);
```

### Music Streaming

Background music with streaming playback:

```beef
// Play music (streams from disk)
if (audioService.PlayMusic("Assets/music/battle.ogg", loop: true) case .Ok(let stream))
{
    stream.Volume = 0.6f;

    // Later: seek to position
    stream.Seek(30.0f);
}

// Stop specific stream
audioService.StopMusic(stream);

// Stop all music
audioService.StopAllMusic();

// Pause/resume all music
audioService.PauseAllMusic();
audioService.ResumeAllMusic();
```

### Volume Controls

Three-tier volume system:

```beef
// Master volume affects everything
audioService.MasterVolume = 0.8f;

// Category volumes multiply with master
audioService.MusicVolume = 0.5f;   // Effective = 0.8 * 0.5 = 0.4
audioService.SFXVolume = 1.0f;     // Effective = 0.8 * 1.0 = 0.8

// Get effective volumes
float sfxVol = audioService.EffectiveSFXVolume;    // Master * SFX
float musicVol = audioService.EffectiveMusicVolume; // Master * Music
```

### Global Controls

```beef
// Pause everything (game paused)
audioService.PauseAll();

// Resume everything
audioService.ResumeAll();
```

## AudioSceneComponent

Automatically added to scenes when AudioService is registered. Manages entity-to-source mappings and listener synchronization.

### Automatic Features

- **Position Sync**: Entity world positions automatically sync to audio sources each frame
- **Listener Sync**: Audio listener follows main camera, or explicit AudioListenerComponent

### Manual Source Management

```beef
let audioScene = scene.GetSceneComponent<AudioSceneComponent>();

// Create source for entity (usually done by AudioSourceComponent)
let source = audioScene.CreateSource(entity);
source.Volume = 0.8f;
source.Play(clip);

// Get existing source
let source = audioScene.GetSource(entity);

// Destroy source
audioScene.DestroySource(entity);
```

### Listener Control

```beef
// Set explicit listener entity
audioScene.SetListenerEntity(playerEntity);

// Clear to use camera fallback
audioScene.ClearListenerEntity();

// Current listener entity (null = using camera)
let listener = audioScene.ListenerEntity;
```

## AudioSourceComponent

Entity component for 3D positional audio. Position automatically syncs with entity transform.

### Basic Usage

```beef
let entity = scene.CreateEntity("Enemy");
entity.Transform.Position = .(10, 0, 5);

let audioSource = new AudioSourceComponent();
audioSource.Volume = 0.7f;
audioSource.Loop = true;
entity.AddComponent(audioSource);

// Play sound
audioSource.Play(ambientClip);
```

### Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `Volume` | float | 1.0 | Volume (0.0 to 1.0) |
| `Pitch` | float | 1.0 | Playback speed (1.0 = normal) |
| `Loop` | bool | false | Loop playback |
| `MinDistance` | float | 1.0 | Full volume distance |
| `MaxDistance` | float | 100.0 | Silence distance |
| `Clip` | AudioClip | null | Default clip to play |
| `PlayOnAttach` | bool | false | Auto-play when attached |

### Playback

```beef
// Play default clip
audioSource.Clip = explosionClip;
audioSource.Play();

// Play specific clip
audioSource.Play(footstepClip);

// Play by name from AudioService cache
audioSource.Play("footstep");

// Controls
audioSource.Pause();
audioSource.Resume();
audioSource.Stop();

// Check state
if (audioSource.State == .Playing)
    Console.WriteLine("Playing...");
```

### Auto-Play on Attach

```beef
let audioSource = new AudioSourceComponent();
audioSource.Clip = ambientClip;
audioSource.Loop = true;
audioSource.PlayOnAttach = true;  // Starts playing when added to entity
entity.AddComponent(audioSource);
```

## AudioListenerComponent

Marks an entity as the audio listener. Overrides the default camera-based listener positioning.

### Usage

```beef
// Attach to player entity
let player = scene.CreateEntity("Player");
player.Transform.Position = playerSpawnPos;

let listener = new AudioListenerComponent();
listener.IsActive = true;
player.AddComponent(listener);
```

### Active State

Only one listener should be active per scene:

```beef
// Deactivate current listener
currentListener.IsActive = false;

// Activate new listener
newListener.IsActive = true;
```

### Camera Fallback

If no AudioListenerComponent exists (or none are active), the audio listener automatically follows the main camera from `RenderSceneComponent`.

## 3D Audio Behavior

### Distance Attenuation

Sound volume decreases with distance from listener:

```
Distance ≤ MinDistance  →  Full volume
Distance ≥ MaxDistance  →  Silent
Between                 →  Linear interpolation
```

```beef
audioSource.MinDistance = 2.0f;   // Full volume within 2 units
audioSource.MaxDistance = 50.0f;  // Silent beyond 50 units
```

### Stereo Panning

Sounds are panned based on position relative to listener:
- Left of listener → louder in left speaker
- Right of listener → louder in right speaker
- Uses constant-power panning for smooth transitions

## Integration with Renderer

AudioSceneComponent integrates with RenderSceneComponent for camera-based listener positioning:

```beef
// AudioSceneComponent.SyncListener() does this automatically:
if (mListenerEntity == null)
{
    if (let renderScene = mScene.GetSceneComponent<RenderSceneComponent>())
    {
        if (let camera = renderScene.GetMainCameraProxy())
        {
            listener.Position = camera.Position;
            listener.Forward = camera.Forward;
            listener.Up = camera.Up;
        }
    }
}
```

## Complete Example

```beef
using Sedulous.Audio;
using Sedulous.Audio.SDL3;
using Sedulous.Audio.Decoders;
using Sedulous.Engine.Audio;
using Sedulous.Engine.Core;

class GameAudioManager
{
    private Context mContext;
    private AudioService mAudioService;
    private AudioDecoderFactory mDecoderFactory;

    public Result<void> Initialize(Context context)
    {
        mContext = context;

        // Create audio system
        let audioSystem = new SDL3AudioSystem();
        if (!audioSystem.IsInitialized)
        {
            delete audioSystem;
            return .Err;
        }

        // Create decoder factory
        mDecoderFactory = new AudioDecoderFactory();
        mDecoderFactory.RegisterDefaultDecoders();

        // Create and register audio service
        mAudioService = new AudioService();
        mAudioService.Initialize(audioSystem);
        context.RegisterService<AudioService>(mAudioService);

        // Set initial volumes
        mAudioService.MasterVolume = 0.8f;
        mAudioService.MusicVolume = 0.6f;
        mAudioService.SFXVolume = 1.0f;

        // Load sound effects
        LoadClip("explosion", "Assets/sfx/explosion.ogg");
        LoadClip("footstep", "Assets/sfx/footstep.ogg");
        LoadClip("laser", "Assets/sfx/laser.ogg");

        return .Ok;
    }

    private void LoadClip(StringView name, StringView path)
    {
        if (mDecoderFactory.DecodeFile(path) case .Ok(let clip))
            mAudioService.LoadClip(name, Span<uint8>(clip.Data, clip.DataLength));
    }

    public void SetupEnemy(Entity enemy)
    {
        let audioSource = new AudioSourceComponent();
        audioSource.Volume = 0.8f;
        audioSource.MinDistance = 3.0f;
        audioSource.MaxDistance = 30.0f;
        enemy.AddComponent(audioSource);
    }

    public void PlayEnemySound(Entity enemy, StringView sound)
    {
        if (let audioSource = enemy.GetComponent<AudioSourceComponent>())
            audioSource.Play(sound);
    }

    public void PlayExplosion(Vector3 position)
    {
        mAudioService.PlayOneShot3D("explosion", position);
    }

    public void PlayUIClick()
    {
        mAudioService.PlayOneShot("click", volume: 0.5f);
    }

    public void PlayBattleMusic()
    {
        mAudioService.PlayMusic("Assets/music/battle.ogg", loop: true);
    }

    public void Shutdown()
    {
        delete mDecoderFactory;
        // AudioService cleaned up by context
    }
}
```

## Service Registration Order

For proper camera-based listener sync, register services in this order:

1. **RendererService** - Provides camera for listener fallback
2. **AudioService** - Uses camera if no explicit listener

## Performance Tips

1. **Preload clips** - Load during initialization, not gameplay
2. **Use one-shots for transient sounds** - Explosions, impacts, UI clicks
3. **Use AudioSourceComponent for persistent sounds** - Ambient loops, character audio
4. **Limit simultaneous sources** - Too many can cause audio glitches
5. **Use streaming for music** - Don't load large files into memory
6. **Cache clips by name** - Avoid decoding the same file multiple times

## Serialization

AudioSourceComponent and AudioListenerComponent support serialization:

```beef
// AudioSourceComponent serializes:
// - volume, pitch, loop
// - minDistance, maxDistance
// - playOnAttach

// AudioListenerComponent serializes:
// - isActive

// Note: AudioClip references must be restored after deserialization
// using clip names and the AudioService cache
```

## See Also

- [Low-Level Audio Library](../Audio.md) - Core audio types and decoders
- [Engine Core](Core.md) - Context, Scene, Entity system
- [Engine Renderer](Renderer.md) - Camera integration
