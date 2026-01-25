namespace Sedulous.Materials;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;

/// Manages materials, material instances, and their GPU resources.
/// Generates bind group layouts from material property definitions.
class MaterialSystem : IDisposable
{
	private IDevice mDevice;

	/// Bind group layout cache (keyed by layout hash).
	private Dictionary<int, IBindGroupLayout> mLayoutCache = new .() ~ {
		//for (let kv in _)
		//	delete kv.value;
		delete _;
	};

	/// Material uniform buffers (per material instance).
	private Dictionary<MaterialInstance, IBuffer> mUniformBuffers = new .() ~ {
		for (let kv in _)
			delete kv.value;
		delete _;
	};

	/// Material bind groups (per material instance).
	private Dictionary<MaterialInstance, IBindGroup> mBindGroups = new .() ~ {
		for (let kv in _)
			delete kv.value;
		delete _;
	};

	/// Default resources.
	private ISampler mDefaultSampler ~ delete _;
	private ITexture mWhiteTexture ~ delete _;
	private ITexture mNormalTexture ~ delete _;
	private ITexture mBlackTexture ~ delete _;
	private ITexture mDepthTexture ~ delete _;
	private ITextureView mWhiteTextureView ~ delete _;
	private ITextureView mNormalTextureView ~ delete _;
	private ITextureView mBlackTextureView ~ delete _;
	private ITextureView mDepthTextureView ~ delete _;

	/// Default PBR material (for meshes without assigned materials).
	private Material mDefaultMaterial ~ delete _;
	private MaterialInstance mDefaultMaterialInstance ~ delete _;

	/// Cached default material bind group layout (owned by mLayoutCache, not deleted here).
	private IBindGroupLayout mDefaultMaterialLayout;

	/// Gets the default sampler (linear, clamp).
	public ISampler DefaultSampler => mDefaultSampler;

	/// Gets the white 1x1 texture view.
	public ITextureView WhiteTexture => mWhiteTextureView;

	/// Gets the flat normal 1x1 texture view.
	public ITextureView NormalTexture => mNormalTextureView;

	/// Gets the black 1x1 texture view.
	public ITextureView BlackTexture => mBlackTextureView;

	/// Gets the depth 1x1 texture view (for shadow fallback).
	public ITextureView DepthTexture => mDepthTextureView;

	/// Gets the device.
	public IDevice Device => mDevice;

	/// Gets the default PBR material.
	public Material DefaultMaterial => mDefaultMaterial;

	/// Gets the default material instance.
	public MaterialInstance DefaultMaterialInstance => mDefaultMaterialInstance;

	/// Gets the default material bind group layout.
	public IBindGroupLayout DefaultMaterialLayout => mDefaultMaterialLayout;

	/// Initializes the material system.
	public Result<void> Initialize(IDevice device)
	{
		if (device == null)
			return .Err;

		mDevice = device;

		if (!CreateDefaultResources())
			return .Err;

		return .Ok;
	}

	/// Gets or creates a bind group layout for a material.
	/// Layout is inferred from the material's property definitions.
	public Result<IBindGroupLayout> GetOrCreateLayout(Material material)
	{
		if (material == null)
			return .Err;

		// Compute hash from material properties
		int layoutHash = ComputeLayoutHash(material);

		// Check cache
		if (mLayoutCache.TryGetValue(layoutHash, let cached))
			return cached;

		// Build layout entries from material properties
		List<BindGroupLayoutEntry> entries = scope .();

		// Check if we need a uniform buffer (any scalar properties)
		bool hasUniforms = false;
		for (let prop in material.Properties)
		{
			if (prop.IsUniform)
			{
				hasUniforms = true;
				break;
			}
		}

		// Add uniform buffer entry at binding 0 for material uniforms
		if (hasUniforms && material.UniformDataSize > 0)
			entries.Add(.UniformBuffer(0, .Fragment));

		// Track texture and sampler bindings
		int textureBinding = 0;
		int samplerBinding = 0;

		// Add texture/sampler entries
		for (let prop in material.Properties)
		{
			switch (prop.Type)
			{
			case .Texture2D, .TextureCube:
				// Textures start at binding 0 in the texture binding space
				entries.Add(.SampledTexture((uint32)textureBinding, .Fragment));
				textureBinding++;
			case .Sampler:
				entries.Add(.Sampler((uint32)samplerBinding, .Fragment));
				samplerBinding++;
			default:
				// Scalar params go in uniform buffer
			}
		}

		if (entries.Count == 0)
			return .Err;

		// Create layout
		Span<BindGroupLayoutEntry> entriesSpan = .(entries.Ptr, entries.Count);
		BindGroupLayoutDescriptor layoutDesc = .(entriesSpan);

		if (mDevice.CreateBindGroupLayout(&layoutDesc) case .Ok(let layout))
		{
			mLayoutCache[layoutHash] = layout;
			return layout;
		}

		return .Err;
	}

