namespace Sedulous.Framework.Audio;

using System;
using System.Collections;
using Sedulous.Audio;
using Sedulous.Framework.Scenes;
using Sedulous.Mathematics;
using Sedulous.Serialization;

/// Scene module that manages audio sources for entities.
/// Created automatically by AudioSubsystem for each scene.
class AudioSceneModule : SceneModule
{
	private AudioSubsystem mSubsystem;
	private Scene mScene;

	/// Creates an AudioSceneModule linked to the given subsystem.
	public this(AudioSubsystem subsystem)
	{
		mSubsystem = subsystem;
	}

	/// Gets the audio subsystem.
	public AudioSubsystem Subsystem => mSubsystem;

	public override void OnSceneCreate(Scene scene)
	{
		mScene = scene;
	}

	public override void OnSceneDestroy(Scene scene)
	{
		// Clean up all audio sources
		for (let (entity, audioSource) in scene.Query<AudioSourceComponent>())
		{
			if (audioSource.Source != null)
			{
				audioSource.Source.Stop();
				mSubsystem?.AudioSystem?.DestroySource(audioSource.Source);
				audioSource.Source = null;
			}
		}
		mScene = null;
	}

	public override void Update(Scene scene, float deltaTime)
	{
		if (mSubsystem?.AudioSystem == null)
			return;

		// Update listener position
		UpdateListener(scene);

		// Update audio sources
		for (let (entity, audioSource) in scene.Query<AudioSourceComponent>())
		{
			if (audioSource.Source == null)
				continue;

			// Sync audio properties from component
			audioSource.Source.Volume = audioSource.Volume * mSubsystem.EffectiveSFXVolume;
			audioSource.Source.Pitch = audioSource.Pitch;

			if (audioSource.Spatial)
			{
				let transform = scene.GetTransform(entity);
				audioSource.Source.Position = transform.Position;
				audioSource.Source.MinDistance = audioSource.MinDistance;
				audioSource.Source.MaxDistance = audioSource.MaxDistance;
			}
		}
	}

	public override void OnEntityDestroyed(Scene scene, EntityId entity)
	{
		// Clean up audio source if entity has one
		if (let audioSource = scene.GetComponent<AudioSourceComponent>(entity))
		{
			if (audioSource.Source != null)
			{
				audioSource.Source.Stop();
				mSubsystem?.AudioSystem?.DestroySource(audioSource.Source);
				audioSource.Source = null;
			}
		}
	}

	/// Plays a sound on an entity. Creates audio source if needed.
	public void Play(EntityId entity, AudioClip clip, float volume = 1.0f, bool loop = false, bool spatial = true)
	{
		if (mScene == null || mSubsystem?.AudioSystem == null)
			return;

		var audioSource = mScene.GetComponent<AudioSourceComponent>(entity);
		if (audioSource == null)
		{
			mScene.SetComponent<AudioSourceComponent>(entity, .Default);
			audioSource = mScene.GetComponent<AudioSourceComponent>(entity);
		}

		// Stop and destroy existing source
		if (audioSource.Source != null)
		{
			audioSource.Source.Stop();
			mSubsystem.AudioSystem.DestroySource(audioSource.Source);
		}

		// Create new source
		let source = mSubsystem.AudioSystem.CreateSource();
		audioSource.Source = source;
		audioSource.Clip = clip;
		audioSource.Volume = volume;
		audioSource.Spatial = spatial;
		audioSource.Loop = loop;

		source.Volume = volume * mSubsystem.EffectiveSFXVolume;
		source.Loop = loop;
		source.Pitch = audioSource.Pitch;
		source.MinDistance = audioSource.MinDistance;
		source.MaxDistance = audioSource.MaxDistance;

		if (spatial)
		{
			let transform = mScene.GetTransform(entity);
			source.Position = transform.Position;
		}

		source.Play(clip);
	}

	/// Stops the sound on an entity.
	public void Stop(EntityId entity)
	{
		if (mScene == null)
			return;

		if (let audioSource = mScene.GetComponent<AudioSourceComponent>(entity))
		{
			if (audioSource.Source != null)
				audioSource.Source.Stop();
		}
	}

	/// Pauses the sound on an entity.
	public void Pause(EntityId entity)
	{
		if (mScene == null)
			return;

		if (let audioSource = mScene.GetComponent<AudioSourceComponent>(entity))
		{
			if (audioSource.Source != null)
				audioSource.Source.Pause();
		}
	}

	/// Resumes the sound on an entity.
	public void Resume(EntityId entity)
	{
		if (mScene == null)
			return;

		if (let audioSource = mScene.GetComponent<AudioSourceComponent>(entity))
		{
			if (audioSource.Source != null)
				audioSource.Source.Resume();
		}
	}

	private void UpdateListener(Scene scene)
	{
		let listener = mSubsystem.AudioSystem.Listener;
		if (listener == null)
			return;

		// Find active listener entity
		for (let (entity, listenerComp) in scene.Query<AudioListenerComponent>())
		{
			if (listenerComp.Active)
			{
				let transform = scene.GetTransform(entity);
				listener.Position = transform.Position;

				// Calculate forward/up from rotation
				let forward = Vector3.Transform(Vector3.Forward, transform.Rotation);
				let up = Vector3.Transform(Vector3.Up, transform.Rotation);
				listener.Forward = forward;
				listener.Up = up;
				break;
			}
		}
	}
}
