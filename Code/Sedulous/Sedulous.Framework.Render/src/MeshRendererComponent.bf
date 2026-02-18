namespace Sedulous.Framework.Render;

using Sedulous.Framework.Scenes;
using Sedulous.Geometry.Resources;
using Sedulous.Materials;
using Sedulous.Materials.Resources;
using Sedulous.Render;
using Sedulous.Resources;
using Sedulous.Serialization;
using System;
using static Sedulous.Resources.ResourceSerializerExtensions;


/// Component for entities with a static mesh.
/// Set the Mesh field and the framework handles GPU upload automatically.
/// Supports up to MaxMaterialsPerMesh material slots for multi-submesh rendering.
[Component]
struct MeshRendererComponent : ISerializableComponent
{
	/// The mesh resource handle (runtime, not serialized).
	public ResourceHandle<StaticMeshResource> Mesh;
	/// Serializable reference to the mesh resource.
	[Property] public ResourceRef MeshRef;
	/// Number of active material slots.
	public int32 MaterialCount;
	/// Serializable references to material resources (one per submesh slot).
	public ResourceRef[RenderConfig.MaxMaterialsPerMesh] MaterialRefs;
	/// Material resource handles (runtime, not serialized).
	public ResourceHandle<MaterialResource>[RenderConfig.MaxMaterialsPerMesh] Materials;
	/// Material instances for rendering (runtime, created from MaterialResource).
	public MaterialInstance[RenderConfig.MaxMaterialsPerMesh] MaterialInstances;
	/// Whether this renderer is enabled.
	[Property] public bool Enabled;

	public void Dispose() mut
	{
		MeshRef.Dispose();
		for (int32 i = 0; i < MaterialRefs.Count; i++)
			MaterialRefs[i].Dispose();
	}

	public int32 SerializationVersion => 3;

	public SerializationResult Serialize(Serializer s) mut
	{
		var version = SerializationVersion;
		s.Version(ref version);
		s.ResourceRef("mesh", ref MeshRef);
		s.Int32("materialCount", ref MaterialCount);
		for (int32 i = 0; i < MaterialCount; i++)
		{
			let name = scope String();
			name.AppendF("material{}", i);
			s.ResourceRef(name, ref MaterialRefs[i]);
		}
		s.Bool("enabled", ref Enabled);
		return .Ok;
	}

	public static MeshRendererComponent Default => .() {
		Mesh = default,
		MeshRef = .(),
		MaterialCount = 0,
		MaterialRefs = .(),
		Materials = .(),
		MaterialInstances = .(),
		Enabled = true
	};
}
