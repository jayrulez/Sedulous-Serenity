namespace Sedulous.Engine.Render;

using System;
using System.Collections;
using Sedulous.Engine.Scenes;
using Sedulous.Core.Mathematics;
using Sedulous.Render;
using Sedulous.Resources;

// ==================== Provider Initialization ====================

extension RenderSceneModule
{
	private void InitDataProviders()
	{
		mDataProviders.Add(new LightDataProvider(this));
		mDataProviders.Add(new CameraDataProvider(this));
		mDataProviders.Add(new MeshDataProvider(this));
		mDataProviders.Add(new SkinnedMeshDataProvider(this));
		mDataProviders.Add(new SpriteDataProvider(this));
		mDataProviders.Add(new DecalDataProvider(this));
		mDataProviders.Add(new TrailEmitterDataProvider(this));
		mDataProviders.Add(new ParticleEmitterDataProvider(this));
	}

	// ==================== Fill/Apply for instance-based components ====================

	public bool FillMeshComponentData(EntityId entity, MeshComponentData* data)
	{
		if (!mEntityToMeshInstance.TryGetValue(entity, let idx)) return false;
		let instance = ref mMeshInstances[idx];
		if (!instance.Active) return false;
		// Shallow copy — caller must NOT free ResourceRef strings
		data.MeshRef = instance.MeshRef;
		data.MaterialRefs = instance.MaterialRefs;
		data.Enabled = instance.Enabled;
		return true;
	}

	public void ApplyMeshComponentData(EntityId entity, MeshComponentData* data)
	{
		if (!mEntityToMeshInstance.TryGetValue(entity, let idx)) return;
		var instance = ref mMeshInstances[idx];
		if (!instance.Active) return;
		// Deep-copy ResourceRefs (module owns the strings)
		// NOTE: data may contain shallow copies aliasing instance's strings,
		// so deep-copy new strings BEFORE disposing old ones.
		let newMeshPath = (data.MeshRef.Path != null) ? new String(data.MeshRef.Path) : null;
		instance.MeshRef.Dispose();
		instance.MeshRef.Id = data.MeshRef.Id;
		instance.MeshRef.Path = newMeshPath;

		int32 oldCount = instance.MaterialRefs.Count;
		for (int32 i = 0; i < data.MaterialRefs.Count; i++)
		{
			let src = ref data.MaterialRefs.Refs[i];
			let newPath = (src.Path != null) ? new String(src.Path) : null;
			if (i < oldCount)
				delete instance.MaterialRefs.Refs[i].Path;
			instance.MaterialRefs.Refs[i].Id = src.Id;
			instance.MaterialRefs.Refs[i].Path = newPath;
		}
		for (int32 i = data.MaterialRefs.Count; i < oldCount; i++)
			instance.MaterialRefs.Refs[i].Dispose();
		instance.MaterialRefs.Count = data.MaterialRefs.Count;

		instance.Enabled = data.Enabled;
	}

	public bool FillSkinnedMeshComponentData(EntityId entity, SkinnedMeshComponentData* data)
	{
		if (!mEntityToSkinnedMeshInstance.TryGetValue(entity, let idx)) return false;
		let instance = ref mSkinnedMeshInstances[idx];
		if (!instance.Active) return false;
		data.MeshRef = instance.MeshRef;
		data.MaterialRefs = instance.MaterialRefs;
		data.Enabled = instance.Enabled;
		return true;
	}

