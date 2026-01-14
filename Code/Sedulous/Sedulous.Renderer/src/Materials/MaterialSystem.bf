namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Shaders;
using Sedulous.Mathematics;

/// Manages materials and material instances for rendering.
/// Provides bind group layout caching and default resources.
class MaterialSystem
{
	private IDevice mDevice;
	private ShaderLibrary mShaderLibrary;
	private GPUResourceManager mResourceManager;

	// Material storage
	private List<Material> mMaterials = new .() ~ DeleteContainerAndItems!(_);
	private List<uint32> mMaterialGenerations = new .() ~ delete _;
	private List<uint32> mFreeMaterialSlots = new .() ~ delete _;

	// Instance storage
	private List<MaterialInstance> mInstances = new .() ~ DeleteContainerAndItems!(_);
	private List<uint32> mInstanceGenerations = new .() ~ delete _;
	private List<uint32> mFreeInstanceSlots = new .() ~ delete _;

	// Cached bind group layouts (keyed by layout hash)
	private Dictionary<int, IBindGroupLayout> mBindGroupLayoutCache = new .() ~ DeleteDictionaryAndValues!(_);

	// Default resources
	private ISampler mDefaultSampler ~ delete _;
	private GPUTextureHandle mWhiteTexture = .Invalid;
	private GPUTextureHandle mNormalTexture = .Invalid;
	private GPUTextureHandle mBlackTexture = .Invalid;

	/// Gets the default sampler (linear filtering, clamp).
	public ISampler DefaultSampler => mDefaultSampler;

	/// Gets the white 1x1 texture (255, 255, 255, 255).
	public GPUTextureHandle WhiteTexture => mWhiteTexture;

	/// Gets the flat normal 1x1 texture (128, 128, 255, 255).
	public GPUTextureHandle NormalTexture => mNormalTexture;

	/// Gets the black 1x1 texture (0, 0, 0, 255).
	public GPUTextureHandle BlackTexture => mBlackTexture;

	/// Gets the shader library.
	public ShaderLibrary ShaderLibrary => mShaderLibrary;

	/// Gets the resource manager.
	public GPUResourceManager ResourceManager => mResourceManager;

	/// Gets the device.
	public IDevice Device => mDevice;

	public this(IDevice device, ShaderLibrary shaderLibrary, GPUResourceManager resourceManager)
	{
		mDevice = device;
		mShaderLibrary = shaderLibrary;
		mResourceManager = resourceManager;

		CreateDefaultResources();
	}

	/// Creates a material from a Material object.
	/// Takes ownership of the material.
	public MaterialHandle RegisterMaterial(Material material)
	{
		if (material == null)
			return .Invalid;

		return AllocateMaterialSlot(material);
	}

	/// Creates a material instance from a material handle.
	public MaterialInstanceHandle CreateInstance(MaterialHandle materialHandle)
	{
		let material = GetMaterial(materialHandle);
		if (material == null)
			return .Invalid;

		let instance = new MaterialInstance(material);

		// Initialize GPU resources
		let layout = GetOrCreateBindGroupLayout(material);
		if (layout != null)
		{
			instance.Initialize(mDevice, layout);
		}

		return AllocateInstanceSlot(instance);
	}

	/// Gets a material by handle.
	public Material GetMaterial(MaterialHandle handle)
	{
		if (!handle.IsValid || handle.Index >= mMaterials.Count)
			return null;

		if (mMaterialGenerations[(int)handle.Index] != handle.Generation)
			return null;

		return mMaterials[(int)handle.Index];
	}

	/// Gets a material instance by handle.
	public MaterialInstance GetInstance(MaterialInstanceHandle handle)
	{
		if (!handle.IsValid || handle.Index >= mInstances.Count)
			return null;

		if (mInstanceGenerations[(int)handle.Index] != handle.Generation)
			return null;

		return mInstances[(int)handle.Index];
	}

	/// Releases a material handle.
	public void ReleaseMaterial(MaterialHandle handle)
	{
		if (handle.IsValid && handle.Index < mMaterials.Count)
		{
			if (mMaterialGenerations[(int)handle.Index] == handle.Generation)
			{
				FreeMaterialSlot(handle.Index);
			}
		}
	}

	/// Releases a material instance handle.
	public void ReleaseInstance(MaterialInstanceHandle handle)
	{
		if (handle.IsValid && handle.Index < mInstances.Count)
		{
			if (mInstanceGenerations[(int)handle.Index] == handle.Generation)
			{
				FreeInstanceSlot(handle.Index);
			}
		}
	}

