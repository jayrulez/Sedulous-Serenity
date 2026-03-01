namespace Sedulous.Engine.Audio;

using System;
using System.Collections;
using Sedulous.Audio;
using Sedulous.Engine.Scenes;
using Sedulous.Core.Mathematics;
using Sedulous.Resources;
using Sedulous.Serialization;

/// Internal data for an audio source instance, owned by AudioSceneModule.
public struct AudioSourceInstanceData
{
	public EntityId Entity;
	public IAudioSource Source;
	public AudioClip Clip;
	public ResourceRef ClipRef;
	public float Volume;
	public float Pitch;
	public bool Spatial;
	public bool Loop;
	public bool AutoPlay;
	public float MinDistance;
	public float MaxDistance;
	public bool Active;
}

/// Internal data for an audio listener instance, owned by AudioSceneModule.
public struct AudioListenerInstanceData
{
	public EntityId Entity;
	public bool ListenerActive;
	public bool Active;
}

/// Scene module that manages audio sources and listeners for entities.
/// All data is owned internally — components are thin handles.
class AudioSceneModule : SceneModule
{
	private AudioSubsystem mSubsystem;
	private Scene mScene;

	// Source storage
	private List<AudioSourceInstanceData> mSourceInstances = new .() ~ delete _;
	private List<int32> mFreeSourceSlots = new .() ~ delete _;
	private Dictionary<EntityId, int32> mEntityToSource = new .() ~ delete _;

	// Listener storage
	private List<AudioListenerInstanceData> mListenerInstances = new .() ~ delete _;
	private List<int32> mFreeListenerSlots = new .() ~ delete _;
	private Dictionary<EntityId, int32> mEntityToListener = new .() ~ delete _;

	/// Creates an AudioSceneModule linked to the given subsystem.
	public this(AudioSubsystem subsystem)
	{
		mSubsystem = subsystem;
	}

	/// Gets the audio subsystem.
	public AudioSubsystem Subsystem => mSubsystem;

	/// Exposes source instances for serializer access.
	public List<AudioSourceInstanceData> SourceInstances => mSourceInstances;

	/// Exposes listener instances for serializer access.
	public List<AudioListenerInstanceData> ListenerInstances => mListenerInstances;

	// ==================== Module Lifecycle ====================

	public override void OnSceneCreate(Scene scene)
	{
		mScene = scene;
		scene.RegisterComponentSerializer(new AudioSourceComponentSerializer());
		scene.RegisterComponentSerializer(new AudioListenerComponentSerializer());
	}

	public override void OnSceneDestroy(Scene scene)
	{
		for (var instance in ref mSourceInstances)
		{
			if (!instance.Active)
				continue;
			if (instance.Source != null)
			{
				instance.Source.Stop();
				mSubsystem?.AudioSystem?.DestroySource(instance.Source);
				instance.Source = null;
			}
			instance.ClipRef.Dispose();
			instance.Active = false;
		}
		mSourceInstances.Clear();
		mFreeSourceSlots.Clear();
		mEntityToSource.Clear();

		mListenerInstances.Clear();
		mFreeListenerSlots.Clear();
		mEntityToListener.Clear();

		mScene = null;
	}

	public override void Update(Scene scene, float deltaTime)
	{
		if (mSubsystem?.AudioSystem == null)
			return;

		UpdateListener(scene);

		for (var instance in ref mSourceInstances)
		{
			if (!instance.Active || instance.Source == null)
				continue;

			instance.Source.Volume = instance.Volume * mSubsystem.EffectiveSFXVolume;
			instance.Source.Pitch = instance.Pitch;

			if (instance.Spatial)
			{
				let transform = scene.GetTransform(instance.Entity);
				instance.Source.Position = transform.Position;
				instance.Source.MinDistance = instance.MinDistance;
				instance.Source.MaxDistance = instance.MaxDistance;
			}
		}
	}

	public override void OnEntityDestroyed(Scene scene, EntityId entity)
	{
		DestroySource(entity);
		DestroyListener(entity);
	}

