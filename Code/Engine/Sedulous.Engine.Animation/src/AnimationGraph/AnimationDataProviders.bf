namespace Sedulous.Engine.Animation;

using System;
using System.Collections;
using Sedulous.Engine.Scenes;
using Sedulous.Resources;

extension AnimationSceneModule
{
	private List<IComponentDataProvider> mDataProviders ~ DeleteContainerAndItems!(_);

	public override void GetDataProviders(List<IComponentDataProvider> outProviders)
	{
		if (mDataProviders == null)
		{
			mDataProviders = new .();
			mDataProviders.Add(new SkeletalAnimationDataProvider(this));
			mDataProviders.Add(new AnimationGraphDataProvider(this));
			mDataProviders.Add(new PropertyAnimationDataProvider(this));
		}
		outProviders.AddRange(mDataProviders);
	}

	// ==================== Fill/Apply ====================

	public bool HasSkeletalAnimation(EntityId entity) => mEntityToSkeletalAnim.ContainsKey(entity);
	public bool HasAnimationGraph(EntityId entity) => mEntityToGraphAnim.ContainsKey(entity);
	public bool HasPropertyAnimation(EntityId entity) => mEntityToPropertyAnim.ContainsKey(entity);

	public bool FillSkeletalAnimComponentData(EntityId entity, SkeletalAnimationComponentData* data)
	{
		if (!mEntityToSkeletalAnim.TryGetValue(entity, let idx)) return false;
		let instance = ref mSkeletalAnimInstances[idx];
		if (!instance.Active) return false;
		data.SkeletonRef = instance.SkeletonRef; // shallow
		data.AnimationClipRef = instance.AnimationClipRef; // shallow
		data.Playing = instance.Playing;
		data.Loop = instance.Loop;
		return true;
	}

	public void ApplySkeletalAnimComponentData(EntityId entity, SkeletalAnimationComponentData* data)
	{
		if (!mEntityToSkeletalAnim.TryGetValue(entity, let idx)) return;
		var instance = ref mSkeletalAnimInstances[idx];
		if (!instance.Active) return;
		// Deep-copy new strings BEFORE disposing old (data may alias instance)
		let newSkelPath = (data.SkeletonRef.Path != null) ? new String(data.SkeletonRef.Path) : null;
		let newClipPath = (data.AnimationClipRef.Path != null) ? new String(data.AnimationClipRef.Path) : null;
		instance.SkeletonRef.Dispose();
		instance.SkeletonRef.Id = data.SkeletonRef.Id;
		instance.SkeletonRef.Path = newSkelPath;
		instance.AnimationClipRef.Dispose();
		instance.AnimationClipRef.Id = data.AnimationClipRef.Id;
		instance.AnimationClipRef.Path = newClipPath;
		instance.Playing = data.Playing;
		instance.Loop = data.Loop;
	}

	public bool FillGraphAnimComponentData(EntityId entity, AnimationGraphComponentData* data)
	{
		if (!mEntityToGraphAnim.TryGetValue(entity, let idx)) return false;
		let instance = ref mGraphAnimInstances[idx];
		if (!instance.Active) return false;
		data.SkeletonRef = instance.SkeletonRef; // shallow
		data.Active = instance.GraphActive;
		return true;
	}

	public void ApplyGraphAnimComponentData(EntityId entity, AnimationGraphComponentData* data)
	{
		if (!mEntityToGraphAnim.TryGetValue(entity, let idx)) return;
		var instance = ref mGraphAnimInstances[idx];
		if (!instance.Active) return;
		let newSkelPath = (data.SkeletonRef.Path != null) ? new String(data.SkeletonRef.Path) : null;
		instance.SkeletonRef.Dispose();
		instance.SkeletonRef.Id = data.SkeletonRef.Id;
		instance.SkeletonRef.Path = newSkelPath;
		instance.GraphActive = data.Active;
	}

	public bool FillPropertyAnimComponentData(EntityId entity, PropertyAnimationComponentData* data)
	{
		if (!mEntityToPropertyAnim.TryGetValue(entity, let idx)) return false;
		let instance = ref mPropertyAnimInstances[idx];
		if (!instance.Active) return false;
		data.ClipRef = instance.ClipRef; // shallow
		data.Playing = instance.Playing;
		data.Speed = instance.Speed;
		return true;
	}

