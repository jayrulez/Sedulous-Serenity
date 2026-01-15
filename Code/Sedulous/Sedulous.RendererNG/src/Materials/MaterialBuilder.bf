namespace Sedulous.RendererNG;

using System;
using Sedulous.RHI;
using Sedulous.Mathematics;

/// Fluent builder for creating materials.
class MaterialBuilder
{
	private Material mMaterial;
	private uint32 mCurrentUniformOffset = 0;
	private uint32 mCurrentBinding = 0;

	/// Creates a new material builder.
	public this(StringView name)
	{
		mMaterial = new Material();
		mMaterial.Name.Set(name);
		mMaterial.PipelineConfig = PipelineConfig();
	}

	/// Sets the shader name.
	public Self Shader(StringView shaderName)
	{
		mMaterial.ShaderName.Set(shaderName);
		mMaterial.PipelineConfig.ShaderName = mMaterial.ShaderName;
		return this;
	}

	/// Sets shader variant flags.
	public Self Flags(ShaderFlags flags)
	{
		mMaterial.ShaderFlags = flags;
		mMaterial.PipelineConfig.ShaderFlags = flags;
		return this;
	}

	/// Sets the vertex layout.
	public Self VertexLayout(VertexLayoutType layout)
	{
		mMaterial.PipelineConfig.VertexLayout = layout;
		return this;
	}

	/// Sets the blend mode.
	public Self Blend(BlendMode mode)
	{
		mMaterial.PipelineConfig.BlendMode = mode;
		return this;
	}

	/// Sets the depth mode.
	public Self Depth(DepthMode mode)
	{
		mMaterial.PipelineConfig.DepthMode = mode;
		return this;
	}

	/// Sets the cull mode.
	public Self Cull(CullModeConfig mode)
	{
		mMaterial.PipelineConfig.CullMode = mode;
		return this;
	}

	/// Makes this material double-sided (no culling).
	public Self DoubleSided()
	{
		mMaterial.PipelineConfig.CullMode = .None;
		return this;
	}

	/// Makes this material transparent.
	public Self Transparent()
	{
		mMaterial.PipelineConfig.BlendMode = .AlphaBlend;
		mMaterial.PipelineConfig.DepthMode = .ReadOnly;
		return this;
	}

	/// Makes this material additive.
	public Self Additive()
	{
		mMaterial.PipelineConfig.BlendMode = .Additive;
		mMaterial.PipelineConfig.DepthMode = .ReadOnly;
		return this;
	}

	/// Adds a float property.
	public Self Float(StringView name, float defaultValue = 0)
	{
		let size = MaterialPropertyDef.GetSize(.Float);
		mMaterial.AddProperty(.(name, .Float, mCurrentBinding, mCurrentUniformOffset, size));
		mCurrentUniformOffset += size;
		mCurrentBinding++;

		mMaterial.AllocateDefaultUniformData();
		mMaterial.SetDefaultFloat(name, defaultValue);
		return this;
	}

	/// Adds a float2 property.
	public Self Float2(StringView name, Vector2 defaultValue = default)
	{
		let size = MaterialPropertyDef.GetSize(.Float2);
		mMaterial.AddProperty(.(name, .Float2, mCurrentBinding, mCurrentUniformOffset, size));
		mCurrentUniformOffset += size;
		mCurrentBinding++;

		mMaterial.AllocateDefaultUniformData();
		mMaterial.SetDefaultFloat2(name, defaultValue);
		return this;
	}

	/// Adds a float3 property.
	public Self Float3(StringView name, Vector3 defaultValue = default)
	{
		let size = MaterialPropertyDef.GetSize(.Float3);
		// Align to 16 bytes for float3 in std140
		mCurrentUniformOffset = (mCurrentUniformOffset + 15) & ~15;

		mMaterial.AddProperty(.(name, .Float3, mCurrentBinding, mCurrentUniformOffset, size));
		mCurrentUniformOffset += 16; // float3 takes 16 bytes due to alignment
		mCurrentBinding++;

		mMaterial.AllocateDefaultUniformData();
		mMaterial.SetDefaultFloat3(name, defaultValue);
		return this;
	}

	/// Adds a float4 property.
	public Self Float4(StringView name, Vector4 defaultValue = default)
	{
		let size = MaterialPropertyDef.GetSize(.Float4);
		// Align to 16 bytes
		mCurrentUniformOffset = (mCurrentUniformOffset + 15) & ~15;

		mMaterial.AddProperty(.(name, .Float4, mCurrentBinding, mCurrentUniformOffset, size));
		mCurrentUniformOffset += size;
		mCurrentBinding++;

		mMaterial.AllocateDefaultUniformData();
		mMaterial.SetDefaultFloat4(name, defaultValue);
		return this;
	}

