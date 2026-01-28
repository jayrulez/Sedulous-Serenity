using System;
using System.Collections;
using Sedulous.Models;
using Sedulous.Mathematics;
using Sedulous.Materials;

namespace Sedulous.Geometry.Tooling;

/// Converts ModelMaterial to MaterialResource.
static class MaterialConverter
{
	/// Creates a Renderer.MaterialResource from a ModelMaterial (legacy).
	/// Texture paths are set based on the model's texture list.
	public static Sedulous.Renderer.MaterialResource Convert(ModelMaterial modelMat, Model model)
	{
		if (modelMat == null)
			return null;

		let matRes = new Sedulous.Renderer.MaterialResource(.PBR);
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

	/// Helper to set texture slot in legacy MaterialResource from model texture index.
	private static void SetTextureSlot(Sedulous.Renderer.MaterialResource matRes, StringView slot, Model model, int32 textureIndex)
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

	/// Creates a Materials.Resources.MaterialResource from a ModelMaterial.
	/// Uses the new Sedulous.Materials system.
	public static Sedulous.Materials.Resources.MaterialResource ConvertToNew(ModelMaterial modelMat, Model model)
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

		// Set texture paths (names match Materials.CreatePBR)
		if (model != null)
		{
			SetNewTextureSlot(matRes, "AlbedoMap", model, modelMat.BaseColorTextureIndex);
			SetNewTextureSlot(matRes, "NormalMap", model, modelMat.NormalTextureIndex);
			SetNewTextureSlot(matRes, "MetallicRoughnessMap", model, modelMat.MetallicRoughnessTextureIndex);
			SetNewTextureSlot(matRes, "OcclusionMap", model, modelMat.OcclusionTextureIndex);
			SetNewTextureSlot(matRes, "EmissiveMap", model, modelMat.EmissiveTextureIndex);
		}

		return matRes;
	}

	/// Helper to set texture path in new MaterialResource from model texture index.
	private static void SetNewTextureSlot(Sedulous.Materials.Resources.MaterialResource matRes, StringView slot, Model model, int32 textureIndex)
	{
		if (textureIndex >= 0 && textureIndex < model.Textures.Count)
		{
			let tex = model.Textures[textureIndex];
			String texPath = scope .();
			if (!tex.Name.IsEmpty)
				texPath.Set(tex.Name);
			else if (!tex.Uri.IsEmpty)
				texPath.Set(tex.Uri);
			else
				texPath.Set(scope $"texture_{textureIndex}");

			matRes.SetTexturePath(slot, texPath);
		}
	}
}
