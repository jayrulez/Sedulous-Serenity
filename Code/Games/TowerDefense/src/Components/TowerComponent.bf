namespace TowerDefense.Components;

using System;
using Sedulous.Framework.Scenes;
using Sedulous.Mathematics;
using TowerDefense.Data;

/// Simple reference class for legacy delegate compatibility.
/// Note: Tower state is managed by TowerFactory using TowerData internally.
class TowerComponent
{
	public TowerDefinition Definition;

	public this()
	{
	}

	public this(TowerDefinition definition)
	{
		Definition = definition;
	}
}
