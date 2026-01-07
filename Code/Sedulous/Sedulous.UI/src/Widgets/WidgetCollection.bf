using System;
using System.Collections;

namespace Sedulous.UI;

/// Collection of child widgets.
class WidgetCollection : IEnumerable<Widget>
{
	private List<Widget> mWidgets = new .() ~ delete _;
	private Widget mOwner;

	/// Creates a widget collection for the specified owner.
	public this(Widget owner)
	{
		mOwner = owner;
	}

	/// Gets the number of widgets in the collection.
	public int Count => mWidgets.Count;

	/// Gets the widget at the specified index.
	public Widget this[int index] => mWidgets[index];

	/// Gets the owner widget.
	public Widget Owner => mOwner;

	/// Adds a widget to the collection.
	public void Add(Widget widget)
	{
		if (widget == null)
			return;

		// Remove from previous parent
		if (widget.Parent != null)
			widget.Parent.Children.Remove(widget);

		mWidgets.Add(widget);
		widget.[Friend]mParent = mOwner;
		widget.[Friend]OnAttached();
		mOwner.InvalidateMeasure();
	}

	/// Inserts a widget at the specified index.
	public void Insert(int index, Widget widget)
	{
		if (widget == null)
			return;

		// Remove from previous parent
		if (widget.Parent != null)
			widget.Parent.Children.Remove(widget);

		mWidgets.Insert(index, widget);
		widget.[Friend]mParent = mOwner;
		widget.[Friend]OnAttached();
		mOwner.InvalidateMeasure();
	}

	/// Removes a widget from the collection.
	public bool Remove(Widget widget)
	{
		if (widget == null)
			return false;

		int index = mWidgets.IndexOf(widget);
		if (index >= 0)
		{
			RemoveAt(index);
			return true;
		}
		return false;
	}

	/// Removes the widget at the specified index.
	public void RemoveAt(int index)
	{
		if (index < 0 || index >= mWidgets.Count)
			return;

		let widget = mWidgets[index];
		widget.[Friend]OnDetached();
		widget.[Friend]mParent = null;
		mWidgets.RemoveAt(index);
		mOwner.InvalidateMeasure();
	}

	/// Clears all widgets from the collection.
	public void Clear()
	{
		for (let widget in mWidgets)
		{
			widget.[Friend]OnDetached();
			widget.[Friend]mParent = null;
		}
		mWidgets.Clear();
		mOwner.InvalidateMeasure();
	}

	/// Checks if the collection contains the specified widget.
	public bool Contains(Widget widget) => mWidgets.Contains(widget);

	/// Gets the index of the specified widget.
	public int IndexOf(Widget widget) => mWidgets.IndexOf(widget);

	/// Gets an enumerator for the collection.
	public List<Widget>.Enumerator GetEnumerator() => mWidgets.GetEnumerator();
}
