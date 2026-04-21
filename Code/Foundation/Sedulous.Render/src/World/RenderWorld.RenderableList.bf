namespace Sedulous.Render;

using System;
using Sedulous.Core.Mathematics;
using Sedulous.RHI;

/// RenderableList population — builds the pure-data renderable list from the
/// proxy pools that RenderWorld owns. This is the producer side of the seam
/// between RenderWorld (scene data) and the rest of Sedulous.Render (renderer).
extension RenderWorld
{
	/// Populates the given renderable list from all active proxy pools.
	/// Called by RenderSystem.BeginFrame each frame before the render graph is built.
	public void PopulateRenderables(RenderableList list)
	{
		list.Clear();

		// Stamp source ID so cached systems (skinning, reflection probes) can
		// distinguish renderables from different worlds and avoid handle collision.
		list.SourceId = (uint32)(int)Internal.UnsafeCastToPtr(this);

		PopulateEnvironment(list);
		PopulateMeshes(list);
		PopulateSkinnedMeshes(list);
		PopulateLights(list);
		PopulateSprites(list);
		PopulateDecals(list);
		PopulateCurveDecals(list);
		PopulateParticles(list);
		PopulateTrails(list);
		PopulateTerrains(list);
		PopulateGrassPatches(list);
		PopulateWaterSurfaces(list);
		PopulateReflectionProbes(list);
	}

	// ==================== Environment ====================

	private void PopulateEnvironment(RenderableList list)
	{
		list.Environment = .()
		{
			AmbientColor = AmbientColor,
			AmbientIntensity = AmbientIntensity,
			Exposure = Exposure,
			Tonemap = TonemapOperator,
			AA = AAMode,
			InstancingEnabled = InstancingEnabled,
			LODBias = LODBias
		};
	}

	// ==================== Meshes ====================

	private void PopulateMeshes(RenderableList list)
	{
		ForEachMesh(scope (handle, mesh) =>
		{
			if (!mesh.IsActive || !mesh.Flags.HasFlag(.Visible))
				return;

			if (!mesh.MeshHandle.IsValid)
				return;

			var renderable = MeshRenderable()
			{
				MeshHandle = mesh.MeshHandle,
				MaterialCount = mesh.MaterialCount,
				WorldMatrix = mesh.WorldMatrix,
				PrevWorldMatrix = mesh.PrevWorldMatrix,
				WorldBounds = mesh.WorldBounds,
				Flags = mesh.Flags,
				LayerMask = mesh.LayerMask,
				LODLevel = (int32)mesh.LODLevel,
				ObjectBindGroup = mesh.ObjectBindGroup,
				MeshRenderHandle = MeshRenderHandle() { Handle = handle }
			};

			// Copy per-submesh material slots so the forward pass can resolve materials
			// without reaching back to RenderWorld.
			for (int32 i = 0; i < mesh.MaterialCount; i++)
				renderable.Materials[i] = mesh.Materials[i];

			// Emit one entry per mesh. All meshes currently go to OpaqueMeshes; proper
			// transparency bucketing based on MaterialInstance blend mode will happen
			// in a follow-up when features need distinct transparent draws.
			list.OpaqueMeshes.Add(renderable);
		});
	}

	// ==================== Skinned Meshes ====================

	private void PopulateSkinnedMeshes(RenderableList list)
	{
		ForEachSkinnedMesh(scope (handle, mesh) =>
		{
			if (!mesh.IsActive || !mesh.Flags.HasFlag(.Visible))
				return;

			if (!mesh.MeshHandle.IsValid)
				return;

			var renderable = SkinnedMeshRenderable()
			{
				MeshHandle = mesh.MeshHandle,
				BoneBufferHandle = mesh.BoneBufferHandle,
				SkinnedMeshHandle = SkinnedMeshRenderHandle() { Handle = handle },
				MaterialCount = mesh.MaterialCount,
				WorldMatrix = mesh.WorldMatrix,
				PrevWorldMatrix = mesh.PrevWorldMatrix,
				WorldBounds = mesh.WorldBounds,
				Flags = mesh.Flags,
				LayerMask = mesh.LayerMask,
				BoneCount = mesh.BoneCount,
				LODLevel = (int32)mesh.LODLevel
			};

			for (int32 i = 0; i < mesh.MaterialCount; i++)
				renderable.Materials[i] = mesh.Materials[i];

			list.SkinnedMeshes.Add(renderable);
		});
	}

	// ==================== Lights ====================

	private void PopulateLights(RenderableList list)
	{
		ForEachLight(scope (handle, light) =>
		{
			if (!light.IsActive || !light.IsEnabled)
				return;

			list.Lights.Add(.()
			{
				Type = light.Type,
				Position = light.Position,
				Direction = light.Direction,
				Color = light.Color,
				Intensity = light.Intensity,
				Range = light.Range,
				InnerConeAngle = light.InnerConeAngle,
				OuterConeAngle = light.OuterConeAngle,
				CastsShadows = light.CastsShadows,
				ShadowIndex = light.ShadowIndex,
				ShadowBias = light.ShadowBias,
				ShadowNormalBias = light.ShadowNormalBias,
				LayerMask = light.LayerMask,
				LightHandle = LightRenderHandle() { Handle = handle }
			});
		});
	}

