namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.RHI;

/// Blend mode presets for materials.
public enum BlendMode
{
	Opaque,
	AlphaBlend,
	Additive,
	Multiply,
	PremultipliedAlpha,
}

/// Depth testing mode for materials.
public enum DepthMode
{
	ReadWrite,
	ReadOnly,
	WriteOnly,
	Disabled,
}

/// Material template — defines the shader, properties, and render state.
/// Multiple MaterialInstances can share the same definition.
public class MaterialDefinition
{
	/// Display name.
	public String Name ~ delete _;
	/// Shader name (registered in ShaderLibrary).
	public String ShaderName ~ delete _;

	/// Property descriptors.
	public List<MaterialProperty> Properties = new .() ~ delete _;

	/// Render state.
	public BlendMode BlendMode = .Opaque;
	public CullMode CullMode = .Back;
	public DepthMode DepthMode = .ReadWrite;

	/// Render layer bitmask for selective rendering.
	public uint32 RenderLayer = 1;

	/// Total size of scalar properties in the material UBO (bytes).
	public uint32 PropertyBufferSize;

	/// Number of texture bindings.
	public uint32 TextureCount;
	/// Number of sampler bindings.
	public uint32 SamplerCount;

	/// Cached bind group layout for material set (Set 1).
	public IBindGroupLayout BindGroupLayout;

	/// Builds the bind group layout from the property descriptors.
	/// Call after all properties have been added.
	public Result<void> BuildLayout(IDevice device)
	{
		// Count entries: 1 UBO (if scalar props) + textures + samplers
		int entryCount = 0;
		if (PropertyBufferSize > 0)
			entryCount++;
		entryCount += (int)TextureCount;
		entryCount += (int)SamplerCount;

		if (entryCount == 0)
			return .Ok;

		let entries = scope BindGroupLayoutEntry[entryCount];
		uint32 binding = 0;

		// Binding 0: Material properties UBO
		if (PropertyBufferSize > 0)
		{
			entries[binding] = BindGroupLayoutEntry.UniformBuffer(
				binding, .Fragment | .Vertex);
			binding++;
		}

		// Texture bindings
		for (let prop in Properties)
		{
			if (prop.Type == .Texture2D)
			{
				entries[binding] = BindGroupLayoutEntry.SampledTexture(
					binding, .Fragment, .Texture2D);
				binding++;
			}
			else if (prop.Type == .TextureCube)
			{
				entries[binding] = BindGroupLayoutEntry.SampledTexture(
					binding, .Fragment, .TextureCube);
				binding++;
			}
		}

		// Sampler bindings
		for (let prop in Properties)
		{
			if (prop.Type == .Sampler)
			{
				entries[binding] = BindGroupLayoutEntry.Sampler(
					binding, .Fragment);
				binding++;
			}
		}

		let result = device.CreateBindGroupLayout(BindGroupLayoutDesc()
		{
			Entries = entries,
			Label = Name
		});

		if (result case .Err)
			return .Err;

		BindGroupLayout = result.Value;
		return .Ok;
	}

	/// Adds a scalar property and returns its byte offset.
	public uint32 AddScalarProperty(StringView name, MaterialPropertyType type)
	{
		// Align to 4 bytes
		let size = MaterialProperty.GetTypeSize(type);
		let offset = PropertyBufferSize;

		// Align float3 to 16 bytes (std140 rule)
		var alignedOffset = offset;
		if (type == .Float3 || type == .Float4 || type == .Color)
			alignedOffset = (offset + 15) & ~(uint32)15;
		else
			alignedOffset = (offset + 3) & ~(uint32)3;

		Properties.Add(.()
		{
			Name = name,
			Type = type,
			ByteOffset = alignedOffset,
			BindingSlot = 0
		});

		PropertyBufferSize = alignedOffset + size;
		return alignedOffset;
	}

	/// Adds a texture property and returns its binding slot.
	public uint32 AddTextureProperty(StringView name, MaterialPropertyType type = .Texture2D)
	{
		// Binding slot: skip UBO binding (0) + existing textures
		uint32 slot = (PropertyBufferSize > 0 ? (uint32)1 : (uint32)0) + TextureCount;

		Properties.Add(.()
		{
			Name = name,
			Type = type,
			ByteOffset = 0,
			BindingSlot = slot
		});

		TextureCount++;
		return slot;
	}

	/// Adds a sampler property and returns its binding slot.
	public uint32 AddSamplerProperty(StringView name)
	{
		uint32 slot = (PropertyBufferSize > 0 ? (uint32)1 : (uint32)0) + TextureCount + SamplerCount;

		Properties.Add(.()
		{
			Name = name,
			Type = .Sampler,
			ByteOffset = 0,
			BindingSlot = slot
		});

		SamplerCount++;
		return slot;
	}

	/// Releases GPU resources.
	public void Release(IDevice device)
	{
		if (BindGroupLayout != null)
			device.DestroyBindGroupLayout(ref BindGroupLayout);
	}

	/// Converts BlendMode to RHI BlendState.
	public static BlendState? GetBlendState(BlendMode mode)
	{
		switch (mode)
		{
		case .Opaque:            return null;
		case .AlphaBlend:        return BlendState.AlphaBlend;
		case .Additive:          return BlendState.Additive;
		case .Multiply:          return BlendState.Multiply;
		case .PremultipliedAlpha: return BlendState.PremultipliedAlpha;
		}
	}

	/// Converts DepthMode to RHI DepthStencilState.
	public static DepthStencilState GetDepthStencilState(DepthMode mode, TextureFormat depthFormat = .Depth24Plus)
	{
		switch (mode)
		{
		case .ReadWrite: return DepthStencilState.DepthDefault(depthFormat);
		case .ReadOnly:  return DepthStencilState.DepthReadOnly(depthFormat);
		case .WriteOnly:
			var state = DepthStencilState.DepthDefault(depthFormat);
			state.DepthCompare = .Always;
			return state;
		case .Disabled:  return DepthStencilState.Disabled(depthFormat);
		}
	}
}