	public void ApplySkinnedMeshComponentData(EntityId entity, SkinnedMeshComponentData* data)
	{
		if (!mEntityToSkinnedMeshInstance.TryGetValue(entity, let idx)) return;
		var instance = ref mSkinnedMeshInstances[idx];
		if (!instance.Active) return;
		let newMeshPath = (data.MeshRef.Path != null) ? new String(data.MeshRef.Path) : null;
		instance.MeshRef.Dispose();
		instance.MeshRef.Id = data.MeshRef.Id;
		instance.MeshRef.Path = newMeshPath;

		int32 oldCount = instance.MaterialRefs.Count;
		for (int32 i = 0; i < data.MaterialRefs.Count; i++)
		{
			let src = ref data.MaterialRefs.Refs[i];
			let newPath = (src.Path != null) ? new String(src.Path) : null;
			if (i < oldCount)
				delete instance.MaterialRefs.Refs[i].Path;
			instance.MaterialRefs.Refs[i].Id = src.Id;
			instance.MaterialRefs.Refs[i].Path = newPath;
		}
		for (int32 i = data.MaterialRefs.Count; i < oldCount; i++)
			instance.MaterialRefs.Refs[i].Dispose();
		instance.MaterialRefs.Count = data.MaterialRefs.Count;

		instance.Enabled = data.Enabled;
	}

	public bool FillSpriteComponentData(EntityId entity, SpriteComponentData* data)
	{
		if (!mEntityToSpriteInstance.TryGetValue(entity, let idx)) return false;
		let instance = ref mSpriteInstances[idx];
		if (!instance.Active) return false;
		if (let proxy = mWorld?.GetSprite(instance.RenderHandle))
		{
			data.Size = proxy.Size;
			data.Color = proxy.Color.ToVector4();
			data.UVRect = proxy.UVRect;
			data.LayerMask = proxy.LayerMask;
			data.Enabled = proxy.IsActive;
		}
		data.TextureRef = instance.TextureRef; // shallow
		return true;
	}

	public void ApplySpriteComponentData(EntityId entity, SpriteComponentData* data)
	{
		if (!mEntityToSpriteInstance.TryGetValue(entity, let idx)) return;
		var instance = ref mSpriteInstances[idx];
		if (!instance.Active) return;
		if (let proxy = mWorld?.GetSprite(instance.RenderHandle))
		{
			proxy.Size = data.Size;
			proxy.Color = Color(data.Color);
			proxy.UVRect = data.UVRect;
			proxy.LayerMask = data.LayerMask;
			proxy.IsActive = data.Enabled;
		}
		let newTexPath = (data.TextureRef.Path != null) ? new String(data.TextureRef.Path) : null;
		instance.TextureRef.Dispose();
		instance.TextureRef.Id = data.TextureRef.Id;
		instance.TextureRef.Path = newTexPath;
	}

	public bool FillDecalComponentData(EntityId entity, DecalComponentData* data)
	{
		if (!mEntityToDecalInstance.TryGetValue(entity, let idx)) return false;
		let instance = ref mDecalInstances[idx];
		if (!instance.Active) return false;
		if (let proxy = mWorld?.GetDecal(instance.RenderHandle))
		{
			data.Scale = proxy.Scale;
			data.Color = proxy.Color;
			data.AngleFadeStart = proxy.AngleFadeStart;
			data.AngleFadeEnd = proxy.AngleFadeEnd;
			data.SortOrder = proxy.SortOrder;
			data.BlendMode = proxy.BlendMode;
			data.Enabled = proxy.IsActive;
		}
		data.TextureRef = instance.TextureRef; // shallow
		return true;
	}

	public void ApplyDecalComponentData(EntityId entity, DecalComponentData* data)
	{
		if (!mEntityToDecalInstance.TryGetValue(entity, let idx)) return;
		var instance = ref mDecalInstances[idx];
		if (!instance.Active) return;
		if (let proxy = mWorld?.GetDecal(instance.RenderHandle))
		{
			proxy.Scale = data.Scale;
			proxy.Color = data.Color;
			proxy.AngleFadeStart = data.AngleFadeStart;
			proxy.AngleFadeEnd = data.AngleFadeEnd;
			proxy.SortOrder = data.SortOrder;
			proxy.BlendMode = data.BlendMode;
			proxy.IsActive = data.Enabled;
		}
		let newTexPath = (data.TextureRef.Path != null) ? new String(data.TextureRef.Path) : null;
		instance.TextureRef.Dispose();
		instance.TextureRef.Id = data.TextureRef.Id;
		instance.TextureRef.Path = newTexPath;
	}
}

