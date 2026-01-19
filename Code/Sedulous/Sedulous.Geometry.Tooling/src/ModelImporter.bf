using System;
using System.IO;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.Geometry;
using Sedulous.Models;
using Sedulous.Imaging;
using Sedulous.Renderer;
using Sedulous.Renderer.Resources;
using Sedulous.Animation.Resources;

namespace Sedulous.Geometry.Tooling;

/// Imports models and creates CPU resources.
class ModelImporter
{
	private ModelImportOptions mOptions ~ delete _;
	private ImageLoader mImageLoader;

	/// Create an importer with the given options and image loader.
	/// The importer does NOT take ownership of the image loader.
	public this(ModelImportOptions options, ImageLoader imageLoader = null)
	{
		mOptions = options;
		mImageLoader = imageLoader;
	}

	/// Import resources from a loaded model.
	public ModelImportResult Import(Model model)
	{
		let result = new ModelImportResult();

		if (model == null)
		{
			result.AddError("Model is null");
			return result;
		}

		// Import skeletons first (needed for skinned meshes)
		if (mOptions.Flags.HasFlag(.Skeletons))
		{
			ImportSkeletons(model, result);
		}

		// Import meshes
		if (mOptions.Flags.HasFlag(.Meshes))
		{
			ImportStaticMeshes(model, result);
		}

		// Import skinned meshes
		if (mOptions.Flags.HasFlag(.SkinnedMeshes))
		{
			ImportSkinnedMeshes(model, result);
		}

		// Import textures
		if (mOptions.Flags.HasFlag(.Textures))
		{
			ImportTextures(model, result);
		}

		// Import materials
		if (mOptions.Flags.HasFlag(.Materials))
		{
			ImportMaterials(model, result);
		}

		// Import standalone animations
		if (mOptions.Flags.HasFlag(.Animations))
		{
			ImportAnimations(model, result);
		}

		return result;
	}

	private void ImportSkeletons(Model model, ModelImportResult result)
	{
		for (int skinIdx = 0; skinIdx < model.Skins.Count; skinIdx++)
		{
			let skin = model.Skins[skinIdx];

			let skeleton = SkeletonConverter.CreateFromSkin(model, skin);
			if (skeleton == null)
			{
				result.AddWarning(scope $"Failed to create skeleton from skin {skinIdx}");
				continue;
			}

			let skeletonRes = new SkeletonResource(skeleton, true);

			// Generate name
			let name = scope String();
			if (skin.Joints.Count > 0 && skin.Joints[0] >= 0 && skin.Joints[0] < model.Bones.Count)
			{
				name.AppendF("{}_skeleton", model.Bones[skin.Joints[0]].Name);
			}
			else
			{
				name.AppendF("skeleton_{}", skinIdx);
			}
			skeletonRes.Name.Set(name);

			result.Skeletons.Add(skeletonRes);
		}
	}

	private void ImportStaticMeshes(Model model, ModelImportResult result)
	{
		for (int meshIdx = 0; meshIdx < model.Meshes.Count; meshIdx++)
		{
			let modelMesh = model.Meshes[meshIdx];

			// Check if this mesh has skinning data - if so, skip (handled by ImportSkinnedMeshes)
			bool hasSkinning = false;
			for (let element in modelMesh.VertexElements)
			{
				if (element.Semantic == .Joints || element.Semantic == .Weights)
				{
					hasSkinning = true;
					break;
				}
			}

			if (hasSkinning)
				continue;

			let mesh = ModelMeshConverter.ConvertToStaticMesh(modelMesh);
			if (mesh == null)
			{
				result.AddWarning(scope $"Failed to convert mesh '{modelMesh.Name}'");
				continue;
			}

			// Apply scale if needed
			if (mOptions.Scale != 1.0f)
			{
				ApplyScale(mesh, mOptions.Scale);
			}

			let meshRes = new StaticMeshResource(mesh, true);
			meshRes.Name.Set(modelMesh.Name);

			result.StaticMeshes.Add(meshRes);
		}
	}

