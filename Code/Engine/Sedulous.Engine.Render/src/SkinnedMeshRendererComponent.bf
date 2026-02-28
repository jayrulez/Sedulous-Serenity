namespace Sedulous.Engine.Render;

using Sedulous.Engine.Scenes;
using Sedulous.Geometry.Resources;
using Sedulous.Materials;
using Sedulous.Materials.Resources;
using Sedulous.Render;
using Sedulous.Resources;
using Sedulous.Serialization;
using System;

using static Sedulous.Resources.ResourceSerializerExtensions;

/// Component for entities with a skinned mesh.
/// Set the Mesh field and the framework handles GPU upload automatically.
/// Supports up to MaxMaterialsPerMesh material slots for multi-submesh rendering.
[Component]
struct SkinnedMeshRendererComponent : ISerializableComponent
{
	/// The skinned mesh resource handle (runtime, not serialized).
	public ResourceHandle<SkinnedMeshResource> Mesh;
	/// Serializable reference to the mesh resource.
	[Property] public ResourceRef MeshRef;
	/// Serializable references to material resources (one per submesh slot).
	[Property] public ResourceRefArray<const RenderConfig.MaxMaterialsPerMesh> MaterialRefs;
	/// Material resource handles (runtime, not serialized).
	public ResourceHandle<MaterialResource>[RenderConfig.MaxMaterialsPerMesh] Materials;
	/// Material instances for rendering (runtime, created from MaterialResource).
	public MaterialInstance[RenderConfig.MaxMaterialsPerMesh] MaterialInstances;
	/// Whether this renderer is enabled.
	[Property] public bool Enabled;

	public void Dispose() mut
	{
		MeshRef.Dispose();
		MaterialRefs.Dispose();
	}

	public int32 SerializationVersion => 3;

	public SerializationResult Serialize(Serializer s) mut
	{
		var version = SerializationVersion;
		s.Version(ref version);
		s.ResourceRef("mesh", ref MeshRef);
		s.ResourceRefArray("materials", ref MaterialRefs);
		s.Bool("enabled", ref Enabled);
		return .Ok;
	}

	public static SkinnedMeshRendererComponent Default => .() {
		Mesh = default,
		MeshRef = .(),
		MaterialRefs = .(),
		Materials = .(),
		MaterialInstances = .(),
		Enabled = true
	};
}
