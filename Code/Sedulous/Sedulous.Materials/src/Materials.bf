using Sedulous.RHI;
using System;
namespace Sedulous.Materials;

/// Factory methods for common material types.
static class Materials
{
	/// Creates a basic PBR material.
	public static Material CreatePBR(StringView name, String shaderName = null, ITextureView defaultAlbedo = null, ISampler defaultSampler = null)
	{
		return scope MaterialBuilder(name)
			.Shader(shaderName ?? "pbr")
			.VertexLayout(.Mesh)
			.Color("BaseColor", .(1, 1, 1, 1))
			.Float("Metallic", 0.0f)
			.Float("Roughness", 0.5f)
			.Float("AO", 1.0f)
			.Float("AlphaCutoff", 0.0f)
			.Color("EmissiveColor", .(0, 0, 0, 1))
			.Texture("AlbedoMap", defaultAlbedo)
			.Texture("NormalMap")
			.Texture("MetallicRoughnessMap")
			.Texture("OcclusionMap")
			.Texture("EmissiveMap")
			.Sampler("MainSampler", defaultSampler)
			.Build();
	}

	/// Creates a simple unlit material.
	public static Material CreateUnlit(StringView name, String shaderName = null, ITextureView defaultTexture = null, ISampler defaultSampler = null)
	{
		return scope MaterialBuilder(name)
			.Shader(shaderName ?? "unlit")
			.VertexLayout(.Mesh)
			.Color("Color", .(1, 1, 1, 1))
			.Texture("MainTexture", defaultTexture)
			.Sampler("MainSampler", defaultSampler)
			.Build();
	}

	/// Creates a skybox material.
	public static Material CreateSkybox(StringView name, String shaderName = null, ITextureView cubemap = null, ISampler sampler = null)
	{
		return scope MaterialBuilder(name)
			.Shader(shaderName ?? "skybox")
			.VertexLayout(.PositionOnly)
			.Depth(.ReadOnly)
			.Cull(.Front)
			.TextureCube("EnvironmentMap", cubemap)
			.Sampler("EnvironmentSampler", sampler)
			.Build();
	}

	/// Creates a sprite material.
	public static Material CreateSprite(StringView name, String shaderName = null, ITextureView texture = null, ISampler sampler = null)
	{
		return scope MaterialBuilder(name)
			.Shader(shaderName ?? "sprite")
			.VertexLayout(.PositionUVColor)
			.Transparent()
			.Cull(.None)
			.Texture("SpriteTexture", texture)
			.Sampler("SpriteSampler", sampler)
			.Build();
	}

	/// Creates a depth-only material for shadow passes.
	public static Material CreateShadow(StringView name, String shaderName = null)
	{
		var config = PipelineConfig.ForShadow("shadow");
		let builder = scope MaterialBuilder(name);
		builder.Shader(shaderName ?? "shadow");
		builder.VertexLayout(.PositionOnly);
		let mat = builder.Build();
		mat.PipelineConfig = config;
		return mat;
	}
}