	// ==================== Source API ====================

	/// Creates an audio source for an entity with default settings.
	public void CreateSource(EntityId entity)
	{
		if (mEntityToSource.ContainsKey(entity))
			return;

		let slot = AllocSourceSlot();
		mSourceInstances[slot] = .() {
			Entity = entity,
			Source = null,
			Clip = null,
			ClipRef = .(),
			Volume = 1.0f,
			Pitch = 1.0f,
			Spatial = true,
			Loop = false,
			AutoPlay = false,
			MinDistance = 1.0f,
			MaxDistance = 100.0f,
			Active = true
		};
		mEntityToSource[entity] = slot;

		// Ensure entity has the thin handle component
		var comp = mScene.GetComponent<AudioSourceComponent>(entity);
		if (comp == null)
		{
			mScene.SetComponent<AudioSourceComponent>(entity, .());
			comp = mScene.GetComponent<AudioSourceComponent>(entity);
		}
		comp.InternalHandle = slot;
	}

	/// Creates an audio source from deserialized data.
	public void CreateSourceFromData(EntityId entity, AudioSourceComponentData data)
	{
		if (mEntityToSource.ContainsKey(entity))
			return;

		let slot = AllocSourceSlot();
		var clipRef = ResourceRef();
		if (data.ClipRef.IsValid)
			clipRef = ResourceRef(data.ClipRef.Id, data.ClipRef.Path);

		mSourceInstances[slot] = .() {
			Entity = entity,
			Source = null,
			Clip = null,
			ClipRef = clipRef,
			Volume = data.Volume,
			Pitch = data.Pitch,
			Spatial = data.Spatial,
			Loop = data.Loop,
			AutoPlay = data.AutoPlay,
			MinDistance = data.MinDistance,
			MaxDistance = data.MaxDistance,
			Active = true
		};
		mEntityToSource[entity] = slot;

		// Ensure entity has the thin handle component
		var comp = mScene.GetComponent<AudioSourceComponent>(entity);
		if (comp == null)
		{
			mScene.SetComponent<AudioSourceComponent>(entity, .());
			comp = mScene.GetComponent<AudioSourceComponent>(entity);
		}
		comp.InternalHandle = slot;
	}

	/// Destroys an audio source for an entity.
	public void DestroySource(EntityId entity)
	{
		if (!mEntityToSource.TryGetValue(entity, var slot))
			return;

		var instance = ref mSourceInstances[slot];
		if (instance.Source != null)
		{
			instance.Source.Stop();
			mSubsystem?.AudioSystem?.DestroySource(instance.Source);
			instance.Source = null;
		}
		instance.ClipRef.Dispose();
		instance.Active = false;
		mFreeSourceSlots.Add(slot);
		mEntityToSource.Remove(entity);

		if (var comp = mScene?.GetComponent<AudioSourceComponent>(entity))
			comp.InternalHandle = -1;
	}

	/// Plays a sound on an entity. Creates internal source if needed.
	public void Play(EntityId entity, AudioClip clip, float volume = 1.0f, bool loop = false, bool spatial = true)
	{
		if (mScene == null || mSubsystem?.AudioSystem == null)
			return;

		// Ensure source instance exists
		if (!mEntityToSource.ContainsKey(entity))
			CreateSource(entity);

		if (!mEntityToSource.TryGetValue(entity, var slot))
			return;

		var instance = ref mSourceInstances[slot];

		// Stop and destroy existing audio source
		if (instance.Source != null)
		{
			instance.Source.Stop();
			mSubsystem.AudioSystem.DestroySource(instance.Source);
		}

		// Create new audio source
		let source = mSubsystem.AudioSystem.CreateSource();
		instance.Source = source;
		instance.Clip = clip;
		instance.Volume = volume;
		instance.Spatial = spatial;
		instance.Loop = loop;

		source.Volume = volume * mSubsystem.EffectiveSFXVolume;
		source.Loop = loop;
		source.Pitch = instance.Pitch;
		source.MinDistance = instance.MinDistance;
		source.MaxDistance = instance.MaxDistance;

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
		if (!mEntityToSource.TryGetValue(entity, var slot))
			return;
		var instance = ref mSourceInstances[slot];
		if (instance.Source != null)
			instance.Source.Stop();
	}

