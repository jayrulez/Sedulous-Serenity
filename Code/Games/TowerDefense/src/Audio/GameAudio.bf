namespace TowerDefense.Audio;

using System;
using System.Collections;
using Sedulous.Audio;
using Sedulous.Audio.Decoders;
using Sedulous.Framework.Audio;
using Sedulous.Mathematics;
using TowerDefense.Data;

/// Manages all game audio - sound effects and music.
/// Generates procedural sounds for game events.
/// Ported to Sedulous.Framework architecture.
class GameAudio
{
	private AudioSubsystem mAudioSubsystem;
	private AudioDecoderFactory mDecoderFactory;

	// Sound effect clips (procedurally generated)
	private AudioClip mCannonFireClip ~ delete _;
	private AudioClip mArcherFireClip ~ delete _;
	private AudioClip mFrostFireClip ~ delete _;
	private AudioClip mMortarFireClip ~ delete _;
	private AudioClip mSAMFireClip ~ delete _;
	private AudioClip mEnemyDeathClip ~ delete _;
	private AudioClip mEnemyExitClip ~ delete _;
	private AudioClip mWaveStartClip ~ delete _;
	private AudioClip mWaveCompleteClip ~ delete _;
	private AudioClip mVictoryClip ~ delete _;
	private AudioClip mGameOverClip ~ delete _;
	private AudioClip mUIClickClip ~ delete _;
	private AudioClip mTowerPlaceClip ~ delete _;
	private AudioClip mNoMoneyClip ~ delete _;

	// Background music
	private AudioClip mProceduralMusicClip ~ delete _;  // Procedural music (fallback)
	private IAudioStream mMusicStream;                   // Music playback stream
	private bool mMusicPlaying = false;
	private bool mUseDecodedMusic = true;  // Try decoded file first, fall back to procedural
	private String mMusicFilePath = new .("Assets/sounds/background.mp3") ~ delete _;

	// Tower fire clips lookup (for direct access)
	private Dictionary<String, AudioClip> mTowerFireClips = new .() ~ DeleteDictionaryAndKeys!(_);

	// Volume settings
	public float SFXVolume
	{
		get => mAudioSubsystem?.SFXVolume ?? 0.1f;
		set { if (mAudioSubsystem != null) mAudioSubsystem.SFXVolume = value; }
	}

	public float MusicVolume
	{
		get => mAudioSubsystem?.MusicVolume ?? 0.1f;
		set { if (mAudioSubsystem != null) mAudioSubsystem.MusicVolume = value; }
	}

	public this(AudioSubsystem audioSubsystem, AudioDecoderFactory decoderFactory)
	{
		mAudioSubsystem = audioSubsystem;
		mDecoderFactory = decoderFactory;

		if (mAudioSubsystem != null && mAudioSubsystem.AudioSystem != null)
		{
			GenerateSounds();
			Console.WriteLine("GameAudio: Sounds generated");
		}
		else
		{
			Console.WriteLine("GameAudio: AudioSubsystem not available, audio disabled");
		}
	}

	/// Generates all procedural sound effects.
	private void GenerateSounds()
	{
		// Tower fire sounds - different frequencies/characteristics per tower
		mCannonFireClip = GenerateBoom(100, 0.15f);       // Low boom
		mArcherFireClip = GenerateClick(1200, 0.05f);     // Quick twang
		mFrostFireClip = GenerateSweep(800, 400, 0.12f);  // High to low sweep
		mMortarFireClip = GenerateBoom(60, 0.25f);        // Deep boom
		mSAMFireClip = GenerateSweep(400, 1200, 0.08f);   // Rising whoosh

		// Register tower fire clips
		RegisterTowerFireClips();

		// Enemy sounds
		mEnemyDeathClip = GenerateNoiseBurst(0.1f);
		mEnemyExitClip = GenerateSweep(400, 200, 0.2f);

		// Wave sounds
		mWaveStartClip = GenerateFanfare(true);
		mWaveCompleteClip = GenerateFanfare(false);

		// Game state sounds
		mVictoryClip = GenerateVictoryJingle();
		mGameOverClip = GenerateGameOverSound();

		// UI sounds
		mUIClickClip = GenerateClick(800, 0.03f);
		mTowerPlaceClip = GenerateClick(400, 0.08f);
		mNoMoneyClip = GenerateBuzz(200, 0.15f);

		// Procedural background music (fallback)
		mProceduralMusicClip = GenerateBackgroundMusic();
	}

