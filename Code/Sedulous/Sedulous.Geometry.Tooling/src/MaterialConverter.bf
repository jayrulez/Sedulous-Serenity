using System;
using System.Collections;
using Sedulous.Models;
using Sedulous.Mathematics;
using Sedulous.Engine.Renderer;

namespace Sedulous.Geometry.Tooling;

/// Converts ModelMaterial to MaterialResource.
static class MaterialConverter
{
	/// Creates a MaterialResource from a ModelMaterial.
	/// Texture paths are set based on the model's texture list.
	public static MaterialResource Convert(ModelMaterial modelMat, Model model)
	{
		if (modelMat == null)
			return null;

		let matRes = new MaterialResource(.PBR);
		matRes.Name.Set(modelMat.Name);

		// Copy PBR properties
		matRes.BaseColor = .(modelMat.BaseColorFactor.X, modelMat.BaseColorFactor.Y,
			modelMat.BaseColorFactor.Z, modelMat.BaseColorFactor.W);
		matRes.Metallic = modelMat.MetallicFactor;
		matRes.Roughness = modelMat.RoughnessFactor;
		matRes.EmissiveFactor = .(modelMat.EmissiveFactor.X, modelMat.EmissiveFactor.Y,
			modelMat.EmissiveFactor.Z);
		matRes.DoubleSided = modelMat.DoubleSided;
		matRes.AlphaCutoff = modelMat.AlphaCutoff;

		// Map alpha mode
		matRes.AlphaMode = modelMat.AlphaMode == .Opaque ? .Opaque :
			(modelMat.AlphaMode == .Mask ? .Mask : .Blend);

		// Set texture references (using slot names from Material.CreatePBR)
		if (model != null)
		{
			SetTextureSlot(matRes, "albedoMap", model, modelMat.BaseColorTextureIndex);
			SetTextureSlot(matRes, "normalMap", model, modelMat.NormalTextureIndex);
			SetTextureSlot(matRes, "metallicRoughnessMap", model, modelMat.MetallicRoughnessTextureIndex);
			SetTextureSlot(matRes, "aoMap", model, modelMat.OcclusionTextureIndex);
			SetTextureSlot(matRes, "emissiveMap", model, modelMat.EmissiveTextureIndex);
		}

		return matRes;
	}

	/// Helper to set texture slot in MaterialResource from model texture index.
	private static void SetTextureSlot(MaterialResource matRes, StringView slot, Model model, int32 textureIndex)
	{
		if (textureIndex >= 0 && textureIndex < model.Textures.Count)
		{
			let tex = model.Textures[textureIndex];
			// Use texture name, falling back to URI, falling back to index
			String texPath = scope .();
			if (!tex.Name.IsEmpty)
				texPath.Set(tex.Name);
			else if (!tex.Uri.IsEmpty)
				texPath.Set(tex.Uri);
			else
				texPath.Set(scope $"texture_{textureIndex}");

			matRes.SetTexture(slot, texPath);
		}
	}
}
