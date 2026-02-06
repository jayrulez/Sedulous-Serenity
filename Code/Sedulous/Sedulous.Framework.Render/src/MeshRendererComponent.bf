namespace Sedulous.Framework.Render;

using Sedulous.Framework.Scenes;
using Sedulous.Geometry.Resources;
using Sedulous.Materials;
using Sedulous.Materials.Resources;
using Sedulous.Resources;
using Sedulous.Serialization;
using static Sedulous.Resources.ResourceSerializerExtensions;


/// Component for entities with a static mesh.
/// Set the Mesh field and the framework handles GPU upload automatically.
/// Note: ResourceHandle uses manual ref counting. Call AddRef() when copying,
/// Release() when removing/replacing.
struct MeshRendererComponent : ISerializableComponent
{
	/// The mesh resource handle (runtime, not serialized).
	public ResourceHandle<StaticMeshResource> Mesh;
	/// Serializable reference to the mesh resource.
	public ResourceRef MeshRef;
	/// The material resource handle (runtime, not serialized).
	public ResourceHandle<MaterialResource> Material;
	/// Serializable reference to the material resource.
	public ResourceRef MaterialRef;
	/// The material instance for rendering (runtime, created from MaterialResource).
	public MaterialInstance MaterialInstance;
	/// Whether this renderer is enabled.
	public bool Enabled;

	public int32 SerializationVersion => 2;

	public SerializationResult Serialize(Serializer s) mut
	{
		var version = SerializationVersion;
		s.Version(ref version);
		if (version >= 2)
		{
			s.ResourceRef("mesh", ref MeshRef);
			s.ResourceRef("material", ref MaterialRef);
		}
		s.Bool("enabled", ref Enabled);
		return .Ok;
	}

	public static MeshRendererComponent Default => .() {
		Mesh = default,
		MeshRef = .(),
		Material = default,
		MaterialRef = .(),
		MaterialInstance = null,
		Enabled = true
	};
}