	/// Gets or creates a bind group layout for a material.
	/// The layout is inferred from the material's parameter declarations.
	public IBindGroupLayout GetOrCreateBindGroupLayout(Material material)
	{
		if (material == null)
			return null;

		// Compute hash from material's parameter declarations
		int layoutHash = ComputeLayoutHash(material);

		// Check cache
		if (mBindGroupLayoutCache.TryGetValue(layoutHash, let cached))
			return cached;

		// Build layout entries from Material.Parameters
		List<BindGroupLayoutEntry> entries = scope .();

		// Add uniform buffer if material has scalar parameters
		if (material.UniformBufferSize > 0)
		{
			// Find the uniform buffer binding from scalar parameters
			uint32 uniformBinding = 1; // Default to b1 for material uniforms
			for (let param in material.Parameters)
			{
				if (param.Type != .Texture2D && param.Type != .Sampler)
				{
					uniformBinding = param.Binding;
					break;
				}
			}
			entries.Add(.UniformBuffer(uniformBinding, .Fragment));
		}

		// Add texture/sampler entries from parameters
		for (let param in material.Parameters)
		{
			switch (param.Type)
			{
			case .Texture2D:
				entries.Add(.SampledTexture(param.Binding, .Fragment));
			case .Sampler:
				entries.Add(.Sampler(param.Binding, .Fragment));
			default:
				// Scalar params go in uniform buffer, already handled
			}
		}

		if (entries.Count == 0)
			return null;

		// Create and cache
		Span<BindGroupLayoutEntry> entriesSpan = .(entries.Ptr, entries.Count);
		BindGroupLayoutDescriptor layoutDesc = .(entriesSpan);
		if (mDevice.CreateBindGroupLayout(&layoutDesc) case .Ok(let layout))
		{
			mBindGroupLayoutCache[layoutHash] = layout;
			return layout;
		}

		return null;
	}

	/// Creates a bind group for a material instance.
	/// Uses the material's bind group layout and the instance's resources.
	public IBindGroup CreateBindGroup(MaterialInstance instance, IBindGroupLayout layout)
	{
		if (instance == null || layout == null)
			return null;

		let material = instance.BaseMaterial;
		List<BindGroupEntry> entries = scope .();

		// Add uniform buffer if present
		if (instance.UniformBuffer != null)
		{
			// Find the uniform buffer binding
			uint32 uniformBinding = 1;
			for (let param in material.Parameters)
			{
				if (param.Type != .Texture2D && param.Type != .Sampler)
				{
					uniformBinding = param.Binding;
					break;
				}
			}
			entries.Add(.Buffer(uniformBinding, instance.UniformBuffer, 0, material.UniformBufferSize));
		}

		// Add textures and samplers
		for (let param in material.Parameters)
		{
			switch (param.Type)
			{
			case .Texture2D:
				let texHandle = instance.GetTexture(param.Binding);
				ITextureView view = null;

				if (texHandle.IsValid)
				{
					if (let gpuTex = mResourceManager.GetTexture(texHandle))
						view = gpuTex.View;
				}

				// Use default texture if not set
				if (view == null)
				{
					GPUTextureHandle defaultHandle = .Invalid;

					// Choose appropriate default based on parameter name
					// Normal maps default to flat normal (128, 128, 255)
					// Emissive maps default to black (additive, no emission)
					// Metallic/roughness/AO maps default to WHITE so uniform values pass through
					// (shader multiplies texture sample * uniform value)
					if (param.Name.Contains("normal", true))
						defaultHandle = mNormalTexture;
					else if (param.Name.Contains("emissive", true))
						defaultHandle = mBlackTexture;
					else
						defaultHandle = mWhiteTexture;

					if (let gpuTex = mResourceManager.GetTexture(defaultHandle))
						view = gpuTex.View;
				}

				if (view != null)
					entries.Add(.Texture(param.Binding, view));

			case .Sampler:
				var sampler = instance.GetSampler(param.Binding);
				if (sampler == null)
					sampler = mDefaultSampler;
				if (sampler != null)
					entries.Add(.Sampler(param.Binding, sampler));

			default:
				// Scalar params in uniform buffer, already handled
			}
		}

		if (entries.Count == 0)
			return null;

		Span<BindGroupEntry> entriesSpan = .(entries.Ptr, entries.Count);
		BindGroupDescriptor bgDesc = .(layout, entriesSpan);
		if (mDevice.CreateBindGroup(&bgDesc) case .Ok(let bindGroup))
			return bindGroup;

		return null;
	}