	/// Adds a color property (float4 alias).
	public Self Color(StringView name, Vector4 defaultValue = .(1, 1, 1, 1))
	{
		return Float4(name, defaultValue);
	}

	/// Adds a texture property.
	public Self Texture(StringView name, ITextureView defaultTexture = null)
	{
		mMaterial.AddProperty(.(name, .Texture2D, mCurrentBinding, 0, 0));
		mCurrentBinding++;

		if (defaultTexture != null)
			mMaterial.SetDefaultTexture(name, defaultTexture);
		return this;
	}

	/// Adds a cube texture property.
	public Self TextureCube(StringView name, ITextureView defaultTexture = null)
	{
		mMaterial.AddProperty(.(name, .TextureCube, mCurrentBinding, 0, 0));
		mCurrentBinding++;

		if (defaultTexture != null)
			mMaterial.SetDefaultTexture(name, defaultTexture);
		return this;
	}

	/// Adds a sampler property.
	public Self Sampler(StringView name, ISampler defaultSampler = null)
	{
		mMaterial.AddProperty(.(name, .Sampler, mCurrentBinding, 0, 0));
		mCurrentBinding++;

		if (defaultSampler != null)
			mMaterial.SetDefaultSampler(name, defaultSampler);
		return this;
	}

	/// Builds and returns the material.
	/// Note: Caller takes ownership.
	public Material Build()
	{
		mMaterial.AllocateDefaultUniformData();
		let result = mMaterial;
		mMaterial = null;
		return result;
	}

	/// Destructor - cleans up if Build() was not called.
	public ~this()
	{
		if (mMaterial != null)
			delete mMaterial;
	}
}

/// Factory methods for common material types.
static class Materials
{
	/// Creates a basic PBR material.
	public static Material CreatePBR(StringView name, ITextureView defaultAlbedo = null, ISampler defaultSampler = null)
	{
		return scope MaterialBuilder(name)
			.Shader("pbr")
			.VertexLayout(.PositionNormalUVTangent)
			.Color("BaseColor", .(1, 1, 1, 1))
			.Float("Metallic", 0.0f)
			.Float("Roughness", 0.5f)
			.Float("AO", 1.0f)
			.Texture("AlbedoMap", defaultAlbedo)
			.Texture("NormalMap")
			.Texture("MetallicRoughnessMap")
			.Texture("OcclusionMap")
			.Texture("EmissiveMap")
			.Sampler("MainSampler", defaultSampler)
			.Build();
	}

	/// Creates a simple unlit material.
	public static Material CreateUnlit(StringView name, ITextureView defaultTexture = null, ISampler defaultSampler = null)
	{
		return scope MaterialBuilder(name)
			.Shader("unlit")
			.VertexLayout(.PositionNormalUV)
			.Color("Color", .(1, 1, 1, 1))
			.Texture("MainTexture", defaultTexture)
			.Sampler("MainSampler", defaultSampler)
			.Build();
	}

	/// Creates a skybox material.
	public static Material CreateSkybox(StringView name, ITextureView cubemap = null, ISampler sampler = null)
	{
		return scope MaterialBuilder(name)
			.Shader("skybox")
			.VertexLayout(.PositionOnly)
			.Depth(.ReadOnly)
			.Cull(.Front)
			.TextureCube("EnvironmentMap", cubemap)
			.Sampler("EnvironmentSampler", sampler)
			.Build();
	}

	/// Creates a sprite material.
	public static Material CreateSprite(StringView name, ITextureView texture = null, ISampler sampler = null)
	{
		return scope MaterialBuilder(name)
			.Shader("sprite")
			.VertexLayout(.PositionUVColor)
			.Transparent()
			.Cull(.None)
			.Texture("SpriteTexture", texture)
			.Sampler("SpriteSampler", sampler)
			.Build();
	}

	/// Creates a depth-only material for shadow passes.
	public static Material CreateShadow(StringView name)
	{
		var config = PipelineConfig.ForShadow("shadow");
		let builder = scope MaterialBuilder(name);
		builder.Shader("shadow");
		builder.VertexLayout(.PositionOnly);
		let mat = builder.Build();
		mat.PipelineConfig = config;
		return mat;
	}
}
