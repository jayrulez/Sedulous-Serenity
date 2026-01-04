using System;
using System.IO;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.Geometry;
using Sedulous.Models;
using Sedulous.Imaging;
using Sedulous.Framework.Renderer;

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

			let mesh = ModelMeshConverter.ConvertToMesh(modelMesh);
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

			let meshRes = new MeshResource(mesh, true);
			meshRes.Name.Set(modelMesh.Name);

			result.Meshes.Add(meshRes);
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

					// Link to skeleton if available
					if (skinIdx < result.Skeletons.Count)
					{
						skinnedMeshRes.SetSkeletonResource(result.Skeletons[skinIdx]);
					}
					else
					{
						// Create skeleton inline
						let skeleton = SkeletonConverter.CreateFromSkin(model, skin);
						if (skeleton != null)
						{
							skinnedMeshRes.SetSkeleton(skeleton, true);
						}
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

			Image image = null;

			// Try loading from embedded data first
			if (modelTex.HasEmbeddedData)
			{
				let data = Span<uint8>(modelTex.GetData(), modelTex.GetDataSize());
				image = LoadImageFromMemory(data);
			}
			// Otherwise try loading from file
			else if (!modelTex.Uri.IsEmpty && mImageLoader != null)
			{
				let fullPath = scope String();
				if (!mOptions.BasePath.IsEmpty)
				{
					fullPath.Append(mOptions.BasePath);
					if (!fullPath.EndsWith('/') && !fullPath.EndsWith('\\'))
						fullPath.Append('/');
				}
				fullPath.Append(modelTex.Uri);

				image = LoadImageFromFile(fullPath);
			}

			if (image == null)
			{
				result.AddWarning(scope $"Failed to load texture '{modelTex.Name}' (uri: {modelTex.Uri})");
				continue;
			}

			let textureRes = new TextureResource(image, true);
			textureRes.Name.Set(modelTex.Name.IsEmpty ? modelTex.Uri : modelTex.Name);
			textureRes.SetupFor3D();  // Default to 3D texture settings

			result.Textures.Add(textureRes);
		}
	}

	private void ImportMaterials(Model model, ModelImportResult result)
	{
		for (int matIdx = 0; matIdx < model.Materials.Count; matIdx++)
		{
			let modelMat = model.Materials[matIdx];

			let matDef = new MaterialDefinition();
			matDef.Name.Set(modelMat.Name);

			// Copy properties
			matDef.BaseColor = .(modelMat.BaseColorFactor.X, modelMat.BaseColorFactor.Y,
				modelMat.BaseColorFactor.Z, modelMat.BaseColorFactor.W);
			matDef.Metallic = modelMat.MetallicFactor;
			matDef.Roughness = modelMat.RoughnessFactor;
			matDef.EmissiveFactor = .(modelMat.EmissiveFactor.X, modelMat.EmissiveFactor.Y,
				modelMat.EmissiveFactor.Z);
			matDef.DoubleSided = modelMat.DoubleSided;
			matDef.AlphaCutoff = modelMat.AlphaCutoff;

			// Map alpha mode
			matDef.AlphaMode = modelMat.AlphaMode == .Opaque ? .Opaque :
				(modelMat.AlphaMode == .Mask ? .Mask : .Blend);

			// Set texture references (by name if available)
			if (modelMat.BaseColorTextureIndex >= 0 && modelMat.BaseColorTextureIndex < model.Textures.Count)
			{
				let tex = model.Textures[modelMat.BaseColorTextureIndex];
				matDef.BaseColorTexture.Set(tex.Name.IsEmpty ? tex.Uri : tex.Name);
			}

			if (modelMat.NormalTextureIndex >= 0 && modelMat.NormalTextureIndex < model.Textures.Count)
			{
				let tex = model.Textures[modelMat.NormalTextureIndex];
				matDef.NormalTexture.Set(tex.Name.IsEmpty ? tex.Uri : tex.Name);
			}

			if (modelMat.MetallicRoughnessTextureIndex >= 0 && modelMat.MetallicRoughnessTextureIndex < model.Textures.Count)
			{
				let tex = model.Textures[modelMat.MetallicRoughnessTextureIndex];
				matDef.MetallicRoughnessTexture.Set(tex.Name.IsEmpty ? tex.Uri : tex.Name);
			}

			if (modelMat.OcclusionTextureIndex >= 0 && modelMat.OcclusionTextureIndex < model.Textures.Count)
			{
				let tex = model.Textures[modelMat.OcclusionTextureIndex];
				matDef.OcclusionTexture.Set(tex.Name.IsEmpty ? tex.Uri : tex.Name);
			}

			if (modelMat.EmissiveTextureIndex >= 0 && modelMat.EmissiveTextureIndex < model.Textures.Count)
			{
				let tex = model.Textures[modelMat.EmissiveTextureIndex];
				matDef.EmissiveTexture.Set(tex.Name.IsEmpty ? tex.Uri : tex.Name);
			}

			result.Materials.Add(matDef);
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

	private void ApplyScale(Mesh mesh, float scale)
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