	/// Pauses the sound on an entity.
	public void Pause(EntityId entity)
	{
		if (!mEntityToSource.TryGetValue(entity, var slot))
			return;
		var instance = ref mSourceInstances[slot];
		if (instance.Source != null)
			instance.Source.Pause();
	}

	/// Resumes the sound on an entity.
	public void Resume(EntityId entity)
	{
		if (!mEntityToSource.TryGetValue(entity, var slot))
			return;
		var instance = ref mSourceInstances[slot];
		if (instance.Source != null)
			instance.Source.Resume();
	}

	/// Sets the volume for an entity's audio source.
	public void SetVolume(EntityId entity, float volume)
	{
		if (!mEntityToSource.TryGetValue(entity, var slot))
			return;
		mSourceInstances[slot].Volume = volume;
	}

	/// Sets the pitch for an entity's audio source.
	public void SetPitch(EntityId entity, float pitch)
	{
		if (!mEntityToSource.TryGetValue(entity, var slot))
			return;
		mSourceInstances[slot].Pitch = pitch;
	}

	/// Sets whether the audio source is spatial.
	public void SetSpatial(EntityId entity, bool spatial)
	{
		if (!mEntityToSource.TryGetValue(entity, var slot))
			return;
		mSourceInstances[slot].Spatial = spatial;
	}

	/// Sets whether the audio source loops.
	public void SetLoop(EntityId entity, bool loop)
	{
		if (!mEntityToSource.TryGetValue(entity, var slot))
			return;
		var instance = ref mSourceInstances[slot];
		instance.Loop = loop;
		if (instance.Source != null)
			instance.Source.Loop = loop;
	}

	/// Sets the minimum distance for spatial audio.
	public void SetMinDistance(EntityId entity, float minDistance)
	{
		if (!mEntityToSource.TryGetValue(entity, var slot))
			return;
		mSourceInstances[slot].MinDistance = minDistance;
	}

	/// Sets the maximum distance for spatial audio.
	public void SetMaxDistance(EntityId entity, float maxDistance)
	{
		if (!mEntityToSource.TryGetValue(entity, var slot))
			return;
		mSourceInstances[slot].MaxDistance = maxDistance;
	}

	/// Returns whether the entity has an audio source.
	public bool HasSource(EntityId entity)
	{
		return mEntityToSource.ContainsKey(entity);
	}

	// ==================== Listener API ====================

	/// Creates an audio listener for an entity.
	public void CreateListener(EntityId entity, bool active = true)
	{
		if (mEntityToListener.ContainsKey(entity))
			return;

		let slot = AllocListenerSlot();
		mListenerInstances[slot] = .() {
			Entity = entity,
			ListenerActive = active,
			Active = true
		};
		mEntityToListener[entity] = slot;

		// Ensure entity has the thin handle component
		var comp = mScene.GetComponent<AudioListenerComponent>(entity);
		if (comp == null)
		{
			mScene.SetComponent<AudioListenerComponent>(entity, .());
			comp = mScene.GetComponent<AudioListenerComponent>(entity);
		}
		comp.InternalHandle = slot;
	}

	/// Creates an audio listener from deserialized data.
	public void CreateListenerFromData(EntityId entity, AudioListenerComponentData data)
	{
		if (mEntityToListener.ContainsKey(entity))
			return;

		let slot = AllocListenerSlot();
		mListenerInstances[slot] = .() {
			Entity = entity,
			ListenerActive = data.Active,
			Active = true
		};
		mEntityToListener[entity] = slot;

		// Ensure entity has the thin handle component
		var comp = mScene.GetComponent<AudioListenerComponent>(entity);
		if (comp == null)
		{
			mScene.SetComponent<AudioListenerComponent>(entity, .());
			comp = mScene.GetComponent<AudioListenerComponent>(entity);
		}
		comp.InternalHandle = slot;
	}

