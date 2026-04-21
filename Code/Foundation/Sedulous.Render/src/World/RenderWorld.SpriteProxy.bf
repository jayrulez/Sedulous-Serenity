using Sedulous.RHI;
using Sedulous.Core.Mathematics;
namespace Sedulous.Render;

extension RenderWorld
{
	private RenderPool<SpriteProxy> mSpriteProxies = new .() ~ delete _;

	// ========================================================================
	// Sprite API
	// ========================================================================

	/// Creates a new sprite proxy.
	public SpriteRenderHandle CreateSprite()
	{
		let handle = mSpriteProxies.Allocate();
		var proxy = mSpriteProxies.Get(handle);
		*proxy = SpriteProxy.CreateDefault();
		proxy.IsActive = true;
		proxy.Generation = handle.Generation;
		mSpritesDirty = true;
		return .() { Handle = handle };
	}

	/// Gets a sprite proxy by handle.
	public SpriteProxy* GetSprite(SpriteRenderHandle handle)
	{
		return mSpriteProxies.Get(handle.Handle);
	}

	/// Gets a reference to a sprite proxy.
	public ref SpriteProxy GetSpriteRef(SpriteRenderHandle handle)
	{
		return ref mSpriteProxies.GetRef(handle.Handle);
	}

	/// Destroys a sprite proxy.
	public void DestroySprite(SpriteRenderHandle handle)
	{
		if (mSpriteProxies.TryGet(handle.Handle, let proxy))
		{
			proxy.Reset();
		}
		mSpriteProxies.Free(handle.Handle);
		mSpritesDirty = true;
	}

	/// Sets sprite position.
	public void SetSpritePosition(SpriteRenderHandle handle, Vector3 position)
	{
		if (let proxy = mSpriteProxies.Get(handle.Handle))
		{
			proxy.Position = position;
			mSpritesDirty = true;
		}
	}

	/// Sets sprite size.
	public void SetSpriteSize(SpriteRenderHandle handle, Vector2 size)
	{
		if (let proxy = mSpriteProxies.Get(handle.Handle))
		{
			proxy.Size = size;
			mSpritesDirty = true;
		}
	}

	/// Sets sprite color.
	public void SetSpriteColor(SpriteRenderHandle handle, Color color)
	{
		if (let proxy = mSpriteProxies.Get(handle.Handle))
		{
			proxy.Color = color;
			mSpritesDirty = true;
		}
	}

	/// Sets sprite texture.
	public void SetSpriteTexture(SpriteRenderHandle handle, ITextureView texture)
	{
		if (let proxy = mSpriteProxies.Get(handle.Handle))
		{
			proxy.Texture = texture;
			mSpritesDirty = true;
		}
	}

	/// Sets sprite UV rect for atlas sub-regions.
	public void SetSpriteUVRect(SpriteRenderHandle handle, Vector4 uvRect)
	{
		if (let proxy = mSpriteProxies.Get(handle.Handle))
		{
			proxy.UVRect = uvRect;
			mSpritesDirty = true;
		}
	}

	/// Iterates over all active sprites.
	public void ForEachSprite(RenderPoolCallback<SpriteProxy> callback)
	{
		mSpriteProxies.ForEach(callback);
	}
}
