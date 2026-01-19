using System;
using System.Collections;
using Sedulous.Renderer.Resources;
using Sedulous.Animation.Resources;

namespace Sedulous.Geometry.Tooling;

/// Result of importing a model, containing all created resources.
/// Caller takes ownership of all resources.
class ModelImportResult : IDisposable
{
	/// Imported static meshes.
	public List<StaticMeshResource> StaticMeshes = new .() ~ DeleteContainerAndItems!(_);

	/// Imported skinned meshes.
	public List<SkinnedMeshResource> SkinnedMeshes = new .() ~ DeleteContainerAndItems!(_);

	/// Imported skeletons.
	public List<SkeletonResource> Skeletons = new .() ~ DeleteContainerAndItems!(_);

	/// Imported textures.
	public List<TextureResource> Textures = new .() ~ DeleteContainerAndItems!(_);

	/// Imported materials.
	public List<MaterialResource> Materials = new .() ~ DeleteContainerAndItems!(_);

	/// Imported animation clips.
	public List<AnimationClipResource> Animations = new .() ~ DeleteContainerAndItems!(_);

	/// Errors encountered during import.
	public List<String> Errors = new .() ~ DeleteContainerAndItems!(_);

	/// Warnings encountered during import.
	public List<String> Warnings = new .() ~ DeleteContainerAndItems!(_);

	/// Whether the import completed successfully (no errors).
	public bool Success => Errors.Count == 0;

	/// Total number of resources imported.
	public int TotalResourceCount =>
		StaticMeshes.Count + SkinnedMeshes.Count + Skeletons.Count +
		Textures.Count + Materials.Count + Animations.Count;

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
	public StaticMeshResource TakeStaticMesh(int index)
	{
		if (index < 0 || index >= StaticMeshes.Count)
			return null;
		let mesh = StaticMeshes[index];
		StaticMeshes.RemoveAt(index);
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
	public StaticMeshResource FindStaticMesh(StringView name)
	{
		for (let mesh in StaticMeshes)
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

	/// Take ownership of an animation resource (removes from this result).
	public AnimationClipResource TakeAnimation(int index)
	{
		if (index < 0 || index >= Animations.Count)
			return null;
		let anim = Animations[index];
		Animations.RemoveAt(index);
		return anim;
	}

	/// Find an animation by name.
	public AnimationClipResource FindAnimation(StringView name)
	{
		for (let anim in Animations)
			if (anim.Name == name)
				return anim;
		return null;
	}
}