	/// Registers tower fire clips.
	private void RegisterTowerFireClips()
	{
		mTowerFireClips[new String("tower_fire_cannon")] = mCannonFireClip;
		mTowerFireClips[new String("tower_fire_archer")] = mArcherFireClip;
		mTowerFireClips[new String("tower_fire_frost")] = mFrostFireClip;
		mTowerFireClips[new String("tower_fire_mortar")] = mMortarFireClip;
		mTowerFireClips[new String("tower_fire_sam")] = mSAMFireClip;
	}

	/// Gets the clip name for a tower's fire sound.
	public static void GetTowerFireClipName(StringView towerName, String outName)
	{
		outName.Clear();
		outName.Append("tower_fire_");
		let lowerName = scope String(towerName);
		lowerName.ToLower();
		outName.Append(lowerName);
	}

	/// Gets the tower fire clip for the given tower name.
	public AudioClip GetTowerFireClip(StringView towerName)
	{
		let clipName = scope String();
		GetTowerFireClipName(towerName, clipName);

		if (mTowerFireClips.TryGetValue(clipName, let clip))
			return clip;

		// Fallback to cannon
		if (mTowerFireClips.TryGetValue("tower_fire_cannon", let fallback))
			return fallback;

		return mCannonFireClip;
	}

	// ==================== Playback Methods ====================

	/// Plays a clip at a 3D position (convenience wrapper).
	public void PlaySpatial(AudioClip clip, Vector3 position)
	{
		if (mAudioSubsystem == null || clip == null)
			return;
		mAudioSubsystem.PlayOneShot3D(clip, position);
	}

	/// Plays tower fire sound based on tower type.
	public void PlayTowerFire(TowerDefinition def, Vector3 position)
	{
		if (mAudioSubsystem == null)
			return;

		AudioClip clip = null;

		// Select clip based on tower name
		switch (def.Name)
		{
		case "Cannon": clip = mCannonFireClip;
		case "Archer": clip = mArcherFireClip;
		case "Frost": clip = mFrostFireClip;
		case "Mortar": clip = mMortarFireClip;
		case "SAM": clip = mSAMFireClip;
		default: clip = mCannonFireClip;  // Default to cannon
		}

		if (clip != null)
			mAudioSubsystem.PlayOneShot3D(clip, position);
	}

	/// Plays enemy death sound.
	public void PlayEnemyDeath(Vector3 position)
	{
		if (mAudioSubsystem == null || mEnemyDeathClip == null)
			return;

		mAudioSubsystem.PlayOneShot3D(mEnemyDeathClip, position, 0.8f);
	}

	/// Plays enemy reached exit sound.
	public void PlayEnemyExit()
	{
		if (mAudioSubsystem == null || mEnemyExitClip == null)
			return;

		mAudioSubsystem.PlayOneShot(mEnemyExitClip);
	}

	/// Plays wave start sound.
	public void PlayWaveStart()
	{
		if (mAudioSubsystem == null || mWaveStartClip == null)
			return;

		mAudioSubsystem.PlayOneShot(mWaveStartClip);
	}

	/// Plays wave complete sound.
	public void PlayWaveComplete()
	{
		if (mAudioSubsystem == null || mWaveCompleteClip == null)
			return;

		mAudioSubsystem.PlayOneShot(mWaveCompleteClip);
	}

	/// Plays victory jingle.
	public void PlayVictory()
	{
		if (mAudioSubsystem == null || mVictoryClip == null)
			return;

		mAudioSubsystem.PlayOneShot(mVictoryClip);
	}

	/// Plays game over sound.
	public void PlayGameOver()
	{
		if (mAudioSubsystem == null || mGameOverClip == null)
			return;

		mAudioSubsystem.PlayOneShot(mGameOverClip);
	}

