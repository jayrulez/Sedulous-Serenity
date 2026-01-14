namespace Sedulous.RendererNext;

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

	/// Texture view bindings (by binding slot).
	private Dictionary<uint32, ITextureView> mTextures = new .() ~ delete _;

	/// Sampler bindings (by binding slot).
	private Dictionary<uint32, ISampler> mSamplers = new .() ~ delete _;

	/// Whether uniform data needs to be uploaded.
	private bool mDirty = true;

	/// Whether bind group needs to be recreated.
	private bool mBindGroupDirty = true;

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
	public bool Initialize(IDevice device)
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

	/// Sets a float parameter by name.
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

	/// Sets a float2 parameter by name.
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

	/// Sets a float3 parameter by name.
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

	/// Sets a float4 parameter by name.
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

	/// Sets a matrix parameter by name.
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

	/// Sets a texture parameter by name.
	public void SetTexture(StringView name, ITextureView view)
	{
		let param = FindParam(name);
		if (param != null && (param.Type == .Texture2D || param.Type == .TextureCube))
		{
			mTextures[param.Binding] = view;
			mBindGroupDirty = true;
		}
	}

	/// Sets a sampler parameter by name.
	public void SetSampler(StringView name, ISampler sampler)
	{
		let param = FindParam(name);
		if (param != null && param.Type == .Sampler)
		{
			mSamplers[param.Binding] = sampler;
			mBindGroupDirty = true;
		}
	}

	/// Gets a texture binding by slot.
	public ITextureView GetTexture(uint32 binding)
	{
		if (mTextures.TryGetValue(binding, let tex))
			return tex;
		return null;
	}

	/// Gets a sampler binding by slot.
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

	/// Whether the bind group needs to be recreated.
	public bool NeedsBindGroupUpdate => mBindGroupDirty;

	/// Marks bind group as updated.
	public void MarkBindGroupUpdated()
	{
		mBindGroupDirty = false;
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

	public static readonly Self Invalid = .(uint32.MaxValue, 0);

	public uint32 Index => mIndex;
	public uint32 Generation => mGeneration;
	public bool IsValid => mIndex != uint32.MaxValue;

	public this(uint32 index, uint32 generation)
	{
		mIndex = index;
		mGeneration = generation;
	}

	public bool Equals(Self other)
	{
		return mIndex == other.mIndex && mGeneration == other.mGeneration;
	}

	public int GetHashCode()
	{
		return (int)(mIndex ^ (mGeneration << 16));
	}

	public static bool operator ==(Self lhs, Self rhs) => lhs.Equals(rhs);
	public static bool operator !=(Self lhs, Self rhs) => !lhs.Equals(rhs);
}