	// ==================== Sprites ====================

	private void PopulateSprites(RenderableList list)
	{
		ForEachSprite(scope (handle, sprite) =>
		{
			if (!sprite.IsActive)
				return;

			list.Sprites.Add(.()
			{
				Position = sprite.Position,
				Size = sprite.Size,
				Color = sprite.Color,
				Texture = sprite.Texture,
				UVRect = sprite.UVRect,
				LayerMask = sprite.LayerMask
			});
		});
	}

	// ==================== Decals ====================

	private void PopulateDecals(RenderableList list)
	{
		ForEachDecal(scope (handle, decal) =>
		{
			if (!decal.IsActive)
				return;

			list.Decals.Add(.()
			{
				WorldMatrix = decal.GetWorldMatrix(),
				InvWorldMatrix = decal.GetInvWorldMatrix(),
				Scale = decal.Scale,
				Color = decal.Color,
				AngleFadeStart = decal.AngleFadeStart,
				AngleFadeEnd = decal.AngleFadeEnd,
				SortOrder = decal.SortOrder,
				BlendMode = decal.BlendMode,
				AlbedoTexture = decal.AlbedoTexture,
				Sampler = decal.Sampler
			});
		});
	}

	// ==================== Curve Decals ====================

	private void PopulateCurveDecals(RenderableList list)
	{
		ForEachCurveDecal(scope (handle, curveDecal) =>
		{
			if (!curveDecal.IsActive)
				return;

			var renderable = CurveDecalRenderable();
			renderable.ControlPoints = curveDecal.ControlPoints;
			renderable.PointCount = curveDecal.PointCount;
			renderable.Color = curveDecal.Color;
			renderable.AlbedoTexture = curveDecal.AlbedoTexture;
			renderable.Sampler = curveDecal.Sampler;
			renderable.BlendMode = curveDecal.BlendMode;
			renderable.SortOrder = curveDecal.SortOrder;
			renderable.UVTilingU = curveDecal.UVTilingU;
			renderable.UVTilingV = curveDecal.UVTilingV;
			renderable.ProjectionDepth = curveDecal.ProjectionDepth;
			renderable.WorldBounds = curveDecal.WorldBounds;
			list.CurveDecals.Add(renderable);
		});
	}

	// ==================== Particles ====================

	private void PopulateParticles(RenderableList list)
	{
		ForEachParticleEmitter(scope (handle, emitter) =>
		{
			if (!emitter.IsActive || !emitter.IsEnabled || !emitter.IsEmitting)
				return;

			let renderHandle = ParticleEmitterRenderHandle() { Handle = handle };

			if (emitter.Backend == .GPU)
			{
				list.GPUParticles.Add(.()
				{
					EmitterHandle = renderHandle,
					ParticleBuffer = emitter.ParticleBuffer,
					IndirectBuffer = emitter.IndirectBuffer,
					ParticleTexture = emitter.ParticleTexture,
					BlendMode = emitter.BlendMode,
					RenderMode = emitter.RenderMode,
					SoftParticleDistance = emitter.SoftParticleDistance,
					StretchFactor = emitter.StretchFactor,
					AliveCount = emitter.AliveCount,
					LayerMask = emitter.LayerMask
				});
			}
			else // CPU
			{
				// CPU particle VertexBuffer, TrailVertexBuffer, and TrailVertexCount are
				// owned by ParticleFeature's per-emitter state and will be filled in by
				// that feature during its Phase 4 migration.
				list.CPUParticles.Add(.()
				{
					EmitterHandle = renderHandle,
					VertexBuffer = null,
					AliveCount = emitter.AliveCount,
					BlendMode = emitter.BlendMode,
					RenderMode = emitter.RenderMode,
					SoftParticleDistance = emitter.SoftParticleDistance,
					SortParticles = emitter.SortParticles,
					Lit = emitter.Lit,
					AtlasColumns = emitter.AtlasColumns,
					AtlasRows = emitter.AtlasRows,
					LayerMask = emitter.LayerMask,
					HasTrails = emitter.Trail.IsActive,
					TrailVertexBuffer = null,
					TrailVertexCount = 0
				});
			}
		});
	}

	// ==================== Trails ====================

	private void PopulateTrails(RenderableList list)
	{
		ForEachTrailEmitter(scope (handle, trail) =>
		{
			if (!trail.IsActive || !trail.IsEnabled)
				return;

			let renderHandle = TrailEmitterRenderHandle() { Handle = handle };
			let trailEmitter = GetTrailEmitterInstance(renderHandle);

			list.Trails.Add(.()
			{
				TrailHandle = renderHandle,
				VertexBuffer = (trailEmitter != null) ? trailEmitter.GetVertexBuffer(0) : null,
				VertexCount = (trailEmitter != null) ? trailEmitter.VertexCount : 0,
				BlendMode = trail.BlendMode,
				SoftParticleDistance = trail.SoftParticleDistance,
				LayerMask = trail.LayerMask
			});
		});
	}