	/// Uploads material instance uniform data and creates/updates bind group.
	public void UploadInstance(MaterialInstanceHandle handle)
	{
		let instance = GetInstance(handle);
		if (instance == null)
			return;

		// Upload uniform data
		instance.Upload(mDevice.Queue);

		// Create bind group if needed
		if (instance.BindGroup == null)
		{
			let layout = GetOrCreateBindGroupLayout(instance.BaseMaterial);
			if (layout != null)
			{
				let bindGroup = CreateBindGroup(instance, layout);
				if (bindGroup != null)
				{
					if (instance.BindGroup != null)
						delete instance.BindGroup;
					instance.BindGroup = bindGroup;
				}
			}
		}
	}

	// ===== Private Methods =====

	private void CreateDefaultResources()
	{
		// Create default sampler (linear, clamp)
		SamplerDescriptor samplerDesc = .();
		samplerDesc.AddressModeU = .ClampToEdge;
		samplerDesc.AddressModeV = .ClampToEdge;
		samplerDesc.AddressModeW = .ClampToEdge;
		samplerDesc.MinFilter = .Linear;
		samplerDesc.MagFilter = .Linear;
		samplerDesc.MipmapFilter = .Linear;

		if (mDevice.CreateSampler(&samplerDesc) case .Ok(let sampler))
			mDefaultSampler = sampler;

		// Create white 1x1 texture
		uint8[4] whiteData = .(255, 255, 255, 255);
		mWhiteTexture = mResourceManager.CreateTextureFromData(1, 1, .RGBA8Unorm, .(&whiteData[0], 4));

		// Create flat normal 1x1 texture (0.5, 0.5, 1.0 in tangent space)
		uint8[4] normalData = .(128, 128, 255, 255);
		mNormalTexture = mResourceManager.CreateTextureFromData(1, 1, .RGBA8Unorm, .(&normalData[0], 4));

		// Create black 1x1 texture
		uint8[4] blackData = .(0, 0, 0, 255);
		mBlackTexture = mResourceManager.CreateTextureFromData(1, 1, .RGBA8Unorm, .(&blackData[0], 4));
	}

	private int ComputeLayoutHash(Material material)
	{
		int hash = 17;

		// Include uniform buffer size
		hash = hash * 31 + (int)material.UniformBufferSize;

		// Include each parameter's type and binding
		for (let param in material.Parameters)
		{
			hash = hash * 31 + (int)param.Type;
			hash = hash * 31 + (int)param.Binding;
		}

		return hash;
	}

	private MaterialHandle AllocateMaterialSlot(Material material)
	{
		uint32 index;
		uint32 generation;

		if (mFreeMaterialSlots.Count > 0)
		{
			index = mFreeMaterialSlots.PopBack();
			generation = mMaterialGenerations[(int)index];
			mMaterials[(int)index] = material;
		}
		else
		{
			index = (uint32)mMaterials.Count;
			generation = 0;
			mMaterials.Add(material);
			mMaterialGenerations.Add(generation);
		}

		return .(index, generation);
	}

	private void FreeMaterialSlot(uint32 index)
	{
		if (index < mMaterials.Count)
		{
			delete mMaterials[(int)index];
			mMaterials[(int)index] = null;
			mMaterialGenerations[(int)index]++;
			mFreeMaterialSlots.Add(index);
		}
	}

	private MaterialInstanceHandle AllocateInstanceSlot(MaterialInstance instance)
	{
		uint32 index;
		uint32 generation;

		if (mFreeInstanceSlots.Count > 0)
		{
			index = mFreeInstanceSlots.PopBack();
			generation = mInstanceGenerations[(int)index];
			mInstances[(int)index] = instance;
		}
		else
		{
			index = (uint32)mInstances.Count;
			generation = 0;
			mInstances.Add(instance);
			mInstanceGenerations.Add(generation);
		}

		return .(index, generation);
	}

	private void FreeInstanceSlot(uint32 index)
	{
		if (index < mInstances.Count)
		{
			delete mInstances[(int)index];
			mInstances[(int)index] = null;
			mInstanceGenerations[(int)index]++;
			mFreeInstanceSlots.Add(index);
		}
	}
}
