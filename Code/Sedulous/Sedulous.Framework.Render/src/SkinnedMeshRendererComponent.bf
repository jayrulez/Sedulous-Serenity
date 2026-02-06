namespace Sedulous.Framework.Render;

using Sedulous.Framework.Scenes;
using Sedulous.Geometry.Resources;
using Sedulous.Materials;
using Sedulous.Resources;
using Sedulous.Serialization;

/// Component for entities with a skinned mesh.
/// Set the Mesh field and the framework handles GPU upload automatically.
/// Note: ResourceHandle uses manual ref counting. Call AddRef() when copying,
/// Release() when removing/replacing.
struct SkinnedMeshRendererComponent : ISerializableComponent
{
	/// The skinned mesh resource handle. Set this to change the mesh.
	/// Create with ResourceHandle<SkinnedMeshResource>(resource) which calls AddRef().
	/// Call Release() when removing or replacing the mesh.
	public ResourceHandle<SkinnedMeshResource> Mesh;
	/// The material to use for rendering. Can be set before or after the mesh.
	public MaterialInstance Material;
	/// Whether this renderer is enabled.
	public bool Enabled;

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer s) mut
	{
		var version = SerializationVersion;
		s.Version(ref version);
		// TODO: Serialize Mesh (resource path) and Material when resource serialization is implemented
		s.Bool("enabled", ref Enabled);
		return .Ok;
	}

	public static SkinnedMeshRendererComponent Default => .() {
		Mesh = default,
		Material = null,
		Enabled = true
	};
}
