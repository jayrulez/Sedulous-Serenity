namespace Sedulous.Tools.SceneEditor;

using System;
using Sedulous.GUI;
using Sedulous.Core.Mathematics;

/// PropertyItem that displays a clickable button in the value column.
class ButtonPropertyItem : PropertyItem
{
	public delegate void() OnClick ~ delete _;

	public this(StringView name, delegate void() onClick) : base(name, .String)
	{
		OnClick = onClick;
	}

	public override UIElement CreateEditorControl()
	{
		let btn = new Button();
		btn.Content = new TextBlock(Name);
		btn.Click.Subscribe(new (b) =>
			{
				OnClick?.Invoke();
			});
		return btn;
	}
}