	public void ApplyPropertyAnimComponentData(EntityId entity, PropertyAnimationComponentData* data)
	{
		if (!mEntityToPropertyAnim.TryGetValue(entity, let idx)) return;
		var instance = ref mPropertyAnimInstances[idx];
		if (!instance.Active) return;
		let newClipPath = (data.ClipRef.Path != null) ? new String(data.ClipRef.Path) : null;
		instance.ClipRef.Dispose();
		instance.ClipRef.Id = data.ClipRef.Id;
		instance.ClipRef.Path = newClipPath;
		instance.ClipRes.Release();
		instance.Playing = data.Playing;
		instance.Speed = data.Speed;
	}
}

// ==================== Skeletal Animation Data Provider ====================

class SkeletalAnimationDataProvider : IComponentDataProvider
{
	private AnimationSceneModule mModule;
	public this(AnimationSceneModule module) { mModule = module; }

	public void GetDisplayName(String outName) { outName.Append("Skeletal Animation"); }
	public Type ComponentType => typeof(SkeletalAnimationComponent);
	public Type DataType => typeof(SkeletalAnimationComponentData);
	public bool HasComponent(EntityId entity) => mModule.HasSkeletalAnimation(entity);

	public bool GetComponentData(EntityId entity, void* outData)
	{
		return mModule.FillSkeletalAnimComponentData(entity, (SkeletalAnimationComponentData*)outData);
	}

	public void SetComponentData(EntityId entity, void* inData)
	{
		mModule.ApplySkeletalAnimComponentData(entity, (SkeletalAnimationComponentData*)inData);
	}

	public bool CreateDefault(EntityId entity) { mModule.CreateSkeletalAnimation(entity, .(), .()); return true; }
	public void Destroy(EntityId entity) { mModule.DestroySkeletalAnimation(entity); }
}

// ==================== Animation Graph Data Provider ====================

class AnimationGraphDataProvider : IComponentDataProvider
{
	private AnimationSceneModule mModule;
	public this(AnimationSceneModule module) { mModule = module; }

	public void GetDisplayName(String outName) { outName.Append("Animation Graph"); }
	public Type ComponentType => typeof(AnimationGraphComponent);
	public Type DataType => typeof(AnimationGraphComponentData);
	public bool HasComponent(EntityId entity) => mModule.HasAnimationGraph(entity);

	public bool GetComponentData(EntityId entity, void* outData)
	{
		return mModule.FillGraphAnimComponentData(entity, (AnimationGraphComponentData*)outData);
	}

	public void SetComponentData(EntityId entity, void* inData)
	{
		mModule.ApplyGraphAnimComponentData(entity, (AnimationGraphComponentData*)inData);
	}

	public bool CreateDefault(EntityId entity) { mModule.CreateGraphAnimationFromRef(entity, .(), true); return true; }
	public void Destroy(EntityId entity) { mModule.DestroyGraphAnimation(entity); }
}

// ==================== Property Animation Data Provider ====================

class PropertyAnimationDataProvider : IComponentDataProvider
{
	private AnimationSceneModule mModule;
	public this(AnimationSceneModule module) { mModule = module; }

	public void GetDisplayName(String outName) { outName.Append("Property Animation"); }
	public Type ComponentType => typeof(PropertyAnimationComponent);
	public Type DataType => typeof(PropertyAnimationComponentData);
	public bool HasComponent(EntityId entity) => mModule.HasPropertyAnimation(entity);

	public bool GetComponentData(EntityId entity, void* outData)
	{
		return mModule.FillPropertyAnimComponentData(entity, (PropertyAnimationComponentData*)outData);
	}

	public void SetComponentData(EntityId entity, void* inData)
	{
		mModule.ApplyPropertyAnimComponentData(entity, (PropertyAnimationComponentData*)inData);
	}

	public bool CreateDefault(EntityId entity) { mModule.CreatePropertyAnimationFromRef(entity, .()); return true; }
	public void Destroy(EntityId entity) { mModule.DestroyPropertyAnimation(entity); }
}
