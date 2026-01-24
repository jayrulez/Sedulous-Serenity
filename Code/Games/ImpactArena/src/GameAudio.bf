namespace ImpactArena;

using System;
using Sedulous.Audio;
using Sedulous.Audio.Decoders;
using Sedulous.Framework.Audio;

class GameAudio
{
	private AudioSubsystem mAudio;
	private AudioDecoderFactory mDecoder = new .() ~ delete _;

	// Sound clips
	private AudioClip mDashClip ~ delete _;
	private AudioClip mHitClip ~ delete _;
	private AudioClip mEnemyDeathClip ~ delete _;
	private AudioClip mPlayerDeathClip ~ delete _;
	private AudioClip mPickupClip ~ delete _;
	private AudioClip mShockwaveClip ~ delete _;
	private AudioClip mWaveStartClip ~ delete _;
	private AudioClip mGameOverClip ~ delete _;
	private AudioClip mComboClip ~ delete _;

	public float SFXVolume = 0.3f;

	public bool Initialize(AudioSubsystem audioSubsystem, delegate void(StringView, String) getAssetPath)
	{
		mAudio = audioSubsystem;
		mDecoder.RegisterDefaultDecoders();

		// Load sci-fi sounds
		mDashClip = LoadOgg("samples/audio/kenney_sci-fi-sounds/Audio/thrusterFire_000.ogg", getAssetPath);
		mHitClip = LoadOgg("samples/audio/kenney_sci-fi-sounds/Audio/impactMetal_000.ogg", getAssetPath);
		mEnemyDeathClip = LoadOgg("samples/audio/kenney_sci-fi-sounds/Audio/explosionCrunch_000.ogg", getAssetPath);
		mPlayerDeathClip = LoadOgg("samples/audio/kenney_sci-fi-sounds/Audio/lowFrequency_explosion_000.ogg", getAssetPath);
		mPickupClip = LoadOgg("samples/audio/kenney_sci-fi-sounds/Audio/forceField_000.ogg", getAssetPath);
		mShockwaveClip = LoadOgg("samples/audio/kenney_sci-fi-sounds/Audio/forceField_004.ogg", getAssetPath);
		mWaveStartClip = LoadOgg("samples/audio/kenney_sci-fi-sounds/Audio/computerNoise_000.ogg", getAssetPath);
		mGameOverClip = LoadOgg("samples/audio/kenney_sci-fi-sounds/Audio/lowFrequency_explosion_001.ogg", getAssetPath);

		// Load impact sounds
		mComboClip = LoadOgg("samples/audio/kenney_impact-sounds/Audio/impactGlass_medium_000.ogg", getAssetPath);

		let loaded = (mDashClip != null ? 1 : 0) + (mHitClip != null ? 1 : 0) +
			(mEnemyDeathClip != null ? 1 : 0) + (mPlayerDeathClip != null ? 1 : 0) +
			(mPickupClip != null ? 1 : 0) + (mShockwaveClip != null ? 1 : 0) +
			(mWaveStartClip != null ? 1 : 0) + (mGameOverClip != null ? 1 : 0) +
			(mComboClip != null ? 1 : 0);
		Console.WriteLine($"GameAudio: Loaded {loaded}/9 sound clips");
		return loaded > 0;
	}

	private AudioClip LoadOgg(StringView relativePath, delegate void(StringView, String) getAssetPath)
	{
		let fullPath = scope String();
		getAssetPath(relativePath, fullPath);

		switch (mDecoder.DecodeFile(fullPath))
		{
		case .Ok(let clip):
			return clip;
		case .Err:
			Console.WriteLine($"GameAudio: Failed to load '{relativePath}'");
			return null;
		}
	}

	public void PlayDash()
	{
		if (mAudio != null && mDashClip != null)
			mAudio.PlayOneShot(mDashClip, SFXVolume * 0.5f);
	}

	public void PlayHit()
	{
		if (mAudio != null && mHitClip != null)
			mAudio.PlayOneShot(mHitClip, SFXVolume);
	}

	public void PlayEnemyDeath()
	{
		if (mAudio != null && mEnemyDeathClip != null)
			mAudio.PlayOneShot(mEnemyDeathClip, SFXVolume * 0.8f);
	}

	public void PlayPlayerDeath()
	{
		if (mAudio != null && mPlayerDeathClip != null)
			mAudio.PlayOneShot(mPlayerDeathClip, SFXVolume);
	}

	public void PlayPickup()
	{
		if (mAudio != null && mPickupClip != null)
			mAudio.PlayOneShot(mPickupClip, SFXVolume * 0.7f);
	}

	public void PlayShockwave()
	{
		if (mAudio != null && mShockwaveClip != null)
			mAudio.PlayOneShot(mShockwaveClip, SFXVolume);
	}

	public void PlayWaveStart()
	{
		if (mAudio != null && mWaveStartClip != null)
			mAudio.PlayOneShot(mWaveStartClip, SFXVolume * 0.25f);
	}

	public void PlayGameOver()
	{
		if (mAudio != null && mGameOverClip != null)
			mAudio.PlayOneShot(mGameOverClip, SFXVolume);
	}

	public void PlayCombo()
	{
		if (mAudio != null && mComboClip != null)
			mAudio.PlayOneShot(mComboClip, SFXVolume * 0.6f);
	}
}
