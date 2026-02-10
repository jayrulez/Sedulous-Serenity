using System;
using System.Collections;
using Sedulous.Models;
using Sedulous.Mathematics;
using Sedulous.Materials;
using Sedulous.Resources;
using Sedulous.Textures.Resources;

namespace Sedulous.Geometry.Tooling;

/// Converts ModelMaterial to MaterialResource.
static class MaterialConverter
{
	/// Creates a Materials.Resources.MaterialResource from a ModelMaterial.
	/// Uses the new Sedulous.Materials system.
	/// importedTextures contains already-imported TextureResources (with assigned GUIDs).
	public static Sedulous.Materials.Resources.MaterialResource ConvertToNew(ModelMaterial modelMat, Model model, List<TextureResource> importedTextures)
	{
		if (modelMat == null)
			return null;

		// Create PBR material
		let mat = Materials.CreatePBR(modelMat.Name, "forward");

		// Set PBR properties (names match Materials.CreatePBR)
		mat.SetDefaultFloat4("BaseColor", .(modelMat.BaseColorFactor.X, modelMat.BaseColorFactor.Y,
			modelMat.BaseColorFactor.Z, modelMat.BaseColorFactor.W));
		mat.SetDefaultFloat("Metallic", modelMat.MetallicFactor);
		mat.SetDefaultFloat("Roughness", modelMat.RoughnessFactor);
		mat.SetDefaultFloat4("EmissiveColor", .(modelMat.EmissiveFactor.X, modelMat.EmissiveFactor.Y,
			modelMat.EmissiveFactor.Z, 1.0f));
		mat.SetDefaultFloat("AlphaCutoff", modelMat.AlphaCutoff);

		// Set pipeline config based on alpha mode
		switch (modelMat.AlphaMode)
		{
		case .Opaque:
			mat.PipelineConfig.BlendMode = .Opaque;
			mat.PipelineConfig.DepthMode = .ReadWrite;
		case .Mask:
			mat.PipelineConfig.BlendMode = .Opaque;
			mat.PipelineConfig.DepthMode = .ReadWrite;
		case .Blend:
			mat.PipelineConfig.BlendMode = .AlphaBlend;
			mat.PipelineConfig.DepthMode = .ReadOnly;
		}

		mat.PipelineConfig.CullMode = modelMat.DoubleSided ? .None : .Back;

		// Create resource wrapper
		let matRes = new Sedulous.Materials.Resources.MaterialResource(mat, true);
		matRes.Name.Set(modelMat.Name);

		// Set texture references (names match Materials.CreatePBR)
		if (model != null)
		{
			SetNewTextureSlot(matRes, "AlbedoMap", model, modelMat.BaseColorTextureIndex, importedTextures);
			SetNewTextureSlot(matRes, "NormalMap", model, modelMat.NormalTextureIndex, importedTextures);
			SetNewTextureSlot(matRes, "MetallicRoughnessMap", model, modelMat.MetallicRoughnessTextureIndex, importedTextures);
			SetNewTextureSlot(matRes, "OcclusionMap", model, modelMat.OcclusionTextureIndex, importedTextures);
			SetNewTextureSlot(matRes, "EmissiveMap", model, modelMat.EmissiveTextureIndex, importedTextures);
		}

		return matRes;
	}

	/// Helper to set texture ResourceRef in new MaterialResource from model texture index.
	/// Uses the imported TextureResource's GUID and name to build the resource path.
	private static void SetNewTextureSlot(Sedulous.Materials.Resources.MaterialResource matRes, StringView slot, Model model, int32 textureIndex, List<TextureResource> importedTextures)
	{
		if (textureIndex >= 0 && textureIndex < model.Textures.Count)
		{
			// Use the imported TextureResource's name and GUID (the resource name
			// has already been stripped of the source file extension by TextureConverter)
			Guid texGuid = .();
			String texPath = scope .();
			if (importedTextures != null && textureIndex < importedTextures.Count)
			{
				let importedTex = importedTextures[textureIndex];
				texGuid = importedTex.Id;
				texPath.AppendF("{}.texture", importedTex.Name);
			}
			else
			{
				// Fallback when no imported textures available
				let tex = model.Textures[textureIndex];
				if (!tex.Name.IsEmpty)
					texPath.Set(tex.Name);
				else if (!tex.Uri.IsEmpty)
					texPath.Set(tex.Uri);
				else
					texPath.AppendF("texture_{}", textureIndex);
			}

			matRes.SetTextureRef(slot, ResourceRef(texGuid, texPath));
		}
	}
}
