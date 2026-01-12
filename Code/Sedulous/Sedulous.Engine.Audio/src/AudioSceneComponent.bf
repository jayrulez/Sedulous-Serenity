namespace Sedulous.Engine.Audio;

using System;
using System.Collections;
using Sedulous.Audio;
using Sedulous.Engine.Core;
using Sedulous.Engine.Renderer;
using Sedulous.Mathematics;
using Sedulous.Serialization;

/// Scene component that manages audio sources and listener for a scene.
/// Automatically syncs entity positions with audio sources.
/// If no AudioListenerComponent exists, syncs listener with main camera.
class AudioSceneComponent : ISceneComponent
{
	private AudioService mAudioService;
	private Scene mScene;

	// Entity → IAudioSource mappings
	private Dictionary<EntityId, IAudioSource> mEntitySources = new .() ~ delete _;

	// Active listener entity (if explicit AudioListenerComponent exists)
	private Entity mListenerEntity;

	// ==================== Properties ====================

	/// Gets the audio service.
	public AudioService AudioService => mAudioService;

	/// Gets the scene this component is attached to.
	public Scene Scene => mScene;

	/// Gets the listener entity (null if using camera fallback).
	public Entity ListenerEntity => mListenerEntity;

	/// Gets the number of audio sources in this scene.
	public int SourceCount => mEntitySources.Count;

	// ==================== Constructor ====================

	/// Creates a new AudioSceneComponent.
	public this(AudioService audioService)
	{
		mAudioService = audioService;
	}

	// ==================== ISceneComponent Implementation ====================

	/// Called when the component is attached to a scene.
	public void OnAttach(Scene scene)
	{
		mScene = scene;
	}

	/// Called when the component is detached from a scene.
	public void OnDetach()
	{
		// Destroy all audio sources
		for (let (entityId, source) in mEntitySources)
			mAudioService?.AudioSystem?.DestroySource(source);
		mEntitySources.Clear();

		mListenerEntity = null;
		mScene = null;
	}

	/// Called each frame to update the component.
	/// Syncs entity positions to audio sources and updates listener.
	public void OnUpdate(float deltaTime)
	{
		if (mScene == null || mAudioService?.AudioSystem == null)
			return;

		// Sync entity positions to audio sources
		SyncSources();

		// Sync listener position
		SyncListener();
	}

	/// Called when the scene state changes.
	public void OnSceneStateChanged(SceneState oldState, SceneState newState)
	{
		if (newState == .Unloaded)
		{
			// Stop all sources in this scene
			for (let (entityId, source) in mEntitySources)
			{
				source.Stop();
				mAudioService?.AudioSystem?.DestroySource(source);
			}
			mEntitySources.Clear();
			mListenerEntity = null;
		}
	}

	// ==================== ISerializable Implementation ====================

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer serializer)
	{
		var version = SerializationVersion;
		var result = serializer.Version(ref version);
		if (result != .Ok)
			return result;

		// AudioSceneComponent doesn't serialize its sources - they're recreated
		// from entity components when the scene loads
		return .Ok;
	}

	// ==================== Source Management ====================

	/// Creates an audio source for an entity.
	/// Returns the source, or null if failed.
	public IAudioSource CreateSource(Entity entity)
	{
		if (entity == null || mAudioService?.AudioSystem == null)
			return null;

		// Remove existing source if any
		DestroySource(entity);

		// Create new source
		let source = mAudioService.AudioSystem.CreateSource();
		if (source == null)
			return null;

		// Initialize with entity position
		source.Position = entity.Transform.WorldPosition;

		mEntitySources[entity.Id] = source;
		return source;
	}

	/// Destroys the audio source for an entity.
	public void DestroySource(Entity entity)
	{
		if (entity == null)
			return;

		if (mEntitySources.TryGetValue(entity.Id, let source))
		{
			source.Stop();
			mAudioService?.AudioSystem?.DestroySource(source);
			mEntitySources.Remove(entity.Id);
		}
	}

	/// Gets the audio source for an entity.
	/// Returns null if not found.
	public IAudioSource GetSource(Entity entity)
	{
		if (entity == null)
			return null;

		if (mEntitySources.TryGetValue(entity.Id, let source))
			return source;
		return null;
	}

	/// Gets the audio source for an entity by ID.
	/// Returns null if not found.
	public IAudioSource GetSource(EntityId entityId)
	{
		if (mEntitySources.TryGetValue(entityId, let source))
			return source;
		return null;
	}

	// ==================== Listener Management ====================

	/// Sets the listener entity (overrides camera fallback).
	public void SetListenerEntity(Entity entity)
	{
		mListenerEntity = entity;
	}

	/// Clears the listener entity (reverts to camera fallback).
	public void ClearListenerEntity()
	{
		mListenerEntity = null;
	}

	// ==================== Private Methods ====================

	/// Syncs all entity positions to their audio sources.
	private void SyncSources()
	{
		for (let (entityId, source) in mEntitySources)
		{
			if (let entity = mScene.GetEntity(entityId))
				source.Position = entity.Transform.WorldPosition;
		}
	}

	/// Syncs listener position with explicit entity or main camera fallback.
	private void SyncListener()
	{
		let listener = mAudioService?.AudioSystem?.Listener;
		if (listener == null)
			return;

		if (mListenerEntity != null)
		{
			// Use explicit listener entity
			listener.Position = mListenerEntity.Transform.WorldPosition;
			listener.Forward = mListenerEntity.Transform.Forward;
			listener.Up = mListenerEntity.Transform.Up;
		}
		else
		{
			// Fall back to main camera
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
	}
}
