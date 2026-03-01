namespace Sedulous.Engine.UI;

using System;
using System.Collections;
using Sedulous.Engine.Scenes;

extension UISceneModule
{
	private List<IComponentDataProvider> mDataProviders ~ DeleteContainerAndItems!(_);

	public override void GetDataProviders(List<IComponentDataProvider> outProviders)
	{
		if (mDataProviders == null)
		{
			mDataProviders = new .();
			mDataProviders.Add(new WorldUIDataProvider(this));
		}
		outProviders.AddRange(mDataProviders);
	}

	public bool HasWorldUI(EntityId entity)
	{
		return GetPanel(entity) != null;
	}
}

class WorldUIDataProvider : IComponentDataProvider
{
	private UISceneModule mModule;
	public this(UISceneModule module) { mModule = module; }

	public void GetDisplayName(String outName) { outName.Append("World UI"); }
	public Type ComponentType => typeof(WorldUIComponent);
	public Type DataType => typeof(WorldUIComponentData);
	public bool HasComponent(EntityId entity) => mModule.HasWorldUI(entity);

	public bool GetComponentData(EntityId entity, void* outData)
	{
		let panel = mModule.GetPanel(entity);
		if (panel == null) return false;
		var data = (WorldUIComponentData*)outData;
		data.Enabled = true;
		data.PixelWidth = panel.PixelWidth;
		data.PixelHeight = panel.PixelHeight;
		data.PanelWidth = panel.PanelWidth;
		data.PanelHeight = panel.PanelHeight;
		data.IsInteractive = panel.IsInteractive;
		return true;
	}

	public void SetComponentData(EntityId entity, void* inData)
	{
		let panel = mModule.GetPanel(entity);
		if (panel == null) return;
		let data = (WorldUIComponentData*)inData;
		panel.IsInteractive = data.IsInteractive;
		// PixelWidth/Height/PanelWidth/Height are read-only — would need panel recreation to change
	}

	public bool CreateDefault(EntityId entity) { mModule.CreateWorldUI(entity, 512, 512, 1.0f, 1.0f); return true; }
	public void Destroy(EntityId entity)
	{
		let panel = mModule.GetPanel(entity);
		if (panel != null)
			mModule.DestroyPanel(panel);
	}
}