	/// Creates or updates a bind group for a material instance.
	/// Must call this before rendering with the material instance.
	public Result<IBindGroup> PrepareInstance(MaterialInstance instance, IBindGroupLayout layout = null)
	{
		if (instance == null || instance.Material == null)
			return .Err;

		let material = instance.Material;
		IBindGroupLayout bgLayout = layout;

		// Get or create layout if not provided
		if (bgLayout == null)
		{
			if (GetOrCreateLayout(material) case .Ok(let l))
				bgLayout = l;
			else
				return .Err;
		}

		// Create/update uniform buffer if dirty
		if (instance.IsUniformDirty && material.UniformDataSize > 0)
		{
			if (!UpdateUniformBuffer(instance))
				return .Err;
			instance.ClearUniformDirty();
		}

		// Create bind group if dirty
		if (instance.IsBindGroupDirty)
		{
			if (!UpdateBindGroup(instance, bgLayout))
				return .Err;
			instance.ClearBindGroupDirty();
		}

		// Return bind group
		if (mBindGroups.TryGetValue(instance, let bg))
			return bg;

		return .Err;
	}

	/// Gets the bind group for a material instance (returns null if not prepared).
	public IBindGroup GetBindGroup(MaterialInstance instance)
	{
		if (mBindGroups.TryGetValue(instance, let bg))
			return bg;
		return null;
	}

	/// Releases resources associated with a material instance.
	public void ReleaseInstance(MaterialInstance instance)
	{
		if (instance == null)
			return;

		if (mBindGroups.TryGetValue(instance, let bg))
		{
			delete bg;
			mBindGroups.Remove(instance);
		}

		if (mUniformBuffers.TryGetValue(instance, let buf))
		{
			delete buf;
			mUniformBuffers.Remove(instance);
		}
	}

	/// Clears all cached resources.
	public void ClearCache()
	{
		for (let kv in mBindGroups)
			delete kv.value;
		mBindGroups.Clear();

		for (let kv in mUniformBuffers)
			delete kv.value;
		mUniformBuffers.Clear();

		for (let kv in mLayoutCache)
			delete kv.value;
		mLayoutCache.Clear();
	}

	public void Dispose()
	{
		ClearCache();
	}

	// ===== Private Methods =====

	private bool CreateDefaultResources()
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
		else
			return false;

		// Create white 1x1 texture
		if (!CreateTexture1x1(.(255, 255, 255, 255), out mWhiteTexture, out mWhiteTextureView))
			return false;

		// Create flat normal 1x1 texture (0.5, 0.5, 1.0 = pointing up in tangent space)
		if (!CreateTexture1x1(.(128, 128, 255, 255), out mNormalTexture, out mNormalTextureView))
			return false;

		// Create black 1x1 texture
		if (!CreateTexture1x1(.(0, 0, 0, 255), out mBlackTexture, out mBlackTextureView))
			return false;

		// Create 1x1 depth texture (for shadow fallback with comparison sampler)
		if (!CreateDepthTexture1x1())
			return false;

		// Create default PBR material
		if (!CreateDefaultMaterial())
			return false;