// ==================== Light Data Provider ====================

class LightDataProvider : IComponentDataProvider
{
	private RenderSceneModule mModule;
	public this(RenderSceneModule module) { mModule = module; }

	public void GetDisplayName(String outName) { outName.Append("Light"); }
	public Type ComponentType => typeof(LightComponent);
	public Type DataType => typeof(LightComponentData);
	public bool HasComponent(EntityId entity) => mModule.HasLight(entity);

	public bool GetComponentData(EntityId entity, void* outData)
	{
		if (let proxy = mModule.GetLightProxy(entity))
		{
			var data = (LightComponentData*)outData;
			data.Type = proxy.Type;
			data.Color = proxy.Color;
			data.Intensity = proxy.Intensity;
			data.Range = proxy.Range;
			data.InnerConeAngle = proxy.InnerConeAngle;
			data.OuterConeAngle = proxy.OuterConeAngle;
			data.CastsShadows = proxy.CastsShadows;
			data.ShadowBias = proxy.ShadowBias;
			data.ShadowNormalBias = proxy.ShadowNormalBias;
			data.LayerMask = proxy.LayerMask;
			data.Enabled = proxy.IsEnabled;
			return true;
		}
		return false;
	}

	public void SetComponentData(EntityId entity, void* inData)
	{
		if (let proxy = mModule.GetLightProxy(entity))
		{
			let data = (LightComponentData*)inData;
			proxy.Color = data.Color;
			proxy.Intensity = data.Intensity;
			proxy.Range = data.Range;
			proxy.InnerConeAngle = data.InnerConeAngle;
			proxy.OuterConeAngle = data.OuterConeAngle;
			proxy.CastsShadows = data.CastsShadows;
			proxy.ShadowBias = data.ShadowBias;
			proxy.ShadowNormalBias = data.ShadowNormalBias;
			proxy.LayerMask = data.LayerMask;
			proxy.IsEnabled = data.Enabled;
		}
	}

	public bool CreateDefault(EntityId entity) { mModule.CreatePointLight(entity, .(1, 1, 1), 1.0f, 10.0f); return true; }
	public void Destroy(EntityId entity) { mModule.DestroyLight(entity); }
}

// ==================== Camera Data Provider ====================

class CameraDataProvider : IComponentDataProvider
{
	private RenderSceneModule mModule;
	public this(RenderSceneModule module) { mModule = module; }

	public void GetDisplayName(String outName) { outName.Append("Camera"); }
	public Type ComponentType => typeof(CameraComponent);
	public Type DataType => typeof(CameraComponentData);
	public bool HasComponent(EntityId entity) => mModule.HasCamera(entity);

	public bool GetComponentData(EntityId entity, void* outData)
	{
		if (let proxy = mModule.GetCameraProxy(entity))
		{
			var data = (CameraComponentData*)outData;
			data.Projection = proxy.Projection;
			data.FieldOfView = proxy.FieldOfView;
			data.AspectRatio = proxy.AspectRatio;
			data.NearPlane = proxy.NearPlane;
			data.FarPlane = proxy.FarPlane;
			data.OrthoWidth = proxy.OrthoWidth;
			data.OrthoHeight = proxy.OrthoHeight;
			data.Priority = proxy.Priority;
			data.Active = true;
			data.IsMainCamera = proxy.IsMainCamera;
			return true;
		}
		return false;
	}

	public void SetComponentData(EntityId entity, void* inData)
	{
		if (let proxy = mModule.GetCameraProxy(entity))
		{
			let data = (CameraComponentData*)inData;
			proxy.FieldOfView = data.FieldOfView;
			proxy.AspectRatio = data.AspectRatio;
			proxy.NearPlane = data.NearPlane;
			proxy.FarPlane = data.FarPlane;
			proxy.OrthoWidth = data.OrthoWidth;
			proxy.OrthoHeight = data.OrthoHeight;
			proxy.Priority = data.Priority;
			proxy.UpdateMatrices();
			if (data.IsMainCamera)
				mModule.SetMainCamera(entity);
		}
	}

