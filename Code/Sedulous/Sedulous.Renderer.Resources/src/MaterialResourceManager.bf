using System;
using System.IO;
using Sedulous.Resources;
using Sedulous.Mathematics;

namespace Sedulous.Renderer.Resources;

/// Resource manager for MaterialResource.
class MaterialResourceManager : ResourceManager<MaterialResource>
{
	private MaterialResource mDefaultMaterial ~ delete _;

	/// Gets the default material (white, non-metallic).
	public MaterialResource DefaultMaterial
	{
		get
		{
			if (mDefaultMaterial == null)
			{
				mDefaultMaterial = MaterialResource.CreateDefault("__default__");
			}
			return mDefaultMaterial;
		}
	}

	protected override Result<MaterialResource, ResourceLoadError> LoadFromFile(StringView path)
	{
		// Material loading from file would use ResourceSerializer
		// For now, not directly supported - use explicit loading via Geometry.Tooling
		return .Err(.NotSupported);
	}

	protected override Result<MaterialResource, ResourceLoadError> LoadFromMemory(MemoryStream memory)
	{
		// Not implemented - use explicit material creation or ResourceSerializer
		return .Err(.NotSupported);
	}

	public override void Unload(MaterialResource resource)
	{
		if (resource != null)
			resource.ReleaseRef();
	}

	/// Registers a pre-created material resource.
	public ResourceHandle<MaterialResource> Register(MaterialResource resource)
	{
		resource.AddRef();
		return .(resource);
	}

	/// Creates and registers a default PBR material.
	public ResourceHandle<MaterialResource> CreateDefault(StringView name)
	{
		let material = MaterialResource.CreateDefault(name);
		return Register(material);
	}

	/// Creates and registers a metallic material.
	public ResourceHandle<MaterialResource> CreateMetallic(StringView name, Vector4 color, float roughness = 0.3f)
	{
		let material = MaterialResource.CreateMetallic(name, color, roughness);
		return Register(material);
	}

	/// Creates and registers a dielectric (non-metallic) material.
	public ResourceHandle<MaterialResource> CreateDielectric(StringView name, Vector4 color, float roughness = 0.5f)
	{
		let material = MaterialResource.CreateDielectric(name, color, roughness);
		return Register(material);
	}

	/// Creates and registers an emissive material.
	public ResourceHandle<MaterialResource> CreateEmissive(StringView name, Vector3 emissiveColor, float strength = 1.0f)
	{
		let material = MaterialResource.CreateEmissive(name, emissiveColor, strength);
		return Register(material);
	}
}
