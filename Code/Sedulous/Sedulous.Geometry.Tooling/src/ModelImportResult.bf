using System;
using System.Collections;
using Sedulous.Framework.Renderer;

namespace Sedulous.Geometry.Tooling;

/// Result of importing a model, containing all created resources.
/// Caller takes ownership of all resources.
class ModelImportResult : IDisposable
{
	/// Imported static meshes.
	public List<MeshResource> Meshes = new .() ~ DeleteContainerAndItems!(_);

	/// Imported skinned meshes.
	public List<SkinnedMeshResource> SkinnedMeshes = new .() ~ DeleteContainerAndItems!(_);

	/// Imported skeletons.
	public List<SkeletonResource> Skeletons = new .() ~ DeleteContainerAndItems!(_);

	/// Imported textures.
	public List<TextureResource> Textures = new .() ~ DeleteContainerAndItems!(_);

	/// Imported material definitions.
	public List<MaterialDefinition> Materials = new .() ~ DeleteContainerAndItems!(_);

	/// Errors encountered during import.
	public List<String> Errors = new .() ~ DeleteContainerAndItems!(_);

	/// Warnings encountered during import.
	public List<String> Warnings = new .() ~ DeleteContainerAndItems!(_);

	/// Whether the import completed successfully (no errors).
	public bool Success => Errors.Count == 0;

	/// Total number of resources imported.
	public int TotalResourceCount =>
		Meshes.Count + SkinnedMeshes.Count + Skeletons.Count +
		Textures.Count + Materials.Count;

	public void Dispose()
	{
		// Resources are deleted by the ~ destructor attributes
	}

	/// Add an error message.
	public void AddError(StringView message)
	{
		Errors.Add(new String(message));
	}

	/// Add a warning message.
	public void AddWarning(StringView message)
	{
		Warnings.Add(new String(message));
	}

	/// Take ownership of a mesh resource (removes from this result).
	public MeshResource TakeMesh(int index)
	{
		if (index < 0 || index >= Meshes.Count)
			return null;
		let mesh = Meshes[index];
		Meshes.RemoveAt(index);
		return mesh;
	}

	/// Take ownership of a skinned mesh resource (removes from this result).
	public SkinnedMeshResource TakeSkinnedMesh(int index)
	{
		if (index < 0 || index >= SkinnedMeshes.Count)
			return null;
		let mesh = SkinnedMeshes[index];
		SkinnedMeshes.RemoveAt(index);
		return mesh;
	}

	/// Take ownership of a skeleton resource (removes from this result).
	public SkeletonResource TakeSkeleton(int index)
	{
		if (index < 0 || index >= Skeletons.Count)
			return null;
		let skeleton = Skeletons[index];
		Skeletons.RemoveAt(index);
		return skeleton;
	}

	/// Take ownership of a texture resource (removes from this result).
	public TextureResource TakeTexture(int index)
	{
		if (index < 0 || index >= Textures.Count)
			return null;
		let texture = Textures[index];
		Textures.RemoveAt(index);
		return texture;
	}

	/// Find a mesh by name.
	public MeshResource FindMesh(StringView name)
	{
		for (let mesh in Meshes)
			if (mesh.Name == name)
				return mesh;
		return null;
	}

	/// Find a skinned mesh by name.
	public SkinnedMeshResource FindSkinnedMesh(StringView name)
	{
		for (let mesh in SkinnedMeshes)
			if (mesh.Name == name)
				return mesh;
		return null;
	}

	/// Find a skeleton by name.
	public SkeletonResource FindSkeleton(StringView name)
	{
		for (let skeleton in Skeletons)
			if (skeleton.Name == name)
				return skeleton;
		return null;
	}

	/// Find a texture by name.
	public TextureResource FindTexture(StringView name)
	{
		for (let texture in Textures)
			if (texture.Name == name)
				return texture;
		return null;
	}
}

/// Material property definition (CPU-side, for serialization).
class MaterialDefinition
{
	public String Name = new .() ~ delete _;

	// PBR properties
	public float[4] BaseColor = .(1, 1, 1, 1);
	public float Metallic = 0.0f;
	public float Roughness = 0.5f;
	public float[3] EmissiveFactor = .(0, 0, 0);

	// Texture references (names/paths)
	public String BaseColorTexture = new .() ~ delete _;
	public String NormalTexture = new .() ~ delete _;
	public String MetallicRoughnessTexture = new .() ~ delete _;
	public String OcclusionTexture = new .() ~ delete _;
	public String EmissiveTexture = new .() ~ delete _;

	// Rendering properties
	public bool DoubleSided = false;
	public AlphaMode AlphaMode = .Opaque;
	public float AlphaCutoff = 0.5f;
}

/// Alpha blending mode for materials.
enum AlphaMode
{
	Opaque,
	Mask,
	Blend
}
