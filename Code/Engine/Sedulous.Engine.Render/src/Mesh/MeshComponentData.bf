namespace Sedulous.Engine.Render;

using Sedulous.Engine.Scenes;
using Sedulous.Render;
using Sedulous.Resources;
using Sedulous.Serialization;
using static Sedulous.Resources.ResourceSerializerExtensions;

/// Transient data struct for MeshComponent serialization/deserialization.
/// Not stored on entities — only used by MeshComponentSerializer during save/load.
struct MeshComponentData : ISerializableComponentData
{
	[Property] public ResourceRef MeshRef;
	[Property] public ResourceRefArray<const RenderConfig.MaxMaterialsPerMesh> MaterialRefs;
	[Property] public bool Enabled;

	public int32 SerializationVersion => 1;

	public SerializationResult Serialize(Serializer s) mut
	{
		var version = SerializationVersion;
		s.Version(ref version);
		s.ResourceRef("mesh", ref MeshRef);
		s.ResourceRefArray("materials", ref MaterialRefs);
		s.Bool("enabled", ref Enabled);
		return .Ok;
	}

	public void Dispose() mut
	{
		MeshRef.Dispose();
		MaterialRefs.Dispose();
	}
}