	private void ImportSkinnedMeshes(Model model, ModelImportResult result)
	{
		// Group meshes by skin
		for (int skinIdx = 0; skinIdx < model.Skins.Count; skinIdx++)
		{
			let skin = model.Skins[skinIdx];

			// Find meshes that use this skin
			for (int meshIdx = 0; meshIdx < model.Meshes.Count; meshIdx++)
			{
				let modelMesh = model.Meshes[meshIdx];

				// Check if mesh has skinning data
				bool hasSkinning = false;
				for (let element in modelMesh.VertexElements)
				{
					if (element.Semantic == .Joints)
					{
						hasSkinning = true;
						break;
					}
				}

				if (!hasSkinning)
					continue;

				// Convert the mesh
				if (ModelMeshConverter.ConvertToSkinnedMesh(modelMesh, skin) case .Ok(var conversionResult))
				{
					defer conversionResult.Dispose();

					// Apply scale if needed
					if (mOptions.Scale != 1.0f)
					{
						ApplyScaleSkinned(conversionResult.Mesh, mOptions.Scale);
					}

					let skinnedMeshRes = new SkinnedMeshResource(conversionResult.Mesh, true);
					skinnedMeshRes.Name.Set(modelMesh.Name);

					// Create skeleton for this skinned mesh (each owns its own copy to avoid ref count issues)
					let skeleton = SkeletonConverter.CreateFromSkin(model, skin);
					if (skeleton != null)
					{
						skinnedMeshRes.SetSkeleton(skeleton, true);
					}

					// Import animations if requested
					if (mOptions.Flags.HasFlag(.Animations) && model.Animations.Count > 0)
					{
						let animations = AnimationConverter.ConvertAll(model, conversionResult.NodeToBoneMapping);
						skinnedMeshRes.SetAnimations(animations, true);
					}

					result.SkinnedMeshes.Add(skinnedMeshRes);
				}
				else
				{
					result.AddWarning(scope $"Failed to convert skinned mesh '{modelMesh.Name}'");
				}
			}
		}
	}

	private void ImportTextures(Model model, ModelImportResult result)
	{
		for (int texIdx = 0; texIdx < model.Textures.Count; texIdx++)
		{
			let modelTex = model.Textures[texIdx];

			// Use TextureConverter which handles decoded pixel data
			let textureRes = TextureConverter.Convert(modelTex, mImageLoader, mOptions.BasePath);

			if (textureRes == null)
			{
				result.AddWarning(scope $"Failed to load texture '{modelTex.Name}' (uri: {modelTex.Uri})");
				continue;
			}

			result.Textures.Add(textureRes);
		}
	}

	private void ImportMaterials(Model model, ModelImportResult result)
	{
		for (int matIdx = 0; matIdx < model.Materials.Count; matIdx++)
		{
			let modelMat = model.Materials[matIdx];

			// Use MaterialConverter to create MaterialResource
			let matRes = MaterialConverter.Convert(modelMat, model);

			if (matRes == null)
			{
				result.AddWarning(scope $"Failed to convert material '{modelMat.Name}'");
				continue;
			}

			result.Materials.Add(matRes);
		}
	}

	private void ImportAnimations(Model model, ModelImportResult result)
	{
		if (model.Animations.Count == 0 || model.Skins.Count == 0)
			return;

		// Use the first skin to get node-to-bone mapping
		let skin = model.Skins[0];
		let modelMesh = model.Meshes.Count > 0 ? model.Meshes[0] : null;

		// We need to find a mesh with skinning data to get the node-to-bone mapping
		int32[] nodeToBoneMapping = null;
		if (modelMesh != null)
		{
			bool hasSkinning = false;
			for (let element in modelMesh.VertexElements)
			{
				if (element.Semantic == .Joints)
				{
					hasSkinning = true;
					break;
				}
			}

			if (hasSkinning)
			{
				if (ModelMeshConverter.ConvertToSkinnedMesh(modelMesh, skin) case .Ok(var conversionResult))
				{
					nodeToBoneMapping = conversionResult.NodeToBoneMapping;
					delete conversionResult.Mesh;  // Not needed here, only using the mapping
					defer { conversionResult.Dispose(); }

					// Convert each animation to a resource
					for (let modelAnim in model.Animations)
					{
						let clip = AnimationConverter.Convert(modelAnim, nodeToBoneMapping);
						if (clip != null)
						{
							let animRes = new AnimationClipResource(clip, true);
							result.Animations.Add(animRes);
						}
						else
						{
							result.AddWarning(scope $"Failed to convert animation '{modelAnim.Name}'");
						}
					}
				}
			}
		}
	}

	private Image LoadImageFromMemory(Span<uint8> data)
	{
		if (mImageLoader == null)
			return null;

		if (mImageLoader.LoadFromMemory(data) case .Ok(var loadInfo))
		{
			defer loadInfo.Dispose();
			return new Image(loadInfo.Width, loadInfo.Height, loadInfo.Format, loadInfo.Data);
		}

		return null;
	}

	private Image LoadImageFromFile(StringView path)
	{
		if (mImageLoader == null)
			return null;

		if (mImageLoader.LoadFromFile(path) case .Ok(var loadInfo))
		{
			defer loadInfo.Dispose();
			return new Image(loadInfo.Width, loadInfo.Height, loadInfo.Format, loadInfo.Data);
		}

		return null;
	}

	private void ApplyScale(StaticMesh mesh, float scale)
	{
		if (mesh.Vertices == null)
			return;

		for (int32 i = 0; i < mesh.Vertices.VertexCount; i++)
		{
			var pos = mesh.GetPosition(i);
			mesh.SetPosition(i, pos * scale);
		}
	}

	private void ApplyScaleSkinned(SkinnedMesh mesh, float scale)
	{
		for (int32 i = 0; i < mesh.VertexCount; i++)
		{
			var vertex = mesh.GetVertex(i);
			vertex.Position = vertex.Position * scale;
			mesh.SetVertex(i, vertex);
		}
	}
}
