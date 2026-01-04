namespace Sedulous.Framework.Renderer;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;

/// A material instance holds per-object parameter values.
/// Multiple instances can share the same base Material.
class MaterialInstance
{
	/// The base material.
	public Material BaseMaterial;

	/// Uniform buffer for scalar parameters.
	public IBuffer UniformBuffer ~ delete _;

	/// Bind group for this instance's resources.
	public IBindGroup BindGroup ~ delete _;

	/// Raw uniform data.
	private uint8[] mUniformData ~ delete _;

	/// Texture bindings.
	private Dictionary<uint32, GPUTextureHandle> mTextures = new .() ~ delete _;

	/// Sampler bindings.
	private Dictionary<uint32, ISampler> mSamplers = new .() ~ delete _;

	/// Whether uniform data needs to be uploaded.
	private bool mDirty = true;

	public this(Material material)
	{
		BaseMaterial = material;

		if (material.UniformBufferSize > 0)
		{
			mUniformData = new uint8[material.UniformBufferSize];
			Internal.MemSet(mUniformData.Ptr, 0, mUniformData.Count);
		}
	}

	/// Creates the GPU resources for this instance.
	public bool Initialize(IDevice device, IBindGroupLayout layout)
	{
		// Create uniform buffer if needed
		if (BaseMaterial.UniformBufferSize > 0 && mUniformData != null)
		{
			BufferDescriptor bufDesc = .(BaseMaterial.UniformBufferSize, .Uniform, .Upload);
			if (device.CreateBuffer(&bufDesc) case .Ok(let buf))
			{
				UniformBuffer = buf;
			}
			else
			{
				return false;
			}
		}

		return true;
	}

	/// Sets a float parameter.
	public void SetFloat(StringView name, float value)
	{
		let param = FindParam(name);
		if (param != null && param.Type == .Float && mUniformData != null)
		{
			var val = value;
			Internal.MemCpy(&mUniformData[param.Offset], &val, sizeof(float));
			mDirty = true;
		}
	}

	/// Sets a float2 parameter.
	public void SetFloat2(StringView name, Vector2 value)
	{
		let param = FindParam(name);
		if (param != null && param.Type == .Float2 && mUniformData != null)
		{
			var val = value;
			Internal.MemCpy(&mUniformData[param.Offset], &val, sizeof(Vector2));
			mDirty = true;
		}
	}

	/// Sets a float3 parameter.
	public void SetFloat3(StringView name, Vector3 value)
	{
		let param = FindParam(name);
		if (param != null && param.Type == .Float3 && mUniformData != null)
		{
			var val = value;
			Internal.MemCpy(&mUniformData[param.Offset], &val, sizeof(Vector3));
			mDirty = true;
		}
	}

	/// Sets a float4/color parameter.
	public void SetFloat4(StringView name, Vector4 value)
	{
		let param = FindParam(name);
		if (param != null && param.Type == .Float4 && mUniformData != null)
		{
			var val = value;
			Internal.MemCpy(&mUniformData[param.Offset], &val, sizeof(Vector4));
			mDirty = true;
		}
	}

	/// Sets a color parameter (from Color).
	public void SetColor(StringView name, Color color)
	{
		SetFloat4(name, color.ToVector4());
	}

	/// Sets a matrix parameter.
	public void SetMatrix(StringView name, Matrix value)
	{
		let param = FindParam(name);
		if (param != null && param.Type == .Matrix4x4 && mUniformData != null)
		{
			var val = value;
			Internal.MemCpy(&mUniformData[param.Offset], &val, sizeof(Matrix));
			mDirty = true;
		}
	}

	/// Sets a texture parameter.
	public void SetTexture(StringView name, GPUTextureHandle texture)
	{
		let param = FindParam(name);
		if (param != null && param.Type == .Texture2D)
		{
			mTextures[param.Binding] = texture;
		}
	}

	/// Sets a sampler parameter.
	public void SetSampler(StringView name, ISampler sampler)
	{
		let param = FindParam(name);
		if (param != null && param.Type == .Sampler)
		{
			mSamplers[param.Binding] = sampler;
		}
	}

	/// Gets a texture binding.
	public GPUTextureHandle GetTexture(uint32 binding)
	{
		if (mTextures.TryGetValue(binding, let tex))
			return tex;
		return .Invalid;
	}

	/// Gets a sampler binding.
	public ISampler GetSampler(uint32 binding)
	{
		if (mSamplers.TryGetValue(binding, let sampler))
			return sampler;
		return null;
	}

	/// Uploads uniform data to GPU if dirty.
	public void Upload(IQueue queue)
	{
		if (mDirty && UniformBuffer != null && mUniformData != null)
		{
			Span<uint8> data = .(mUniformData.Ptr, mUniformData.Count);
			queue.WriteBuffer(UniformBuffer, 0, data);
			mDirty = false;
		}
	}

	/// Finds a parameter by name.
	private MaterialParameterDesc FindParam(StringView name)
	{
		for (let param in BaseMaterial.Parameters)
		{
			if (param.Name == name)
				return param;
		}
		return null;
	}
}

/// Handle to a material instance.
struct MaterialInstanceHandle : IEquatable<MaterialInstanceHandle>, IHashable
{
	private uint32 mIndex;
	private uint32 mGeneration;

	public static readonly Self Invalid = .((uint32)-1, 0);

	public uint32 Index => mIndex;
	public uint32 Generation => mGeneration;
	public bool IsValid => mIndex != (uint32)-1;

	public this(uint32 index, uint32 generation)
	{
		mIndex = index;
		mGeneration = generation;
	}

	public bool Equals(MaterialInstanceHandle other)
	{
		return mIndex == other.mIndex && mGeneration == other.mGeneration;
	}

	public int GetHashCode()
	{
		return (int)(mIndex ^ (mGeneration << 16));
	}
}
