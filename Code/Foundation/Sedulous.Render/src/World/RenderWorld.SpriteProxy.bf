using Sedulous.RHI;
using Sedulous.Core.Mathematics;
namespace Sedulous.Render;

extension RenderWorld
{
	private ProxyPool<SpriteProxy> mSpriteProxies = new .() ~ delete _;

	// ========================================================================
	// Sprite API
	// ========================================================================

	/// Creates a new sprite proxy.
	public SpriteProxyHandle CreateSprite()
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
	public SpriteProxy* GetSprite(SpriteProxyHandle handle)
	{
		return mSpriteProxies.Get(handle.Handle);
	}

	/// Gets a reference to a sprite proxy.
	public ref SpriteProxy GetSpriteRef(SpriteProxyHandle handle)
	{
		return ref mSpriteProxies.GetRef(handle.Handle);
	}

	/// Destroys a sprite proxy.
	public void DestroySprite(SpriteProxyHandle handle)
	{
		if (mSpriteProxies.TryGet(handle.Handle, let proxy))
		{
			proxy.Reset();
		}
		mSpriteProxies.Free(handle.Handle);
		mSpritesDirty = true;
	}

	/// Sets sprite position.
	public void SetSpritePosition(SpriteProxyHandle handle, Vector3 position)
	{
		if (let proxy = mSpriteProxies.Get(handle.Handle))
		{
			proxy.Position = position;
			mSpritesDirty = true;
		}
	}

	/// Sets sprite size.
	public void SetSpriteSize(SpriteProxyHandle handle, Vector2 size)
	{
		if (let proxy = mSpriteProxies.Get(handle.Handle))
		{
			proxy.Size = size;
			mSpritesDirty = true;
		}
	}

	/// Sets sprite color.
	public void SetSpriteColor(SpriteProxyHandle handle, Color color)
	{
		if (let proxy = mSpriteProxies.Get(handle.Handle))
		{
			proxy.Color = color;
			mSpritesDirty = true;
		}
	}

	/// Sets sprite texture.
	public void SetSpriteTexture(SpriteProxyHandle handle, ITextureView texture)
	{
		if (let proxy = mSpriteProxies.Get(handle.Handle))
		{
			proxy.Texture = texture;
			mSpritesDirty = true;
		}
	}

	/// Sets sprite UV rect for atlas sub-regions.
	public void SetSpriteUVRect(SpriteProxyHandle handle, Vector4 uvRect)
	{
		if (let proxy = mSpriteProxies.Get(handle.Handle))
		{
			proxy.UVRect = uvRect;
			mSpritesDirty = true;
		}
	}

	/// Iterates over all active sprites.
	public void ForEachSprite(ProxyCallback<SpriteProxy> callback)
	{
		mSpriteProxies.ForEach(callback);
	}
}
