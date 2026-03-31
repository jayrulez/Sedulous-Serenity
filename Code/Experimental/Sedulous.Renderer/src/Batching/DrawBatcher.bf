namespace Sedulous.Renderer;

using System;
using System.Collections;

using internal Sedulous.Renderer;

/// Groups visible meshes into batched draw calls with auto-instancing.
class DrawBatcher
{
	private List<DrawBatch> mOpaqueBatches = new .() ~ delete _;
	private List<DrawBatch> mTransparentBatches = new .() ~ delete _;
	private List<InstanceGroup> mInstanceGroups = new .() ~ delete _;
	private List<ProxyHandle> mInstanceProxies = new .() ~ delete _;
	private Dictionary<BatchKey, int32> mGroupMap = new .() ~ delete _;

	public List<DrawBatch> OpaqueBatches => mOpaqueBatches;
	public List<DrawBatch> TransparentBatches => mTransparentBatches;
	public List<InstanceGroup> InstanceGroups => mInstanceGroups;
	public List<ProxyHandle> InstanceProxies => mInstanceProxies;

	/// Builds draw batches from visibility results.
	/// materialLookup: returns a MaterialInstance for a handle (used to check blend mode).
	public void Build(RenderWorld world, GPUResourceManager resources, VisibilityResolver visibility,
		delegate MaterialInstance(MaterialInstanceHandle) materialLookup = null)
	{
		Clear();

		for (let vm in visibility.VisibleMeshes)
		{
			let proxy = world.StaticMeshes.Get(vm.Handle);
			if (proxy == null) continue;

			let mesh = resources.GetMesh(vm.MeshHandle);
			if (mesh == null) continue;

			// Determine submesh range for selected LOD
			uint32 subStart = 0;
			uint32 subCount = (uint32)mesh.SubMeshes.Count;

			if (mesh.LODCount > 0 && mesh.LODLevels != null)
			{
				let lodIdx = Math.Min((uint32)vm.LODLevel, mesh.LODCount - 1);
				let lod = mesh.LODLevels[lodIdx];
				subStart = lod.SubMeshStart;
				subCount = lod.SubMeshCount;
			}

			// Emit a draw per submesh in the LOD
			for (uint32 si = subStart; si < subStart + subCount; si++)
			{
				if (si >= (uint32)mesh.SubMeshes.Count) break;

				let subMesh = mesh.SubMeshes[si];
				let matSlot = subMesh.MaterialSlot;

				// Get material handle from proxy
				let materialHandle = (matSlot < proxy.MaterialCount)
					? proxy.Materials[matSlot]
					: MaterialInstanceHandle.Invalid;

				let key = BatchKey()
				{
					Material = materialHandle,
					Mesh = vm.MeshHandle,
					SubMeshIndex = si,
					LODLevel = vm.LODLevel
				};

				// Group into instance groups
				if (mGroupMap.TryGetValue(key, let groupIdx))
				{
					// Add to existing group
					mInstanceGroups[groupIdx].Count++;
					mInstanceProxies.Add(vm.Handle);
				}
				else
				{
					// Create new group
					let newGroup = InstanceGroup()
					{
						Key = key,
						StartIndex = (uint32)mInstanceProxies.Count,
						Count = 1,
						SortKey = vm.SortKey
					};
					mGroupMap[key] = (int32)mInstanceGroups.Count;
					mInstanceGroups.Add(newGroup);
					mInstanceProxies.Add(vm.Handle);
				}
			}
		}

		// Emit batches from groups, routing to opaque or transparent
		for (int gi = 0; gi < mInstanceGroups.Count; gi++)
		{
			let group = mInstanceGroups[gi];
			let batch = DrawBatch()
			{
				MeshHandle = group.Key.Mesh,
				MaterialHandle = group.Key.Material,
				SubMeshIndex = group.Key.SubMeshIndex,
				LODLevel = group.Key.LODLevel,
				InstanceCount = group.Count,
				InstanceBufferOffset = 0,
				SortKey = group.SortKey,
				GroupIndex = (int32)gi
			};

			// Check material blend mode to route opaque vs transparent
			bool isTransparent = false;
			if (materialLookup != null)
			{
				let matInst = materialLookup(group.Key.Material);
				if (matInst != null && matInst.Definition.BlendMode != .Opaque)
					isTransparent = true;
			}

			if (isTransparent)
				mTransparentBatches.Add(batch);
			else
				mOpaqueBatches.Add(batch);
		}

		// Sort opaque by sort key (material-first, then depth — front-to-back)
		mOpaqueBatches.Sort(scope (a, b) => a.SortKey <=> b.SortKey);

		// Sort transparent back-to-front (reverse distance order)
		mTransparentBatches.Sort(scope (a, b) => b.SortKey <=> a.SortKey);
	}

	/// Builds batches filtered to shadow casters only.
	public void BuildShadowCasters(RenderWorld world, GPUResourceManager resources, VisibilityResolver visibility)
	{
		Clear();

		for (let vm in visibility.VisibleMeshes)
		{
			let proxy = world.StaticMeshes.Get(vm.Handle);
			if (proxy == null) continue;
			if (!proxy.Flags.HasFlag(.CastShadows)) continue;

			let mesh = resources.GetMesh(vm.MeshHandle);
			if (mesh == null) continue;

			uint32 subStart = 0;
			uint32 subCount = (uint32)mesh.SubMeshes.Count;

			if (mesh.LODCount > 0 && mesh.LODLevels != null)
			{
				let lodIdx = Math.Min((uint32)vm.LODLevel, mesh.LODCount - 1);
				let lod = mesh.LODLevels[lodIdx];
				subStart = lod.SubMeshStart;
				subCount = lod.SubMeshCount;
			}

			for (uint32 si = subStart; si < subStart + subCount; si++)
			{
				if (si >= (uint32)mesh.SubMeshes.Count) break;

				let batch = DrawBatch()
				{
					MeshHandle = vm.MeshHandle,
					MaterialHandle = .Invalid,
					SubMeshIndex = si,
					LODLevel = vm.LODLevel,
					InstanceCount = 1,
					InstanceBufferOffset = 0,
					SortKey = vm.SortKey
				};

				mOpaqueBatches.Add(batch);
			}
		}

		mOpaqueBatches.Sort(scope (a, b) => a.SortKey <=> b.SortKey);
	}

	/// Clears all results without releasing memory.
	public void Clear()
	{
		mOpaqueBatches.Clear();
		mTransparentBatches.Clear();
		mInstanceGroups.Clear();
		mInstanceProxies.Clear();
		mGroupMap.Clear();
	}
}