	/// Plays UI click sound.
	public void PlayUIClick()
	{
		if (mAudioSubsystem == null || mUIClickClip == null)
			return;

		mAudioSubsystem.PlayOneShot(mUIClickClip, 0.5f);
	}

	/// Plays tower placement sound.
	public void PlayTowerPlace()
	{
		if (mAudioSubsystem == null || mTowerPlaceClip == null)
			return;

		mAudioSubsystem.PlayOneShot(mTowerPlaceClip);
	}

	/// Plays "not enough money" sound.
	public void PlayNoMoney()
	{
		if (mAudioSubsystem == null || mNoMoneyClip == null)
			return;

		mAudioSubsystem.PlayOneShot(mNoMoneyClip, 0.6f);
	}

	// ==================== Music Methods ====================

	/// Starts playing background music.
	public void StartMusic()
	{
		if (mAudioSubsystem == null || mMusicPlaying)
			return;

		// Try streaming from file first
		if (mUseDecodedMusic)
		{
			switch (mAudioSubsystem.PlayMusic(mMusicFilePath, loop: true))
			{
			case .Ok(let stream):
				mMusicStream = stream;
				mMusicPlaying = true;
				Console.WriteLine($"GameAudio: Background music started (streaming from file)");
				return;
			case .Err:
				Console.WriteLine($"GameAudio: Failed to stream music file, using procedural");
			}
		}

		// Fallback to procedural clip (play via one-shot loop - not ideal but works)
		if (mProceduralMusicClip != null)
		{
			// Use AudioSystem's source for looping
			if (let audioSystem = mAudioSubsystem.AudioSystem)
			{
				let source = audioSystem.CreateSource();
				if (source != null)
				{
					source.Volume = mAudioSubsystem.EffectiveMusicVolume;
					source.Loop = true;
					source.Play(mProceduralMusicClip);
					mMusicPlaying = true;
					Console.WriteLine("GameAudio: Background music started (procedural)");
				}
			}
		}
	}

	/// Stops playing background music.
	public void StopMusic()
	{
		if (!mMusicPlaying)
			return;

		if (mMusicStream != null)
		{
			mAudioSubsystem.StopMusic(mMusicStream);
			mMusicStream = null;
		}

		mMusicPlaying = false;
		Console.WriteLine("GameAudio: Background music stopped");
	}

	/// Pauses background music.
	public void PauseMusic()
	{
		if (!mMusicPlaying || mMusicStream == null)
			return;

		mMusicStream.Pause();
	}

	/// Resumes background music.
	public void ResumeMusic()
	{
		if (!mMusicPlaying || mMusicStream == null)
			return;

		mMusicStream.Resume();
	}

	// ==================== Sound Generation ====================

	private const int32 SAMPLE_RATE = 44100;

	/// Generates a low-frequency boom/explosion sound.
	private AudioClip GenerateBoom(float frequency, float duration)
	{
		int32 sampleCount = (int32)(SAMPLE_RATE * duration);
		int16[] samples = new int16[sampleCount];
		defer delete samples;

		for (int32 i = 0; i < sampleCount; i++)
		{
			float t = (float)i / SAMPLE_RATE;
			float progress = t / duration;

			// Frequency drops over time
			float freq = frequency * (1.0f - progress * 0.5f);

			// Amplitude envelope (quick attack, slow decay)
			float envelope = Math.Exp(-progress * 8.0f);

			// Add some noise for texture
			float noise = ((float)gRand.NextDouble() * 2.0f - 1.0f) * 0.3f;

			// Sine wave + noise
			float sample = (Math.Sin(2.0f * Math.PI_f * freq * t) + noise) * envelope;
			samples[i] = (int16)(sample * 20000);
		}

		return AudioClip.FromInt16(samples, SAMPLE_RATE, 1);
	}

	/// Generates a quick click/pop sound.
	private AudioClip GenerateClick(float frequency, float duration)
	{
		int32 sampleCount = (int32)(SAMPLE_RATE * duration);
		int16[] samples = new int16[sampleCount];
		defer delete samples;

		for (int32 i = 0; i < sampleCount; i++)
		{
			float t = (float)i / SAMPLE_RATE;
			float progress = t / duration;

			// Sharp attack, quick decay
			float envelope = Math.Exp(-progress * 20.0f);

			float sample = Math.Sin(2.0f * Math.PI_f * frequency * t) * envelope;
			samples[i] = (int16)(sample * 25000);
		}

		return AudioClip.FromInt16(samples, SAMPLE_RATE, 1);
	}