	// ==================== Terrain ====================

	private void PopulateTerrains(RenderableList list)
	{
		ForEachTerrain(scope (handle, terrain) =>
		{
			if (!terrain.IsActive)
				return;

			var renderable = TerrainRenderable();
			renderable.PatchCountX = terrain.PatchCountX;
			renderable.PatchCountZ = terrain.PatchCountZ;
			renderable.Origin = terrain.Position;
			renderable.WorldSize = terrain.WorldSize;
			renderable.HeightScale = terrain.HeightScale;
			renderable.HeightmapWidth = terrain.HeightmapWidth;
			renderable.HeightmapHeight = terrain.HeightmapHeight;
			renderable.LayerScales = terrain.LayerScales;
			renderable.Roughness = terrain.Roughness;
			renderable.Metallic = terrain.Metallic;
			renderable.HeightmapView = terrain.HeightmapView;
			renderable.NormalMapView = terrain.NormalMapView;
			renderable.SplatmapView = terrain.SplatmapView;
			renderable.LayerAlbedoViews = terrain.LayerAlbedoViews;
			renderable.WorldBounds = terrain.WorldBounds;
			list.Terrains.Add(renderable);
		});
	}

	// ==================== Grass ====================

	private void PopulateGrassPatches(RenderableList list)
	{
		ForEachGrass(scope (handle, grass) =>
		{
			if (!grass.IsActive)
				return;

			var renderable = GrassRenderable();
			renderable.Origin = grass.TerrainOrigin;
			renderable.WorldSize = grass.TerrainWorldSize;
			renderable.HeightScale = grass.HeightScale;
			renderable.HeightmapData = grass.HeightmapData;
			renderable.HeightmapWidth = grass.HeightmapWidth;
			renderable.HeightmapHeight = grass.HeightmapHeight;
			renderable.SplatmapData = grass.SplatmapData;
			renderable.SplatmapWidth = grass.SplatmapWidth;
			renderable.SplatmapHeight = grass.SplatmapHeight;
			renderable.SplatChannel = grass.SplatChannel;
			renderable.SplatThreshold = grass.SplatThreshold;
			renderable.AlbedoView = grass.AlbedoView;
			renderable.GrassColor = grass.GrassColor;
			renderable.AlphaCutoff = grass.AlphaCutoff;
			renderable.Roughness = grass.Roughness;
			renderable.BladeWidth = grass.BladeWidth;
			renderable.BladeHeight = grass.BladeHeight;
			renderable.Distance = grass.Distance;
			renderable.Density = grass.Density;
			renderable.MinScale = grass.MinScale;
			renderable.MaxScale = grass.MaxScale;
			renderable.WindStrength = grass.WindStrength;
			renderable.WindFrequency = grass.WindFrequency;
			renderable.WindDirection = grass.WindDirection;
			renderable.WorldBounds = grass.WorldBounds;
			list.GrassPatches.Add(renderable);
		});
	}

	// ==================== Water ====================

	private void PopulateWaterSurfaces(RenderableList list)
	{
		ForEachWater(scope (handle, water) =>
		{
			if (!water.IsActive)
				return;

			list.WaterSurfaces.Add(.()
			{
				Center = water.Position,
				WorldSize = water.Size,
				WaterColor = water.WaterColor,
				WaveSpeed = water.WaveSpeed,
				WaveScale = water.WaveScale,
				NormalStrength = water.NormalStrength,
				FresnelR0 = water.FresnelR0,
				RefractionStrength = water.RefractionStrength,
				SpecularPower = water.SpecularPower,
				MaxVisibleDepth = water.MaxVisibleDepth,
				FoamDepthThreshold = water.FoamDepthThreshold,
				FoamIntensity = water.FoamIntensity,
				Roughness = water.Roughness,
				FlowDirection = water.FlowDirection,
				NormalMapView = water.NormalMapView,
				FoamTextureView = water.FoamTextureView,
				WorldBounds = water.WorldBounds
			});
		});
	}

	// ==================== Reflection Probes ====================

	private void PopulateReflectionProbes(RenderableList list)
	{
		ForEachReflectionProbe(scope (handle, probe) =>
		{
			if (!probe.IsActive || !probe.IsEnabled)
				return;

			list.ReflectionProbes.Add(.()
			{
				ProbeHandle = ReflectionProbeRenderHandle() { Handle = handle },
				Position = probe.Position,
				Radius = probe.Radius,
				IsEnabled = probe.IsEnabled,
				ArrayLayer = probe.ArrayLayer,
				IsDirty = probe.IsDirty,
				ZenithColor = probe.ZenithColor,
				HorizonColor = probe.HorizonColor,
				GroundColor = probe.GroundColor,
				IrradianceSH = probe.IrradianceSH
			});

			// Consume the proxy's dirty flag — ReflectionProbeSystem is the
			// authoritative dirty tracker now (via MarkDirty + its internal
			// HashSet), and the renderable already carried the signal. Clearing
			// here prevents legacy code that pokes proxy.IsDirty once from
			// triggering a rebake every frame.
			probe.IsDirty = false;
		});
	}
}
