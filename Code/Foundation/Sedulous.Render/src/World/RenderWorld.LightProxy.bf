using Sedulous.Core.Mathematics;
namespace Sedulous.Render;

extension RenderWorld
{
	private RenderPool<LightProxy> mLightProxies = new .() ~ delete _;

	// ========================================================================
	// Light API
	// ========================================================================

	/// Creates a new light proxy.
	public LightRenderHandle CreateLight(LightType type = .Point)
	{
		let handle = mLightProxies.Allocate();
		var proxy = mLightProxies.Get(handle);
		proxy.Reset();
		proxy.Type = type;
		proxy.IsActive = true;
		proxy.IsEnabled = true;
		proxy.Generation = handle.Generation;
		mLightsDirty = true;
		return .() { Handle = handle };
	}

	/// Creates a directional light.
	public LightRenderHandle CreateDirectionalLight(Vector3 direction, Vector3 color, float intensity)
	{
		let handle = CreateLight(.Directional);
		if (let proxy = mLightProxies.Get(handle.Handle))
		{
			*proxy = LightProxy.CreateDirectional(direction, color, intensity);
			proxy.IsActive = true;
			proxy.Generation = handle.Handle.Generation;
		}
		return handle;
	}

	/// Creates a point light.
	public LightRenderHandle CreatePointLight(Vector3 position, Vector3 color, float intensity, float range)
	{
		let handle = CreateLight(.Point);
		if (let proxy = mLightProxies.Get(handle.Handle))
		{
			*proxy = LightProxy.CreatePoint(position, color, intensity, range);
			proxy.IsActive = true;
			proxy.Generation = handle.Handle.Generation;
		}
		return handle;
	}

	/// Creates a spot light.
	public LightRenderHandle CreateSpotLight(Vector3 position, Vector3 direction, Vector3 color, float intensity, float range, float innerAngle, float outerAngle)
	{
		let handle = CreateLight(.Spot);
		if (let proxy = mLightProxies.Get(handle.Handle))
		{
			*proxy = LightProxy.CreateSpot(position, direction, color, intensity, range, innerAngle, outerAngle);
			proxy.IsActive = true;
			proxy.Generation = handle.Handle.Generation;
		}
		return handle;
	}

	/// Gets a light proxy by handle.
	public LightProxy* GetLight(LightRenderHandle handle)
	{
		return mLightProxies.Get(handle.Handle);
	}

	/// Gets a reference to a light proxy.
	public ref LightProxy GetLightRef(LightRenderHandle handle)
	{
		return ref mLightProxies.GetRef(handle.Handle);
	}

	/// Destroys a light proxy.
	public void DestroyLight(LightRenderHandle handle)
	{
		if (mLightProxies.TryGet(handle.Handle, let proxy))
		{
			proxy.Reset();
		}
		mLightProxies.Free(handle.Handle);
		mLightsDirty = true;
	}

	/// Sets light position.
	public void SetLightPosition(LightRenderHandle handle, Vector3 position)
	{
		if (let proxy = mLightProxies.Get(handle.Handle))
		{
			proxy.Position = position;
			mLightsDirty = true;
		}
	}

	/// Sets light direction.
	public void SetLightDirection(LightRenderHandle handle, Vector3 direction)
	{
		if (let proxy = mLightProxies.Get(handle.Handle))
		{
			proxy.Direction = Vector3.Normalize(direction);
			mLightsDirty = true;
		}
	}

	/// Sets light color and intensity.
	public void SetLightColor(LightRenderHandle handle, Vector3 color, float intensity)
	{
		if (let proxy = mLightProxies.Get(handle.Handle))
		{
			proxy.Color = color;
			proxy.Intensity = intensity;
			mLightsDirty = true;
		}
	}

	/// Enables or disables a light.
	public void SetLightEnabled(LightRenderHandle handle, bool enabled)
	{
		if (let proxy = mLightProxies.Get(handle.Handle))
		{
			proxy.IsEnabled = enabled;
			mLightsDirty = true;
		}
	}

	/// Iterates over all active lights.
	public void ForEachLight(RenderPoolCallback<LightProxy> callback)
	{
		mLightProxies.ForEach(callback);
	}

}
