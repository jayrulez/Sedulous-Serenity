namespace Sedulous.Engine.Audio;

using System;
using Sedulous.Engine.Core;
using Sedulous.Serialization;

/// Entity component that marks an entity as the audio listener.
/// Only one active listener should exist per scene.
/// If no AudioListenerComponent exists, the main camera is used as the listener.
/// Typically attached to the player entity or camera.
class AudioListenerComponent : IEntityComponent
{
	private Entity mEntity;
	private AudioSceneComponent mAudioScene;
	private bool mIsActive = true;

	// ==================== Properties ====================

	/// Gets the entity this component is attached to.
	public Entity Entity => mEntity;

	/// Gets or sets whether this listener is active.
	/// Only one listener should be active per scene.
	public bool IsActive
	{
		get => mIsActive;
		set
		{
			mIsActive = value;
			UpdateListenerRegistration();
		}
	}

	// ==================== IEntityComponent Implementation ====================

	/// Called when the component is attached to an entity.
	public void OnAttach(Entity entity)
	{
		mEntity = entity;

		// Get the AudioSceneComponent from the scene
		mAudioScene = entity.Scene?.GetSceneComponent<AudioSceneComponent>();
		if (mAudioScene == null)
			return;

		// Register as listener if active
		if (mIsActive)
			mAudioScene.SetListenerEntity(entity);
	}

	/// Called when the component is detached from an entity.
	public void OnDetach()
	{
		// Unregister as listener
		if (mAudioScene != null && mIsActive)
		{
			if (mAudioScene.ListenerEntity == mEntity)
				mAudioScene.ClearListenerEntity();
		}

		mAudioScene = null;
		mEntity = null;
	}

	/// Called each frame to update the component.
	/// Listener position sync is handled by AudioSceneComponent.
	public void OnUpdate(float deltaTime)
	{
		// Position syncing is done by AudioSceneComponent.SyncListener()
	}

	// ==================== ISerializable Implementation ====================

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer serializer)
	{
		var version = SerializationVersion;
		var result = serializer.Version(ref version);
		if (result != .Ok)
			return result;

		result = serializer.Bool("isActive", ref mIsActive);
		if (result != .Ok)
			return result;

		return .Ok;
	}

	// ==================== Private Methods ====================

	private void UpdateListenerRegistration()
	{
		if (mAudioScene == null || mEntity == null)
			return;

		if (mIsActive)
		{
			mAudioScene.SetListenerEntity(mEntity);
		}
		else
		{
			if (mAudioScene.ListenerEntity == mEntity)
				mAudioScene.ClearListenerEntity();
		}
	}
}
