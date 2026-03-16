using System;
using System.IO;
using System.Collections;
using Sedulous.Serialization;
using Sedulous.Serialization.OpenDDL;
using Sedulous.OpenDDL;
using Sedulous.Core.Mathematics;
using Sedulous.Geometry;
using Sedulous.Imaging;
using Sedulous.Animation;
using Sedulous.Animation.Resources;
using Sedulous.Geometry.Resources;
using Sedulous.Textures.Resources;
using Sedulous.Materials.Resources;
using Sedulous.Resources;
using Sedulous.Geometry.Tooling;

namespace Sedulous.Geometry.Tooling.Resources;

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
/// Converts ModelImportResult (plain data types) to resources, then saves.
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
	public static Result<void> SaveSkinnedMesh(SkinnedMeshResource resource, StringView path)
	{
		return resource?.SaveToFile(path) ?? .Err;
	}

	/// Load a SkinnedMeshResource bundle from a file. Delegates to SkinnedMeshResource.LoadFromFile.
	public static Result<SkinnedMeshResource> LoadSkinnedMesh(StringView path)
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

	/// Save all resources from a ResourceImportResult to a directory.
	/// Use this when you already have a ResourceImportResult (e.g., from ConvertFrom).
	public static Result<void> SaveImportResult(ResourceImportResult result, StringView outputDir)
	{
		// Ensure directory exists
		if (!Directory.Exists(outputDir))
		{
			if (Directory.CreateDirectory(outputDir) case .Err)
				return .Err;
		}

		// Save textures
		for (let tex in result.Textures)
		{
			let path = scope String();
			path.AppendF("{}/{}.texture", outputDir, tex.Name);
			SanitizePath(path);
			SaveTexture(tex, path);
		}

		// Save materials
		for (let mat in result.Materials)
		{
			let path = scope String();
			path.AppendF("{}/{}.material", outputDir, mat.Name);
			SanitizePath(path);
			SaveMaterial(mat, path);
		}

		// Save static meshes
		for (let mesh in result.StaticMeshes)
		{
			let path = scope String();
			path.AppendF("{}/{}.mesh", outputDir, mesh.Name);
			SanitizePath(path);
			SaveStaticMesh(mesh, path);
		}

		// Save skinned meshes
		for (let mesh in result.SkinnedMeshes)
		{
			let path = scope String();
			path.AppendF("{}/{}.skinnedmesh", outputDir, mesh.Name);
			SanitizePath(path);
			SaveSkinnedMesh(mesh, path);
		}

		// Save skeletons
		for (let skeleton in result.Skeletons)
		{
			let path = scope String();
			path.AppendF("{}/{}.skeleton", outputDir, skeleton.Name);
			SanitizePath(path);
			SaveSkeleton(skeleton, path);
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

	/// Save all resources from a plain ModelImportResult to a directory.
	/// Converts plain data → resources, saves to disk, and returns the ResourceImportResult
	/// (caller takes ownership — needed for registry building with GUIDs).
	public static Result<ResourceImportResult> SaveImportResult(ModelImportResult result, StringView outputDir)
	{
		let resourceResult = ResourceImportResult.ConvertFrom(result);

		if (SaveImportResult(resourceResult, outputDir) case .Err)
		{
			delete resourceResult;
			return .Err;
		}

		return .Ok(resourceResult);
	}

	public static void SanitizePath(String path)
	{
		path.Replace("\\", "/");
		// Replace invalid filename characters
		for (int i = 0; i < path.Length; i++)
		{
			char8 c = path[i];
			if (c == '<'
				|| c == '>'
				//|| c == ':'
				|| c == '"'
				|| c == '|'
				|| c == '?'
				|| c == '*')
			{
				path[i] = '_';
			}
		}
	}
}
