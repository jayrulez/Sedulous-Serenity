using Sedulous.UI;
using System;
namespace UISandbox;
/// Custom control that shows a context menu on right-click.
class ContextMenuArea : Border
{
	private UIContext mUIContext;
	private ContextMenu mContextMenu ~ delete _;

	public this(UIContext context)
	{
		mUIContext = context;

		// Create the context menu
		mContextMenu = new ContextMenu();
		mContextMenu.AddItem("Cut", "Ctrl+X", new (item) => {
			Console.WriteLine("Cut clicked");
		});
		mContextMenu.AddItem("Copy", "Ctrl+C", new (item) => {
			Console.WriteLine("Copy clicked");
		});
		mContextMenu.AddItem("Paste", "Ctrl+V", new (item) => {
			Console.WriteLine("Paste clicked");
		});
		mContextMenu.AddSeparator();
		mContextMenu.AddItem("Delete", "Del", new (item) => {
			Console.WriteLine("Delete clicked");
		});

		// Add to tree so popup can find Context
		mContextMenu.[Friend]mParent = this;
	}

	protected override void OnMouseUpRouted(MouseButtonEventArgs args)
	{
		if (args.Button == .Right)
		{
			// Open context menu at mouse position
			mContextMenu.OpenAt(args.ScreenX, args.ScreenY);
			args.Handled = true;
		}
		base.OnMouseUpRouted(args);
	}
}