	/// Destroys an audio listener for an entity.
	public void DestroyListener(EntityId entity)
	{
		if (!mEntityToListener.TryGetValue(entity, var slot))
			return;

		mListenerInstances[slot].Active = false;
		mFreeListenerSlots.Add(slot);
		mEntityToListener.Remove(entity);

		if (var comp = mScene?.GetComponent<AudioListenerComponent>(entity))
			comp.InternalHandle = -1;
	}

	/// Sets whether the listener is active.
	public void SetListenerActive(EntityId entity, bool active)
	{
		if (!mEntityToListener.TryGetValue(entity, var slot))
			return;
		mListenerInstances[slot].ListenerActive = active;
	}

	/// Returns whether the entity has an audio listener.
	public bool HasListener(EntityId entity)
	{
		return mEntityToListener.ContainsKey(entity);
	}

	/// Duplicates the audio source from src entity to dst entity.
	public void DuplicateSource(EntityId src, EntityId dst)
	{
		if (!mEntityToSource.TryGetValue(src, var srcSlot))
			return;

		let srcInstance = ref mSourceInstances[srcSlot];
		if (!srcInstance.Active)
			return;

		var data = AudioSourceComponentData();
		if (srcInstance.ClipRef.IsValid)
			data.ClipRef = ResourceRef(srcInstance.ClipRef.Id, srcInstance.ClipRef.Path);
		data.Volume = srcInstance.Volume;
		data.Pitch = srcInstance.Pitch;
		data.Spatial = srcInstance.Spatial;
		data.Loop = srcInstance.Loop;
		data.AutoPlay = srcInstance.AutoPlay;
		data.MinDistance = srcInstance.MinDistance;
		data.MaxDistance = srcInstance.MaxDistance;

		CreateSourceFromData(dst, data);
		data.Dispose();
	}

	/// Duplicates the audio listener from src entity to dst entity.
	public void DuplicateListener(EntityId src, EntityId dst)
	{
		if (!mEntityToListener.TryGetValue(src, var srcSlot))
			return;

		let srcInstance = ref mListenerInstances[srcSlot];
		if (!srcInstance.Active)
			return;

		CreateListener(dst, srcInstance.ListenerActive);
	}

	/// Gets the source instance data pointer for an entity (for editor property access).
	public AudioSourceInstanceData* GetSourceData(EntityId entity)
	{
		if (!mEntityToSource.TryGetValue(entity, var slot))
			return null;
		if (!mSourceInstances[slot].Active)
			return null;
		return &mSourceInstances[slot];
	}

	// ==================== Private ====================

	private int32 AllocSourceSlot()
	{
		if (mFreeSourceSlots.Count > 0)
		{
			let slot = mFreeSourceSlots.PopBack();
			return slot;
		}
		let slot = (int32)mSourceInstances.Count;
		mSourceInstances.Add(.());
		return slot;
	}

	private int32 AllocListenerSlot()
	{
		if (mFreeListenerSlots.Count > 0)
		{
			let slot = mFreeListenerSlots.PopBack();
			return slot;
		}
		let slot = (int32)mListenerInstances.Count;
		mListenerInstances.Add(.());
		return slot;
	}

	private void UpdateListener(Scene scene)
	{
		let listener = mSubsystem.AudioSystem.Listener;
		if (listener == null)
			return;

		for (let instance in ref mListenerInstances)
		{
			if (!instance.Active || !instance.ListenerActive)
				continue;

			let transform = scene.GetTransform(instance.Entity);
			listener.Position = transform.Position;

			let forward = Vector3.Transform(Vector3.Forward, transform.Rotation);
			let up = Vector3.Transform(Vector3.Up, transform.Rotation);
			listener.Forward = forward;
			listener.Up = up;
			break;
		}
	}
}
