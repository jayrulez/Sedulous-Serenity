namespace Sedulous.Framework.Renderer;

using System;
using System.Collections;
using Sedulous.RHI;
using Sedulous.Mathematics;

/// A single sprite instance for batched rendering.
[CRepr]
struct SpriteInstance
{
	/// World position of sprite center.
	public Vector3 Position;
	/// Width and height in world units.
	public Vector2 Size;
	/// UV rectangle (minU, minV, maxU, maxV).
	public Vector4 UVRect;
	/// Tint color (RGBA).
	public Color Color;

	public this()
	{
		Position = .Zero;
		Size = .(1, 1);
		UVRect = .(0, 0, 1, 1);
		Color = .White;
	}

	public this(Vector3 position, Vector2 size, Color color = .White)
	{
		Position = position;
		Size = size;
		UVRect = .(0, 0, 1, 1);
		Color = color;
	}

	public this(Vector3 position, Vector2 size, Vector4 uvRect, Color color)
	{
		Position = position;
		Size = size;
		UVRect = uvRect;
		Color = color;
	}
}

/// Batched sprite renderer for efficient billboard rendering.
class SpriteRenderer
{
	private IDevice mDevice;
	private IBuffer mInstanceBuffer;
	private IBuffer mIndexBuffer;
	private IRenderPipeline mPipeline;
	private IBindGroupLayout mBindGroupLayout;
	private IPipelineLayout mPipelineLayout;

	private List<SpriteInstance> mSprites = new .() ~ delete _;
	private int32 mMaxSprites;
	private bool mDirty = false;

	/// Maximum number of sprites that can be rendered in one batch.
	public const int32 DEFAULT_MAX_SPRITES = 10000;

	public this(IDevice device, int32 maxSprites = DEFAULT_MAX_SPRITES)
	{
		mDevice = device;
		mMaxSprites = maxSprites;

		CreateBuffers();
	}

	public ~this()
	{
		if (mInstanceBuffer != null) delete mInstanceBuffer;
		if (mIndexBuffer != null) delete mIndexBuffer;
		if (mPipeline != null) delete mPipeline;
		if (mBindGroupLayout != null) delete mBindGroupLayout;
		if (mPipelineLayout != null) delete mPipelineLayout;
	}

	private void CreateBuffers()
	{
		// Instance buffer (one SpriteInstance per sprite, 4 vertices use same instance data)
		let instanceSize = (uint64)(sizeof(SpriteInstance) * mMaxSprites);
		BufferDescriptor instanceDesc = .(instanceSize, .Vertex, .Upload);
		if (mDevice.CreateBuffer(&instanceDesc) case .Ok(let instBuf))
			mInstanceBuffer = instBuf;

		// Index buffer for quads (6 indices per sprite)
		let indexCount = mMaxSprites * 6;
		let indexSize = (uint64)(sizeof(uint16) * indexCount);
		BufferDescriptor indexDesc = .(indexSize, .Index, .Upload);
		if (mDevice.CreateBuffer(&indexDesc) case .Ok(let idxBuf))
		{
			mIndexBuffer = idxBuf;

			// Fill index buffer with quad indices
			uint16[] indices = new uint16[indexCount];
			defer delete indices;

			for (int32 i = 0; i < mMaxSprites; i++)
			{
				int32 baseVertex = i * 4;
				int32 baseIndex = i * 6;
				indices[baseIndex + 0] = (uint16)(baseVertex + 0);
				indices[baseIndex + 1] = (uint16)(baseVertex + 1);
				indices[baseIndex + 2] = (uint16)(baseVertex + 2);
				indices[baseIndex + 3] = (uint16)(baseVertex + 2);
				indices[baseIndex + 4] = (uint16)(baseVertex + 1);
				indices[baseIndex + 5] = (uint16)(baseVertex + 3);
			}

			Span<uint8> data = .((uint8*)indices.Ptr, (int)indexSize);
			mDevice.Queue.WriteBuffer(mIndexBuffer, 0, data);
		}
	}

	/// Clears all sprites for a new frame.
	public void Begin()
	{
		mSprites.Clear();
		mDirty = true;
	}

	/// Adds a sprite to the batch.
	public void AddSprite(SpriteInstance sprite)
	{
		if (mSprites.Count < mMaxSprites)
		{
			mSprites.Add(sprite);
			mDirty = true;
		}
	}

	/// Adds a sprite with common parameters.
	public void AddSprite(Vector3 position, Vector2 size, Color color = .White)
	{
		AddSprite(.(position, size, color));
	}

	/// Uploads sprite data to GPU and prepares for rendering.
	public void End()
	{
		if (!mDirty || mSprites.Count == 0)
			return;

		// Upload instance data
		let dataSize = (uint64)(sizeof(SpriteInstance) * mSprites.Count);
		Span<uint8> data = .((uint8*)mSprites.Ptr, (int)dataSize);
		mDevice.Queue.WriteBuffer(mInstanceBuffer, 0, data);

		mDirty = false;
	}

	/// Returns the number of sprites in the current batch.
	public int32 SpriteCount => (int32)mSprites.Count;

	/// Gets the instance buffer for rendering.
	public IBuffer InstanceBuffer => mInstanceBuffer;

	/// Gets the index buffer for rendering.
	public IBuffer IndexBuffer => mIndexBuffer;

	/// Gets the number of indices to draw.
	public uint32 IndexCount => (uint32)(mSprites.Count * 6);
}
