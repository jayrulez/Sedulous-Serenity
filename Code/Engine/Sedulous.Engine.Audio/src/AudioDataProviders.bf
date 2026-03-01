namespace Sedulous.Engine.Audio;

using System;
using System.Collections;
using Sedulous.Engine.Scenes;
using Sedulous.Resources;

// ==================== Provider Initialization ====================

extension AudioSceneModule
{
	private List<IComponentDataProvider> mDataProviders ~ DeleteContainerAndItems!(_);

	public override void GetDataProviders(List<IComponentDataProvider> outProviders)
	{
		if (mDataProviders == null)
		{
			mDataProviders = new .();
			mDataProviders.Add(new AudioSourceDataProvider(this));
			mDataProviders.Add(new AudioListenerDataProvider(this));
		}
		outProviders.AddRange(mDataProviders);
	}

	// Fill/Apply for listener (source already has GetSourceData public)

	public bool FillListenerComponentData(EntityId entity, AudioListenerComponentData* data)
	{
		if (!mEntityToListener.TryGetValue(entity, let slot)) return false;
		let instance = ref mListenerInstances[slot];
		if (!instance.Active) return false;
		data.Active = instance.ListenerActive;
		return true;
	}

	public void ApplyListenerComponentData(EntityId entity, AudioListenerComponentData* data)
	{
		if (!mEntityToListener.TryGetValue(entity, let slot)) return;
		var instance = ref mListenerInstances[slot];
		if (!instance.Active) return;
		instance.ListenerActive = data.Active;
	}
}

// ==================== Audio Source Data Provider ====================

class AudioSourceDataProvider : IComponentDataProvider
{
	private AudioSceneModule mModule;
	public this(AudioSceneModule module) { mModule = module; }

	public void GetDisplayName(String outName) { outName.Append("Audio Source"); }
	public Type ComponentType => typeof(AudioSourceComponent);
	public Type DataType => typeof(AudioSourceComponentData);
	public bool HasComponent(EntityId entity) => mModule.HasSource(entity);

	public bool GetComponentData(EntityId entity, void* outData)
	{
		let instance = mModule.GetSourceData(entity);
		if (instance == null) return false;
		var data = (AudioSourceComponentData*)outData;
		data.ClipRef = instance.ClipRef; // shallow — caller must not free
		data.Volume = instance.Volume;
		data.Pitch = instance.Pitch;
		data.Spatial = instance.Spatial;
		data.Loop = instance.Loop;
		data.AutoPlay = instance.AutoPlay;
		data.MinDistance = instance.MinDistance;
		data.MaxDistance = instance.MaxDistance;
		return true;
	}

	public void SetComponentData(EntityId entity, void* inData)
	{
		let data = (AudioSourceComponentData*)inData;
		mModule.SetVolume(entity, data.Volume);
		mModule.SetPitch(entity, data.Pitch);
		mModule.SetSpatial(entity, data.Spatial);
		mModule.SetLoop(entity, data.Loop);
		mModule.SetMinDistance(entity, data.MinDistance);
		mModule.SetMaxDistance(entity, data.MaxDistance);
	}

	public bool CreateDefault(EntityId entity) { mModule.CreateSource(entity); return true; }
	public void Destroy(EntityId entity) { mModule.DestroySource(entity); }
}

// ==================== Audio Listener Data Provider ====================

class AudioListenerDataProvider : IComponentDataProvider
{
	private AudioSceneModule mModule;
	public this(AudioSceneModule module) { mModule = module; }

	public void GetDisplayName(String outName) { outName.Append("Audio Listener"); }
	public Type ComponentType => typeof(AudioListenerComponent);
	public Type DataType => typeof(AudioListenerComponentData);
	public bool HasComponent(EntityId entity) => mModule.HasListener(entity);

	public bool GetComponentData(EntityId entity, void* outData)
	{
		return mModule.FillListenerComponentData(entity, (AudioListenerComponentData*)outData);
	}

	public void SetComponentData(EntityId entity, void* inData)
	{
		mModule.ApplyListenerComponentData(entity, (AudioListenerComponentData*)inData);
	}

	public bool CreateDefault(EntityId entity) { mModule.CreateListener(entity); return true; }
	public void Destroy(EntityId entity) { mModule.DestroyListener(entity); }
}
