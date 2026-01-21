using System;
using System.IO;
using System.Collections;
using Sedulous.Serialization;
using Sedulous.Serialization.OpenDDL;
using Sedulous.OpenDDL;
using Sedulous.Mathematics;
using Sedulous.Geometry;
using Sedulous.Imaging;
using Sedulous.Renderer;
using Sedulous.Animation.Resources;
using Sedulous.Geometry.Resources;
using Sedulous.Textures.Resources;

namespace Sedulous.Geometry.Tooling;

/// Resource file type identifiers.
/// These match the FileType constants in each resource class.
enum ResourceFileType
{
	Unknown,
	Mesh = 1,
	SkinnedMesh = 2,
	Skeleton = 3,
	Animation = 4,
	AnimationSet = 5,
	Material = 6,
	SkinnedMeshBundle = 7,
	Texture = 8
}

/// Serializes and deserializes renderer resources to/from files.
/// Note: Each resource class now has its own SaveToFile/LoadFromFile methods.
/// This class provides batch operations and compatibility wrappers.
static class ResourceSerializer
{
	public const int32 CurrentVersion = 1;

	// ===== Compatibility wrappers that delegate to resource methods =====

	/// Save a MeshResource to a file. Delegates to MeshResource.SaveToFile.
	public static Result<void> SaveStaticMesh(StaticMeshResource resource, StringView path)
	{
		return resource?.SaveToFile(path) ?? .Err;
	}

	/// Load a MeshResource from a file. Delegates to MeshResource.LoadFromFile.
	public static Result<StaticMeshResource> LoadStaticMesh(StringView path)
	{
		return StaticMeshResource.LoadFromFile(path);
	}

	/// Save a SkinnedMeshResource bundle to a file. Delegates to SkinnedMeshResource.SaveToFile.
	public static Result<void> SaveSkinnedMeshBundle(SkinnedMeshResource resource, StringView path)
	{
		return resource?.SaveToFile(path) ?? .Err;
	}

	/// Load a SkinnedMeshResource bundle from a file. Delegates to SkinnedMeshResource.LoadFromFile.
	public static Result<SkinnedMeshResource> LoadSkinnedMeshBundle(StringView path)
	{
		return SkinnedMeshResource.LoadFromFile(path);
	}

	/// Save a SkeletonResource to a file. Delegates to SkeletonResource.SaveToFile.
	public static Result<void> SaveSkeleton(SkeletonResource resource, StringView path)
	{
		return resource?.SaveToFile(path) ?? .Err;
	}

	/// Load a SkeletonResource from a file. Delegates to SkeletonResource.LoadFromFile.
	public static Result<SkeletonResource> LoadSkeleton(StringView path)
	{
		return SkeletonResource.LoadFromFile(path);
	}

	/// Save an AnimationClipResource to a file. Delegates to AnimationClipResource.SaveToFile.
	public static Result<void> SaveAnimation(AnimationClipResource resource, StringView path)
	{
		return resource?.SaveToFile(path) ?? .Err;
	}

	/// Load an AnimationClipResource from a file. Delegates to AnimationClipResource.LoadFromFile.
	public static Result<AnimationClipResource> LoadAnimation(StringView path)
	{
		return AnimationClipResource.LoadFromFile(path);
	}

	/// Save a MaterialResource to a file. Delegates to MaterialResource.SaveToFile.
	public static Result<void> SaveMaterial(MaterialResource material, StringView path)
	{
		return material?.SaveToFile(path) ?? .Err;
	}

	/// Load a MaterialResource from a file. Delegates to MaterialResource.LoadFromFile.
	public static Result<MaterialResource> LoadMaterial(StringView path)
	{
		return MaterialResource.LoadFromFile(path);
	}

	/// Save a TextureResource to a binary file. Delegates to TextureResource.SaveToFile.
	public static Result<void> SaveTexture(TextureResource resource, StringView path)
	{
		return resource?.SaveToFile(path) ?? .Err;
	}

	/// Load a TextureResource from a binary file. Delegates to TextureResource.LoadFromFile.
	public static Result<TextureResource> LoadTexture(StringView path)
	{
		return TextureResource.LoadFromFile(path);
	}

	// ===== Batch operations =====

	/// Save all resources from an import result to a directory.
	public static Result<void> SaveImportResult(ModelImportResult result, StringView outputDir)
	{
		// Ensure directory exists
		if (!Directory.Exists(outputDir))
		{
			if (Directory.CreateDirectory(outputDir) case .Err)
				return .Err;
		}

		// Save meshes
		for (let mesh in result.StaticMeshes)
		{
			let path = scope String();
			path.AppendF("{}/{}.mesh", outputDir, mesh.Name);
			SanitizePath(path);
			SaveStaticMesh(mesh, path);
		}

		// Save skinned meshes (as bundles)
		for (let mesh in result.SkinnedMeshes)
		{
			let path = scope String();
			path.AppendF("{}/{}.skinnedmesh", outputDir, mesh.Name);
			SanitizePath(path);
			SaveSkinnedMeshBundle(mesh, path);
		}

		// Save standalone skeletons
		for (let skeleton in result.Skeletons)
		{
			let path = scope String();
			path.AppendF("{}/{}.skeleton", outputDir, skeleton.Name);
			SanitizePath(path);
			SaveSkeleton(skeleton, path);
		}

		// Save materials
		for (let material in result.Materials)
		{
			let path = scope String();
			path.AppendF("{}/{}.material", outputDir, material.Name);
			SanitizePath(path);
			SaveMaterial(material, path);
		}

		// Save textures
		for (let texture in result.Textures)
		{
			let path = scope String();
			path.AppendF("{}/{}.texture", outputDir, texture.Name);
			SanitizePath(path);
			SaveTexture(texture, path);
		}

		// Save animations
		for (let animation in result.Animations)
		{
			let path = scope String();
			path.AppendF("{}/{}.animation", outputDir, animation.Name);
			SanitizePath(path);
			SaveAnimation(animation, path);
		}

		return .Ok;
	}

	private static void SanitizePath(String path)
	{
		// Replace invalid filename characters
		/*for (int i = 0; i < path.Length; i++)
		{
			char8 c = path[i];
			if (c == '<' || c == '>' || c == ':' || c == '"' || c == '|' || c == '?' || c == '*')
			{
				path[i] = '_';
			}
		}*/
	}
}