	/// Generates a frequency sweep sound.
	private AudioClip GenerateSweep(float startFreq, float endFreq, float duration)
	{
		int32 sampleCount = (int32)(SAMPLE_RATE * duration);
		int16[] samples = new int16[sampleCount];
		defer delete samples;

		float phase = 0.0f;

		for (int32 i = 0; i < sampleCount; i++)
		{
			float t = (float)i / SAMPLE_RATE;
			float progress = t / duration;

			// Interpolate frequency
			float freq = startFreq + (endFreq - startFreq) * progress;

			// Amplitude envelope
			float envelope = 1.0f - progress * progress;

			phase += 2.0f * Math.PI_f * freq / SAMPLE_RATE;
			float sample = Math.Sin(phase) * envelope;
			samples[i] = (int16)(sample * 20000);
		}

		return AudioClip.FromInt16(samples, SAMPLE_RATE, 1);
	}

	/// Generates a noise burst.
	private AudioClip GenerateNoiseBurst(float duration)
	{
		int32 sampleCount = (int32)(SAMPLE_RATE * duration);
		int16[] samples = new int16[sampleCount];
		defer delete samples;

		for (int32 i = 0; i < sampleCount; i++)
		{
			float progress = (float)i / sampleCount;
			float envelope = Math.Exp(-progress * 15.0f);

			float noise = (float)gRand.NextDouble() * 2.0f - 1.0f;
			samples[i] = (int16)(noise * envelope * 18000);
		}

		return AudioClip.FromInt16(samples, SAMPLE_RATE, 1);
	}

	/// Generates a buzzing error sound.
	private AudioClip GenerateBuzz(float frequency, float duration)
	{
		int32 sampleCount = (int32)(SAMPLE_RATE * duration);
		int16[] samples = new int16[sampleCount];
		defer delete samples;

		for (int32 i = 0; i < sampleCount; i++)
		{
			float t = (float)i / SAMPLE_RATE;
			float progress = t / duration;

			// Square wave for harsh sound
			float phase = (t * frequency) % 1.0f;
			float sample = phase < 0.5f ? 1.0f : -1.0f;

			// Envelope
			float envelope = 1.0f - progress;

			samples[i] = (int16)(sample * envelope * 12000);
		}

		return AudioClip.FromInt16(samples, SAMPLE_RATE, 1);
	}

	/// Generates a short fanfare (ascending for start, descending for complete).
	private AudioClip GenerateFanfare(bool ascending)
	{
		float duration = 0.3f;
		int32 sampleCount = (int32)(SAMPLE_RATE * duration);
		int16[] samples = new int16[sampleCount];
		defer delete samples;

		// Three-note arpeggio
		float[] notes = ascending ?
			scope float[](523.25f, 659.25f, 783.99f) : // C5, E5, G5
			scope float[](783.99f, 659.25f, 523.25f);  // G5, E5, C5

		float noteLength = duration / 3.0f;

		for (int32 i = 0; i < sampleCount; i++)
		{
			float t = (float)i / SAMPLE_RATE;
			int noteIndex = Math.Min((int)(t / noteLength), 2);
			float noteT = t % noteLength;
			float noteProgress = noteT / noteLength;

			float freq = notes[noteIndex];
			float envelope = Math.Exp(-noteProgress * 5.0f);

			float sample = Math.Sin(2.0f * Math.PI_f * freq * t) * envelope;
			samples[i] = (int16)(sample * 18000);
		}

		return AudioClip.FromInt16(samples, SAMPLE_RATE, 1);
	}

