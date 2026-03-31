namespace Sedulous.Renderer;

using System;
using System.Collections;
using Sedulous.RHI;

/// Per-instance material data — property values, texture bindings, and GPU bind group.
/// Each instance references a MaterialDefinition (template) and stores its own values.
/// Property buffers and bind groups are double-buffered per frame-in-flight to avoid
/// CPU/GPU contention when properties are updated while the GPU reads the previous frame.
public class MaterialInstance
{
	/// The definition this instance is based on.
	public MaterialDefinition Definition;

	/// Per-frame uniform buffers for scalar properties (mapped CpuToGpu).
	public IBuffer[RenderConfig.FrameBufferCount] PropertyBuffers;

	/// Per-frame persistent mapped pointers.
	private void*[RenderConfig.FrameBufferCount] mMappedPtrs;

	/// Texture views bound to material slots.
	public ITextureView[] TextureSlots ~ delete _;

	/// Samplers bound to material slots.
	public ISampler[] SamplerSlots ~ delete _;

	/// Per-frame GPU bind groups (Set 1).
	public IBindGroup[RenderConfig.FrameBufferCount] BindGroups;

	/// Per-frame dirty flags — tracks which frame slots need bind group rebuild.
	private bool[RenderConfig.FrameBufferCount] mDirtyFrames;

	/// Reference count.
	public int32 RefCount;
	/// Generation for handle validation.
	public uint32 Generation;
	/// Whether this slot is in use.
	public bool IsActive;

	/// Whether any frame slot needs a bind group rebuild.
	public bool Dirty
	{
		get
		{
			for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
				if (mDirtyFrames[i]) return true;
			return false;
		}
	}

	/// Creates the property buffers and allocates texture/sampler slot arrays.
	public Result<void> Initialize(IDevice device, MaterialDefinition definition)
	{
		Definition = definition;

		// Create per-frame property UBOs if needed
		if (definition.PropertyBufferSize > 0)
		{
			// Align to 256 bytes for uniform buffer requirements
			let alignedSize = (definition.PropertyBufferSize + 255) & ~(uint32)255;

			for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
			{
				let result = device.CreateBuffer(BufferDesc()
				{
					Size = (uint64)alignedSize,
					Usage = .Uniform,
					Memory = .CpuToGpu,
					Label = "MaterialPropertyBuffer"
				});

				if (result case .Err)
					return .Err;

				PropertyBuffers[i] = result.Value;
				mMappedPtrs[i] = PropertyBuffers[i].Map();
			}
		}

		// Allocate texture/sampler arrays
		if (definition.TextureCount > 0)
			TextureSlots = new ITextureView[definition.TextureCount];

		if (definition.SamplerCount > 0)
			SamplerSlots = new ISampler[definition.SamplerCount];

		// Mark all frame slots as dirty so bind groups get built on first use
		for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
			mDirtyFrames[i] = true;

		return .Ok;
	}

	/// Sets a float property by name. Writes to all frame slots.
	public void SetFloat(StringView name, float value)
	{
		if (PropertyBuffers[0] == null) return;
		if (FindScalarProperty(name) case .Ok(let prop))
		{
			for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
			{
				let ptr = (float*)((uint8*)mMappedPtrs[i] + prop.ByteOffset);
				*ptr = value;
				mDirtyFrames[i] = true;
			}
		}
	}

	/// Sets a float2 property by name. Writes to all frame slots.
	public void SetFloat2(StringView name, float x, float y)
	{
		if (PropertyBuffers[0] == null) return;
		if (FindScalarProperty(name) case .Ok(let prop))
		{
			for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
			{
				let ptr = (float*)((uint8*)mMappedPtrs[i] + prop.ByteOffset);
				ptr[0] = x;
				ptr[1] = y;
				mDirtyFrames[i] = true;
			}
		}
	}

	/// Sets a float3 property by name. Writes to all frame slots.
	public void SetFloat3(StringView name, float x, float y, float z)
	{
		if (PropertyBuffers[0] == null) return;
		if (FindScalarProperty(name) case .Ok(let prop))
		{
			for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
			{
				let ptr = (float*)((uint8*)mMappedPtrs[i] + prop.ByteOffset);
				ptr[0] = x;
				ptr[1] = y;
				ptr[2] = z;
				mDirtyFrames[i] = true;
			}
		}
	}

	/// Sets a float4/color property by name. Writes to all frame slots.
	public void SetFloat4(StringView name, float x, float y, float z, float w)
	{
		if (PropertyBuffers[0] == null) return;
		if (FindScalarProperty(name) case .Ok(let prop))
		{
			for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
			{
				let ptr = (float*)((uint8*)mMappedPtrs[i] + prop.ByteOffset);
				ptr[0] = x;
				ptr[1] = y;
				ptr[2] = z;
				ptr[3] = w;
				mDirtyFrames[i] = true;
			}
		}
	}