	public bool CreateDefault(EntityId entity) { mModule.CreatePerspectiveCamera(entity, Math.PI_f / 4.0f, 16.0f / 9.0f, 0.1f, 1000.0f); return true; }
	public void Destroy(EntityId entity) { mModule.DestroyCamera(entity); }
}

// ==================== Mesh Data Provider ====================

class MeshDataProvider : IComponentDataProvider
{
	private RenderSceneModule mModule;
	public this(RenderSceneModule module) { mModule = module; }

	public void GetDisplayName(String outName) { outName.Append("Mesh"); }
	public Type ComponentType => typeof(MeshComponent);
	public Type DataType => typeof(MeshComponentData);
	public bool HasComponent(EntityId entity) => mModule.HasMesh(entity);

	public bool GetComponentData(EntityId entity, void* outData)
	{
		return mModule.FillMeshComponentData(entity, (MeshComponentData*)outData);
	}

	public void SetComponentData(EntityId entity, void* inData)
	{
		mModule.ApplyMeshComponentData(entity, (MeshComponentData*)inData);
	}

	public bool CreateDefault(EntityId entity) { mModule.CreateMeshFromRef(entity, .()); return true; }
	public void Destroy(EntityId entity) { mModule.DestroyMesh(entity); }
}

// ==================== SkinnedMesh Data Provider ====================

class SkinnedMeshDataProvider : IComponentDataProvider
{
	private RenderSceneModule mModule;
	public this(RenderSceneModule module) { mModule = module; }

	public void GetDisplayName(String outName) { outName.Append("Skinned Mesh"); }
	public Type ComponentType => typeof(SkinnedMeshComponent);
	public Type DataType => typeof(SkinnedMeshComponentData);
	public bool HasComponent(EntityId entity) => mModule.HasSkinnedMesh(entity);

	public bool GetComponentData(EntityId entity, void* outData)
	{
		return mModule.FillSkinnedMeshComponentData(entity, (SkinnedMeshComponentData*)outData);
	}

	public void SetComponentData(EntityId entity, void* inData)
	{
		mModule.ApplySkinnedMeshComponentData(entity, (SkinnedMeshComponentData*)inData);
	}

	public bool CreateDefault(EntityId entity) { mModule.CreateSkinnedMeshFromRef(entity, .()); return true; }
	public void Destroy(EntityId entity) { mModule.DestroySkinnedMesh(entity); }
}

// ==================== Sprite Data Provider ====================

class SpriteDataProvider : IComponentDataProvider
{
	private RenderSceneModule mModule;
	public this(RenderSceneModule module) { mModule = module; }

	public void GetDisplayName(String outName) { outName.Append("Sprite"); }
	public Type ComponentType => typeof(SpriteComponent);
	public Type DataType => typeof(SpriteComponentData);
	public bool HasComponent(EntityId entity) => mModule.HasSprite(entity);

	public bool GetComponentData(EntityId entity, void* outData)
	{
		return mModule.FillSpriteComponentData(entity, (SpriteComponentData*)outData);
	}

	public void SetComponentData(EntityId entity, void* inData)
	{
		mModule.ApplySpriteComponentData(entity, (SpriteComponentData*)inData);
	}

	public bool CreateDefault(EntityId entity) { mModule.CreateSprite(entity); return true; }
	public void Destroy(EntityId entity) { mModule.DestroySprite(entity); }
}

// ==================== Decal Data Provider ====================

class DecalDataProvider : IComponentDataProvider
{
	private RenderSceneModule mModule;
	public this(RenderSceneModule module) { mModule = module; }

	public void GetDisplayName(String outName) { outName.Append("Decal"); }
	public Type ComponentType => typeof(DecalComponent);
	public Type DataType => typeof(DecalComponentData);
	public bool HasComponent(EntityId entity) => mModule.HasDecal(entity);