	/// Generates a victory jingle (ascending major chord).
	private AudioClip GenerateVictoryJingle()
	{
		float duration = 0.8f;
		int32 sampleCount = (int32)(SAMPLE_RATE * duration);
		int16[] samples = new int16[sampleCount];
		defer delete samples;

		// Major chord notes: C, E, G, C (octave)
		float[] notes = scope float[](261.63f, 329.63f, 392.00f, 523.25f);

		for (int32 i = 0; i < sampleCount; i++)
		{
			float t = (float)i / SAMPLE_RATE;

			float sample = 0.0f;

			// Stagger note entry
			for (int n = 0; n < notes.Count; n++)
			{
				float noteStart = n * 0.12f;
				if (t >= noteStart)
				{
					float noteT = t - noteStart;
					float noteEnv = Math.Exp(-noteT * 2.0f);
					sample += Math.Sin(2.0f * Math.PI_f * notes[n] * t) * noteEnv * 0.25f;
				}
			}

			samples[i] = (int16)(sample * 22000);
		}

		return AudioClip.FromInt16(samples, SAMPLE_RATE, 1);
	}

	/// Generates a game over sound (descending minor).
	private AudioClip GenerateGameOverSound()
	{
		float duration = 0.6f;
		int32 sampleCount = (int32)(SAMPLE_RATE * duration);
		int16[] samples = new int16[sampleCount];
		defer delete samples;

		// Descending minor: Eb, C, Ab (sad progression)
		float[] notes = scope float[](311.13f, 261.63f, 207.65f);

		for (int32 i = 0; i < sampleCount; i++)
		{
			float t = (float)i / SAMPLE_RATE;
			int noteIndex = Math.Min((int)(t / 0.2f), 2);
			float noteT = t % 0.2f;
			float noteProgress = noteT / 0.2f;

			float freq = notes[noteIndex];
			float envelope = Math.Exp(-noteProgress * 3.0f);

			// Add slight vibrato for sadness
			float vibrato = Math.Sin(t * 30.0f) * 5.0f;
			float sample = Math.Sin(2.0f * Math.PI_f * (freq + vibrato) * t) * envelope;

			samples[i] = (int16)(sample * 18000);
		}

		return AudioClip.FromInt16(samples, SAMPLE_RATE, 1);
	}

	/// Generates ambient background music (loopable).
	private AudioClip GenerateBackgroundMusic()
	{
		// Create a 4-second ambient loop
		float duration = 4.0f;
		int32 sampleCount = (int32)(SAMPLE_RATE * duration);
		int16[] samples = new int16[sampleCount];
		defer delete samples;

		// Ambient drone using layered sine waves
		// Minor key base notes for atmospheric feel
		float[] baseFreqs = scope float[](
			110.0f,    // A2 (root)
			164.81f,   // E3 (fifth)
			220.0f     // A3 (octave)
		);

		for (int32 i = 0; i < sampleCount; i++)
		{
			float t = (float)i / SAMPLE_RATE;
			float loopProgress = t / duration;

			float sample = 0.0f;

			// Layer 1: Deep drone
			for (let freq in baseFreqs)
			{
				// Slow amplitude modulation for movement
				float lfoFreq = 0.2f + freq * 0.001f;
				float lfo = 0.7f + 0.3f * Math.Sin(2.0f * Math.PI_f * lfoFreq * t);

				sample += Math.Sin(2.0f * Math.PI_f * freq * t) * lfo * 0.15f;
			}

			// Layer 2: High shimmer (quiet, adds texture)
			float shimmerFreq = 880.0f + Math.Sin(t * 0.5f) * 20.0f;
			sample += Math.Sin(2.0f * Math.PI_f * shimmerFreq * t) * 0.03f;

			// Layer 3: Very subtle noise for air
			float noise = ((float)gRand.NextDouble() * 2.0f - 1.0f) * 0.02f;
			sample += noise;

			// Crossfade for seamless loop (fade last 0.1s into first 0.1s)
			float fadeTime = 0.1f;
			if (loopProgress > (1.0f - fadeTime / duration))
			{
				float fadeOut = (1.0f - loopProgress) / (fadeTime / duration);
				sample *= fadeOut;
			}

			samples[i] = (int16)(Math.Clamp(sample, -1.0f, 1.0f) * 15000);
		}

		return AudioClip.FromInt16(samples, SAMPLE_RATE, 1);
	}

	// Random generator for noise
	private static Random gRand = new Random() ~ delete _;
}