	/// Sets an int property by name. Writes to all frame slots.
	public void SetInt(StringView name, int32 value)
	{
		if (PropertyBuffers[0] == null) return;
		if (FindScalarProperty(name) case .Ok(let prop))
		{
			for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
			{
				let ptr = (int32*)((uint8*)mMappedPtrs[i] + prop.ByteOffset);
				*ptr = value;
				mDirtyFrames[i] = true;
			}
		}
	}

	/// Sets a texture view at the given slot index.
	public void SetTexture(uint32 slotIndex, ITextureView view)
	{
		if (TextureSlots == null || slotIndex >= (uint32)TextureSlots.Count) return;
		TextureSlots[slotIndex] = view;
		MarkAllDirty();
	}

	/// Sets a texture view by property name.
	public void SetTextureByName(StringView name, ITextureView view)
	{
		for (let prop in Definition.Properties)
		{
			if ((prop.Type == .Texture2D || prop.Type == .TextureCube) && prop.Name == name)
			{
				// Texture slot index = binding slot minus texture base offset
				uint32 texBase = Definition.PropertyBufferSize > 0 ? (uint32)1 : (uint32)0;
				uint32 slotIndex = prop.BindingSlot - texBase;
				SetTexture(slotIndex, view);
				return;
			}
		}
	}

	/// Sets a sampler at the given slot index.
	public void SetSampler(uint32 slotIndex, ISampler sampler)
	{
		if (SamplerSlots == null || slotIndex >= (uint32)SamplerSlots.Count) return;
		SamplerSlots[slotIndex] = sampler;
		MarkAllDirty();
	}

	/// Rebuilds the bind group for the given frame index.
	/// Call when the frame slot is dirty before rendering.
	public Result<void> RebuildBindGroup(IDevice device, int frameIndex)
	{
		if (!mDirtyFrames[frameIndex] || Definition.BindGroupLayout == null)
			return .Ok;

		// Destroy old bind group for this frame slot
		if (BindGroups[frameIndex] != null)
			device.DestroyBindGroup(ref BindGroups[frameIndex]);

		// Count entries
		int entryCount = 0;
		if (PropertyBuffers[frameIndex] != null)
			entryCount++;
		if (TextureSlots != null)
			entryCount += TextureSlots.Count;
		if (SamplerSlots != null)
			entryCount += SamplerSlots.Count;

		if (entryCount == 0)
		{
			mDirtyFrames[frameIndex] = false;
			return .Ok;
		}

		let entries = scope BindGroupEntry[entryCount];
		int idx = 0;

		// UBO entry — use the frame-specific property buffer
		if (PropertyBuffers[frameIndex] != null)
			entries[idx++] = BindGroupEntry.Buffer(PropertyBuffers[frameIndex], 0, (uint64)Definition.PropertyBufferSize);

		// Texture entries
		if (TextureSlots != null)
		{
			for (let view in TextureSlots)
				entries[idx++] = BindGroupEntry.Texture(view);
		}

		// Sampler entries
		if (SamplerSlots != null)
		{
			for (let sampler in SamplerSlots)
				entries[idx++] = BindGroupEntry.Sampler(sampler);
		}

		let result = device.CreateBindGroup(BindGroupDesc()
		{
			Layout = Definition.BindGroupLayout,
			Entries = entries,
			Label = "MaterialBindGroup"
		});

		if (result case .Err)
			return .Err;

		BindGroups[frameIndex] = result.Value;
		mDirtyFrames[frameIndex] = false;
		return .Ok;
	}

	/// Gets the bind group for the given frame index.
	public IBindGroup GetBindGroup(int frameIndex)
	{
		return BindGroups[frameIndex];
	}

	/// Returns whether the given frame slot needs a bind group rebuild.
	public bool IsDirty(int frameIndex)
	{
		return mDirtyFrames[frameIndex];
	}

	/// Releases GPU resources.
	public void Release(IDevice device)
	{
		for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
		{
			if (BindGroups[i] != null)
				device.DestroyBindGroup(ref BindGroups[i]);
			if (PropertyBuffers[i] != null)
			{
				PropertyBuffers[i].Unmap();
				device.DestroyBuffer(ref PropertyBuffers[i]);
			}
		}
		DeleteAndNullify!(TextureSlots);
		DeleteAndNullify!(SamplerSlots);
		IsActive = false;
	}

	// --- Internal ---

	private void MarkAllDirty()
	{
		for (int i = 0; i < RenderConfig.FrameBufferCount; i++)
			mDirtyFrames[i] = true;
	}

	private Result<MaterialProperty> FindScalarProperty(StringView name)
	{
		for (let prop in Definition.Properties)
		{
			if (MaterialProperty.IsScalar(prop.Type) && prop.Name == name)
				return .Ok(prop);
		}
		return .Err;
	}
}