		return true;
	}

	private bool CreateDefaultMaterial()
	{
		// Create the default PBR material with standard texture slots
		mDefaultMaterial = Materials.CreatePBR("DefaultPBR", "forward", mWhiteTextureView, mDefaultSampler);

		// Create an instance of the default material
		mDefaultMaterialInstance = new MaterialInstance(mDefaultMaterial);

		// Get/create the layout for the default material
		if (GetOrCreateLayout(mDefaultMaterial) case .Ok(let layout))
			mDefaultMaterialLayout = layout;
		else
			return false;

		// Prepare the default instance (creates bind group)
		if (PrepareInstance(mDefaultMaterialInstance, mDefaultMaterialLayout) case .Err)
			return false;

		return true;
	}

	private bool CreateTexture1x1(Color32 color, out ITexture texture, out ITextureView view)
	{
		texture = null;
		view = null;

		// Create texture descriptor
		var texDesc = TextureDescriptor.Texture2D(1, 1, .RGBA8Unorm, .Sampled | .CopyDst, 1);
		texDesc.Label = "1x1";

		if (mDevice.CreateTexture(&texDesc) case .Ok(let tex))
			texture = tex;
		else
			return false;

		// Upload pixel data
		uint8[4] data = .(color.R, color.G, color.B, color.A);
		var layout = TextureDataLayout()
		{
			BytesPerRow = 4,
			RowsPerImage = 1
		};
		var writeSize = Extent3D(1, 1, 1);

		mDevice.Queue.WriteTexture(texture, Span<uint8>(&data[0], 4), &layout, &writeSize);

		// Create view
		var viewDesc = TextureViewDescriptor()
		{
			Dimension = .Texture2D,
			Format = .RGBA8Unorm,
			BaseMipLevel = 0,
			MipLevelCount = 1,
			BaseArrayLayer = 0,
			ArrayLayerCount = 1,
			Label = "1x1View"
		};

		if (mDevice.CreateTextureView(texture, &viewDesc) case .Ok(let v))
			view = v;
		else
			return false;

		return true;
	}

	private bool CreateDepthTexture1x1()
	{
		// Create 1x1 depth texture for shadow comparison fallback
		// Use DepthStencil to allow clearing, Sampled to allow sampling
		var texDesc = TextureDescriptor.Texture2D(1, 1, .Depth32Float, .Sampled | .DepthStencil, 1);
		texDesc.Label = "Depth1x1";

		if (mDevice.CreateTexture(&texDesc) case .Ok(let tex))
			mDepthTexture = tex;
		else
			return false;

		// Create view with depth aspect
		var viewDesc = TextureViewDescriptor()
		{
			Dimension = .Texture2D,
			Format = .Depth32Float,
			BaseMipLevel = 0,
			MipLevelCount = 1,
			BaseArrayLayer = 0,
			ArrayLayerCount = 1,
			Aspect = .DepthOnly,
			Label = "Depth1x1View"
		};

		if (mDevice.CreateTextureView(mDepthTexture, &viewDesc) case .Ok(let v))
			mDepthTextureView = v;
		else
			return false;

		// Clear the texture to transition from UNDEFINED to SHADER_READ_ONLY
		// by doing a dummy render pass with depth clear
		ClearDepthTexture();

		return true;
	}

	private void ClearDepthTexture()
	{
		// Get a command encoder to clear the texture
		if (let encoder = mDevice.CreateCommandEncoder())
		{
			// Create a render pass that clears depth
			RenderPassDepthStencilAttachment depthAttachment = .()
			{
				View = mDepthTextureView,
				DepthLoadOp = .Clear,
				DepthStoreOp = .Store,
				DepthClearValue = 1.0f,
				StencilLoadOp = .Clear,
				StencilStoreOp = .Store,
				StencilClearValue = 0
			};

			RenderPassDescriptor rpDesc = .()
			{
				DepthStencilAttachment = depthAttachment
			};

			if (let pass = encoder.BeginRenderPass(&rpDesc))
			{
				pass.End();
				delete pass;
			}

			// Transition from DepthStencilAttachment to ShaderReadOnly for sampling
			encoder.TextureBarrier(mDepthTexture, .DepthStencilAttachment, .ShaderReadOnly);

			// Submit the command buffer
			if (let cmdBuffer = encoder.Finish())
			{
				mDevice.Queue.Submit(cmdBuffer);
				mDevice.WaitIdle(); // Wait for completion before continuing
				delete cmdBuffer;
			}

			delete encoder;
		}
	}

	private int ComputeLayoutHash(Material material)
	{
		int hash = 17;

		// Include uniform buffer size
		hash = hash * 31 + (int)material.UniformDataSize;

		// Include each property type
		for (let prop in material.Properties)
		{
			hash = hash * 31 + (int)prop.Type;
			hash = hash * 31 + (int)prop.Binding;
		}

		return hash;
	}

	private bool UpdateUniformBuffer(MaterialInstance instance)
	{
		let material = instance.Material;
		if (material.UniformDataSize == 0)
			return true;

		IBuffer buffer = null;

		// Create buffer if doesn't exist
		if (!mUniformBuffers.TryGetValue(instance, out buffer))
		{
			BufferDescriptor bufDesc = .(material.UniformDataSize, .Uniform | .CopyDst);
			if (mDevice.CreateBuffer(&bufDesc) case .Ok(let buf))
			{
				buffer = buf;
				mUniformBuffers[instance] = buffer;
			}
			else
				return false;
		}

		// Upload uniform data
		let data = instance.UniformData;
		if (data.Length > 0)
			mDevice.Queue.WriteBuffer(buffer, 0, data);

		return true;
	}

	private bool UpdateBindGroup(MaterialInstance instance, IBindGroupLayout layout)
	{
		let material = instance.Material;
		List<BindGroupEntry> entries = scope .();

		// Add uniform buffer if present
		if (mUniformBuffers.TryGetValue(instance, let buffer))
			entries.Add(.Buffer(0, buffer, 0, material.UniformDataSize));

		// Add textures and samplers
		int textureBinding = 0;
		int samplerBinding = 0;
		int propIndex = 0;

		for (let prop in material.Properties)
		{
			switch (prop.Type)
			{
			case .Texture2D, .TextureCube:
				var view = instance.GetTexture(propIndex);

				// Use appropriate default if not set
				if (view == null)
				{
					if (prop.Name.Contains("normal", true) || prop.Name.Contains("Normal", true))
						view = mNormalTextureView;
					else if (prop.Name.Contains("emissive", true) || prop.Name.Contains("Emissive", true))
						view = mBlackTextureView;
					else
						view = mWhiteTextureView;
				}

				if (view != null)
					entries.Add(.Texture((uint32)textureBinding, view));

				textureBinding++;

			case .Sampler:
				var sampler = instance.GetSampler(propIndex);
				if (sampler == null)
					sampler = mDefaultSampler;

				if (sampler != null)
					entries.Add(.Sampler((uint32)samplerBinding, sampler));

				samplerBinding++;

			default:
				// Scalar params in uniform buffer
			}

			propIndex++;
		}

		if (entries.Count == 0)
			return false;

		// Delete old bind group
		if (mBindGroups.TryGetValue(instance, let oldBg))
		{
			delete oldBg;
			mBindGroups.Remove(instance);
		}

		// Create new bind group
		Span<BindGroupEntry> entriesSpan = .(entries.Ptr, entries.Count);
		BindGroupDescriptor bgDesc = .(layout, entriesSpan);

		if (mDevice.CreateBindGroup(&bgDesc) case .Ok(let bg))
		{
			mBindGroups[instance] = bg;
			return true;
		}

		return false;
	}
}

/// RGBA8 color for texture data.
[Packed, CRepr]
struct Color32
{
	public uint8 R, G, B, A;

	public this(uint8 r, uint8 g, uint8 b, uint8 a)
	{
		R = r;
		G = g;
		B = b;
		A = a;
	}
}