	public bool GetComponentData(EntityId entity, void* outData)
	{
		return mModule.FillDecalComponentData(entity, (DecalComponentData*)outData);
	}

	public void SetComponentData(EntityId entity, void* inData)
	{
		mModule.ApplyDecalComponentData(entity, (DecalComponentData*)inData);
	}

	public bool CreateDefault(EntityId entity) { mModule.CreateDecal(entity); return true; }
	public void Destroy(EntityId entity) { mModule.DestroyDecal(entity); }
}

// ==================== Trail Emitter Data Provider ====================

class TrailEmitterDataProvider : IComponentDataProvider
{
	private RenderSceneModule mModule;
	public this(RenderSceneModule module) { mModule = module; }

	public void GetDisplayName(String outName) { outName.Append("Trail Emitter"); }
	public Type ComponentType => typeof(TrailEmitterComponent);
	public Type DataType => typeof(TrailEmitterComponentData);
	public bool HasComponent(EntityId entity) => mModule.HasTrailEmitter(entity);

	public bool GetComponentData(EntityId entity, void* outData)
	{
		if (let proxy = mModule.GetTrailEmitterProxy(entity))
		{
			var data = (TrailEmitterComponentData*)outData;
			data.BlendMode = proxy.BlendMode;
			data.MaxPoints = proxy.MaxPoints;
			data.Lifetime = proxy.Lifetime;
			data.WidthStart = proxy.WidthStart;
			data.WidthEnd = proxy.WidthEnd;
			data.MinVertexDistance = proxy.MinVertexDistance;
			data.Color = proxy.Color;
			data.SoftParticleDistance = proxy.SoftParticleDistance;
			data.LayerMask = proxy.LayerMask;
			data.Enabled = proxy.IsEnabled;
			return true;
		}
		return false;
	}

	public void SetComponentData(EntityId entity, void* inData)
	{
		if (let proxy = mModule.GetTrailEmitterProxy(entity))
		{
			let data = (TrailEmitterComponentData*)inData;
			proxy.BlendMode = data.BlendMode;
			proxy.MaxPoints = data.MaxPoints;
			proxy.Lifetime = data.Lifetime;
			proxy.WidthStart = data.WidthStart;
			proxy.WidthEnd = data.WidthEnd;
			proxy.MinVertexDistance = data.MinVertexDistance;
			proxy.Color = data.Color;
			proxy.SoftParticleDistance = data.SoftParticleDistance;
			proxy.LayerMask = data.LayerMask;
			proxy.IsEnabled = data.Enabled;
		}
	}

	public bool CreateDefault(EntityId entity) { mModule.CreateTrailEmitter(entity); return true; }
	public void Destroy(EntityId entity) { mModule.DestroyTrailEmitter(entity); }
}

// ==================== Particle Emitter Data Provider ====================

class ParticleEmitterDataProvider : IComponentDataProvider
{
	private RenderSceneModule mModule;
	public this(RenderSceneModule module) { mModule = module; }

	public void GetDisplayName(String outName) { outName.Append("Particle Emitter"); }
	public Type ComponentType => typeof(ParticleEmitterComponent);
	public Type DataType => typeof(ParticleEmitterComponentData);
	public bool HasComponent(EntityId entity) => mModule.HasParticleEmitter(entity);

	public bool GetComponentData(EntityId entity, void* outData)
	{
		if (let proxy = mModule.GetParticleEmitterProxy(entity))
		{
			var data = (ParticleEmitterComponentData*)outData;
			data.Backend = proxy.Backend;
			data.SimulationSpace = proxy.SimulationSpace;
			data.BlendMode = proxy.BlendMode;
			data.RenderMode = proxy.RenderMode;
			data.MaxParticles = proxy.MaxParticles;
			data.SpawnRate = proxy.SpawnRate;
			data.ParticleLifetime = proxy.ParticleLifetime;
			data.BurstCount = proxy.BurstCount;
			data.BurstInterval = proxy.BurstInterval;
			data.BurstCycles = proxy.BurstCycles;
			data.StartSize = proxy.StartSize;
			data.EndSize = proxy.EndSize;
			data.StartColor = proxy.StartColor;
			data.EndColor = proxy.EndColor;
			data.InitialVelocity = proxy.InitialVelocity;
			data.VelocityRandomness = proxy.VelocityRandomness;
			data.GravityMultiplier = proxy.GravityMultiplier;
			data.Drag = proxy.Drag;
			data.VelocityInheritance = proxy.VelocityInheritance;
			data.SoftParticleDistance = proxy.SoftParticleDistance;
			data.StretchFactor = proxy.StretchFactor;
			data.SortParticles = proxy.SortParticles;
			data.Lit = proxy.Lit;
			data.AtlasColumns = proxy.AtlasColumns;
			data.AtlasRows = proxy.AtlasRows;
			data.AtlasFPS = proxy.AtlasFPS;
			data.AtlasLoop = proxy.AtlasLoop;
			data.LODStartDistance = proxy.LODStartDistance;
			data.LODCullDistance = proxy.LODCullDistance;
			data.LODMinRateMultiplier = proxy.LODMinRateMultiplier;
			data.LifetimeVarianceMin = proxy.LifetimeVarianceMin;
			data.LifetimeVarianceMax = proxy.LifetimeVarianceMax;
			data.SubEmitterOnly = proxy.SubEmitterOnly;
			data.LayerMask = proxy.LayerMask;
			data.Enabled = proxy.IsEnabled;
			return true;
		}
		return false;
	}

	public void SetComponentData(EntityId entity, void* inData)
	{
		if (let proxy = mModule.GetParticleEmitterProxy(entity))
		{
			let data = (ParticleEmitterComponentData*)inData;
			proxy.SimulationSpace = data.SimulationSpace;
			proxy.BlendMode = data.BlendMode;
			proxy.RenderMode = data.RenderMode;
			proxy.MaxParticles = data.MaxParticles;
			proxy.SpawnRate = data.SpawnRate;
			proxy.ParticleLifetime = data.ParticleLifetime;
			proxy.BurstCount = data.BurstCount;
			proxy.BurstInterval = data.BurstInterval;
			proxy.BurstCycles = data.BurstCycles;
			proxy.StartSize = data.StartSize;
			proxy.EndSize = data.EndSize;
			proxy.StartColor = data.StartColor;
			proxy.EndColor = data.EndColor;
			proxy.InitialVelocity = data.InitialVelocity;
			proxy.VelocityRandomness = data.VelocityRandomness;
			proxy.GravityMultiplier = data.GravityMultiplier;
			proxy.Drag = data.Drag;
			proxy.VelocityInheritance = data.VelocityInheritance;
			proxy.SoftParticleDistance = data.SoftParticleDistance;
			proxy.StretchFactor = data.StretchFactor;
			proxy.SortParticles = data.SortParticles;
			proxy.Lit = data.Lit;
			proxy.AtlasColumns = data.AtlasColumns;
			proxy.AtlasRows = data.AtlasRows;
			proxy.AtlasFPS = data.AtlasFPS;
			proxy.AtlasLoop = data.AtlasLoop;
			proxy.LODStartDistance = data.LODStartDistance;
			proxy.LODCullDistance = data.LODCullDistance;
			proxy.LODMinRateMultiplier = data.LODMinRateMultiplier;
			proxy.LifetimeVarianceMin = data.LifetimeVarianceMin;
			proxy.LifetimeVarianceMax = data.LifetimeVarianceMax;
			proxy.SubEmitterOnly = data.SubEmitterOnly;
			proxy.LayerMask = data.LayerMask;
			proxy.IsEnabled = data.Enabled;
		}
	}

	public bool CreateDefault(EntityId entity) { mModule.CreateParticleEmitter(entity); return true; }
	public void Destroy(EntityId entity) { mModule.DestroyParticleEmitter(entity); }
}
