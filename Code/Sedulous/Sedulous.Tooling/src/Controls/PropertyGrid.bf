using System;
using System.Collections;
using System.Reflection;
using Sedulous.UI;
using Sedulous.Mathematics;

namespace Sedulous.Tooling;

/// Represents a single property row in the PropertyGrid.
class PropertyRow
{
	private String mName ~ delete _;
	private String mCategory ~ delete _;
	private String mDescription ~ delete _;
	private String mValueText ~ delete _;
	private Type mType;
	private Object mOwner;
	private FieldInfo mFieldInfo;
	private bool mIsExpanded = false;
	private bool mIsReadOnly = false;
	private List<PropertyRow> mChildren ~ DeleteContainerAndItems!(_);

	/// Gets the property name.
	public StringView Name => mName ?? "";

	/// Gets the category.
	public StringView Category => mCategory ?? "";

	/// Gets the description.
	public StringView Description => mDescription ?? "";

	/// Gets the value as text.
	public StringView ValueText => mValueText ?? "";

	/// Gets the property type.
	public Type PropertyType => mType;

	/// Gets or sets whether this property is expanded (for complex types).
	public bool IsExpanded
	{
		get => mIsExpanded;
		set => mIsExpanded = value;
	}

	/// Gets whether this property is read-only.
	public bool IsReadOnly => mIsReadOnly;

	/// Gets child properties (for complex types).
	public List<PropertyRow> Children => mChildren;

	/// Creates a property row.
	public this(StringView name, Type type, Object owner, FieldInfo fieldInfo)
	{
		mName = new String(name);
		mType = type;
		mOwner = owner;
		mFieldInfo = fieldInfo;
		UpdateValueText();
	}

	/// Sets the category.
	public void SetCategory(StringView category)
	{
		String.NewOrSet!(mCategory, category);
	}

	/// Sets the description.
	public void SetDescription(StringView description)
	{
		String.NewOrSet!(mDescription, description);
	}

	/// Sets read-only state.
	public void SetReadOnly(bool readOnly)
	{
		mIsReadOnly = readOnly;
	}

	/// Updates the value text representation.
	public void UpdateValueText()
	{
		if (mValueText == null)
			mValueText = new String();
		else
			mValueText.Clear();

		// Get value and convert to string
		if (mOwner != null && mFieldInfo.FieldType != null)
		{
			// Basic type formatting
			if (mType == typeof(String))
				mValueText.Set("(String)");
			else if (mType == typeof(int) || mType == typeof(int32) || mType == typeof(int64))
				mValueText.Set("(Integer)");
			else if (mType == typeof(float) || mType == typeof(double))
				mValueText.Set("(Float)");
			else if (mType == typeof(bool))
				mValueText.Set("(Boolean)");
			else
				mValueText.AppendF("({0})", mType.GetName(.. scope .()));
		}
	}

	/// Adds a child property.
	public void AddChild(PropertyRow child)
	{
		if (mChildren == null)
			mChildren = new .();
		mChildren.Add(child);
	}
}

/// A grid control for viewing and editing object properties.
class PropertyGrid : Widget
{
	private Object mSelectedObject;
	private List<PropertyRow> mProperties = new .() ~ DeleteContainerAndItems!(_);
	private List<String> mCategories = new .() ~ DeleteContainerAndItems!(_);
	private bool mShowCategories = true;
	private bool mShowDescriptions = true;
	private bool mAllowFiltering = true;
	private String mFilterText ~ delete _;

	// Visual properties
	private Color mBackgroundColor = Color(40, 40, 40, 255);
	private Color mRowBackground = Color(45, 45, 45, 255);
	private Color mRowAlternateBackground = Color(50, 50, 50, 255);
	private Color mRowHoverBackground = Color(55, 55, 55, 255);
	private Color mCategoryBackground = Color(35, 35, 35, 255);
	private Color mNameColor = Color(200, 200, 200, 255);
	private Color mValueColor = Color(180, 220, 180, 255);
	private Color mCategoryColor = Color(220, 180, 100, 255);
	private Color mDescriptionColor = Color(140, 140, 140, 255);
	private Color mBorderColor = Color(60, 60, 60, 255);
	private Color mSplitterColor = Color(70, 70, 70, 255);
	private FontHandle mFont;
	private float mFontSize = 12;
	private float mRowHeight = 22;
	private float mCategoryHeight = 24;
	private float mNameColumnWidth = 0.4f; // Percentage
	private float mDescriptionHeight = 60;
	private Thickness mRowPadding = Thickness(6, 2, 6, 2);

	// State
	private int32 mHoveredRowIndex = -1;
	private int32 mSelectedRowIndex = -1;
	private float mScrollOffset = 0;
	private bool mIsDraggingSplitter = false;

	/// Event raised when a property value changes.
	public Event<delegate void(StringView propertyName, Object newValue)> OnPropertyChanged ~ _.Dispose();

	/// Gets or sets the object being inspected.
	public Object SelectedObject
	{
		get => mSelectedObject;
		set
		{
			if (mSelectedObject != value)
			{
				mSelectedObject = value;
				RebuildPropertyList();
			}
		}
	}

	/// Gets or sets whether to group properties by category.
	public bool ShowCategories
	{
		get => mShowCategories;
		set
		{
			if (mShowCategories != value)
			{
				mShowCategories = value;
				RebuildPropertyList();
			}
		}
	}

	/// Gets or sets whether to show the description panel.
	public bool ShowDescriptions
	{
		get => mShowDescriptions;
		set
		{
			mShowDescriptions = value;
			InvalidateMeasure();
		}
	}

	/// Gets or sets whether filtering is allowed.
	public bool AllowFiltering
	{
		get => mAllowFiltering;
		set => mAllowFiltering = value;
	}

	/// Gets or sets the filter text.
	public StringView FilterText
	{
		get => mFilterText ?? "";
		set
		{
			String.NewOrSet!(mFilterText, value);
			// TODO: Apply filter
			InvalidateVisual();
		}
	}

	/// Gets or sets the font.
	public FontHandle Font
	{
		get => mFont;
		set => mFont = value;
	}

	/// Gets or sets the font size.
	public float FontSize
	{
		get => mFontSize;
		set => mFontSize = value;
	}

	/// Gets the properties collection.
	public List<PropertyRow> Properties => mProperties;

	/// Rebuilds the property list from the selected object.
	public void RebuildPropertyList()
	{
		// Clear existing
		for (let prop in mProperties)
			delete prop;
		mProperties.Clear();

		for (let cat in mCategories)
			delete cat;
		mCategories.Clear();

		if (mSelectedObject == null)
		{
			InvalidateMeasure();
			return;
		}

		// Use reflection to get fields
		let type = mSelectedObject.GetType();
		for (let field in type.GetFields())
		{
			if (field.IsStatic)
				continue;

			// Create property row
			let name = field.Name;
			let propRow = new PropertyRow(name, field.FieldType, mSelectedObject, field);

			// Check for attributes (category, description, etc.)
			// In Beef, we'd use custom attributes but for now use defaults
			propRow.SetCategory("General");

			mProperties.Add(propRow);

			// Track categories
			bool foundCategory = false;
			for (let cat in mCategories)
			{
				if (cat.Equals(propRow.Category, .OrdinalIgnoreCase))
				{
					foundCategory = true;
					break;
				}
			}
			if (!foundCategory)
				mCategories.Add(new String(propRow.Category));
		}

		mSelectedRowIndex = -1;
		mHoveredRowIndex = -1;
		mScrollOffset = 0;
		InvalidateMeasure();
	}

	/// Adds a property row manually.
	public void AddProperty(PropertyRow row)
	{
		mProperties.Add(row);
		InvalidateMeasure();
	}

	/// Clears all properties.
	public void ClearProperties()
	{
		for (let prop in mProperties)
			delete prop;
		mProperties.Clear();

		for (let cat in mCategories)
			delete cat;
		mCategories.Clear();

		mSelectedRowIndex = -1;
		mHoveredRowIndex = -1;
		InvalidateMeasure();
	}

	protected override Vector2 MeasureOverride(Vector2 availableSize)
	{
		float height = 0;

		if (mShowCategories)
		{
			height += mCategories.Count * mCategoryHeight;
		}

		height += mProperties.Count * mRowHeight;

		if (mShowDescriptions)
			height += mDescriptionHeight;

		return Vector2(200, height + Padding.VerticalThickness);
	}

	protected override void ArrangeOverride(RectangleF finalRect)
	{
		// PropertyGrid manages its own layout
	}

	protected override void OnRender(DrawContext dc)
	{
		let contentBounds = ContentBounds;

		// Background
		dc.FillRect(contentBounds, mBackgroundColor);
		dc.DrawRect(contentBounds, mBorderColor, 1);

		// Calculate layout
		let nameWidth = contentBounds.Width * mNameColumnWidth;
		let valueWidth = contentBounds.Width - nameWidth;
		var y = contentBounds.Y - mScrollOffset;

		// Draw properties (optionally grouped by category)
		if (mShowCategories && mCategories.Count > 0)
		{
			for (let category in mCategories)
			{
				// Category header
				let categoryRect = RectangleF(contentBounds.X, y, contentBounds.Width, mCategoryHeight);
				if (categoryRect.Bottom > contentBounds.Y && categoryRect.Y < contentBounds.Bottom)
				{
					dc.FillRect(categoryRect, mCategoryBackground);
					let textRect = RectangleF(categoryRect.X + 16, categoryRect.Y, categoryRect.Width - 16, categoryRect.Height);
					dc.DrawText(category, mFont, mFontSize, textRect, mCategoryColor, .Start, .Center, false);

					// Expand/collapse indicator
					let indicatorSize = 8f;
					Vector2[3] arrow = .(
						Vector2(categoryRect.X + 4, categoryRect.Y + (mCategoryHeight - indicatorSize) / 2),
						Vector2(categoryRect.X + 4 + indicatorSize, categoryRect.Y + mCategoryHeight / 2),
						Vector2(categoryRect.X + 4, categoryRect.Y + (mCategoryHeight + indicatorSize) / 2)
					);
					dc.FillPath(arrow, mCategoryColor);
				}
				y += mCategoryHeight;

				// Properties in this category
				int32 rowIndex = 0;
				for (let prop in mProperties)
				{
					if (!prop.Category.Equals(category, true))
					{
						rowIndex++;
						continue;
					}

					let rowRect = RectangleF(contentBounds.X, y, contentBounds.Width, mRowHeight);
					if (rowRect.Bottom > contentBounds.Y && rowRect.Y < contentBounds.Bottom)
					{
						RenderPropertyRow(dc, prop, rowRect, nameWidth, rowIndex);
					}
					y += mRowHeight;
					rowIndex++;
				}
			}
		}
		else
		{
			// Flat list
			int32 rowIndex = 0;
			for (let prop in mProperties)
			{
				let rowRect = RectangleF(contentBounds.X, y, contentBounds.Width, mRowHeight);
				if (rowRect.Bottom > contentBounds.Y && rowRect.Y < contentBounds.Bottom)
				{
					RenderPropertyRow(dc, prop, rowRect, nameWidth, rowIndex);
				}
				y += mRowHeight;
				rowIndex++;
			}
		}

		// Name/value splitter line
		let splitterX = contentBounds.X + nameWidth;
		dc.DrawLine(Vector2(splitterX, contentBounds.Y), Vector2(splitterX, y + mScrollOffset), mSplitterColor, 1);

		// Description panel
		if (mShowDescriptions)
		{
			let descRect = RectangleF(
				contentBounds.X,
				contentBounds.Bottom - mDescriptionHeight,
				contentBounds.Width,
				mDescriptionHeight
			);
			dc.FillRect(descRect, mCategoryBackground);
			dc.DrawRect(descRect, mBorderColor, 1);

			if (mSelectedRowIndex >= 0 && mSelectedRowIndex < mProperties.Count)
			{
				let prop = mProperties[mSelectedRowIndex];
				// Property name
				let nameRect = RectangleF(descRect.X + 4, descRect.Y + 4, descRect.Width - 8, mFontSize + 4);
				dc.DrawText(prop.Name, mFont, mFontSize, nameRect, mNameColor, .Start, .Start, false);

				// Description text
				if (prop.Description.Length > 0)
				{
					let descTextRect = RectangleF(descRect.X + 4, descRect.Y + mFontSize + 8, descRect.Width - 8, descRect.Height - mFontSize - 12);
					dc.DrawText(prop.Description, mFont, mFontSize - 1, descTextRect, mDescriptionColor, .Start, .Start, true);
				}
			}
		}
	}

	private void RenderPropertyRow(DrawContext dc, PropertyRow prop, RectangleF rowRect, float nameWidth, int32 rowIndex)
	{
		// Background
		Color bgColor;
		if (rowIndex == mSelectedRowIndex)
			bgColor = mRowHoverBackground;
		else if (rowIndex == mHoveredRowIndex)
			bgColor = Color(52, 52, 52, 255);
		else if (rowIndex % 2 == 0)
			bgColor = mRowBackground;
		else
			bgColor = mRowAlternateBackground;

		dc.FillRect(rowRect, bgColor);

		// Name
		let nameRect = RectangleF(
			rowRect.X + mRowPadding.Left,
			rowRect.Y,
			nameWidth - mRowPadding.HorizontalThickness,
			rowRect.Height
		);
		dc.DrawText(prop.Name, mFont, mFontSize, nameRect, mNameColor, .Start, .Center, false);

		// Value
		let valueRect = RectangleF(
			rowRect.X + nameWidth + mRowPadding.Left,
			rowRect.Y,
			rowRect.Width - nameWidth - mRowPadding.HorizontalThickness,
			rowRect.Height
		);
		dc.DrawText(prop.ValueText, mFont, mFontSize, valueRect, mValueColor, .Start, .Center, false);
	}

	protected override bool OnMouseMove(MouseMoveEventArgs e)
	{
		let contentBounds = ContentBounds;

		// Check splitter drag
		if (mIsDraggingSplitter)
		{
			mNameColumnWidth = Math.Clamp((e.Position.X - contentBounds.X) / contentBounds.Width, 0.2f, 0.8f);
			InvalidateVisual();
			return true;
		}

		// Find hovered row
		int32 newHovered = -1;
		var y = contentBounds.Y - mScrollOffset;

		if (mShowCategories)
		{
			for (let category in mCategories)
			{
				y += mCategoryHeight;
				for (int32 i = 0; i < mProperties.Count; i++)
				{
					if (!mProperties[i].Category.Equals(category, true))
						continue;

					let rowRect = RectangleF(contentBounds.X, y, contentBounds.Width, mRowHeight);
					if (rowRect.Contains(e.Position))
					{
						newHovered = i;
						break;
					}
					y += mRowHeight;
				}
				if (newHovered >= 0)
					break;
			}
		}
		else
		{
			for (int32 i = 0; i < mProperties.Count; i++)
			{
				let rowRect = RectangleF(contentBounds.X, y, contentBounds.Width, mRowHeight);
				if (rowRect.Contains(e.Position))
				{
					newHovered = i;
					break;
				}
				y += mRowHeight;
			}
		}

		if (mHoveredRowIndex != newHovered)
		{
			mHoveredRowIndex = newHovered;
			InvalidateVisual();
		}

		return true;
	}

	protected override bool OnMouseLeave(MouseEventArgs e)
	{
		if (mHoveredRowIndex != -1)
		{
			mHoveredRowIndex = -1;
			InvalidateVisual();
		}
		return false;
	}

	protected override bool OnMouseDown(MouseButtonEventArgs e)
	{
		if (e.Button != .Left)
			return false;

		let contentBounds = ContentBounds;

		// Check splitter click
		let splitterX = contentBounds.X + contentBounds.Width * mNameColumnWidth;
		if (Math.Abs(e.Position.X - splitterX) < 4)
		{
			mIsDraggingSplitter = true;
			return true;
		}

		// Select row
		if (mHoveredRowIndex >= 0)
		{
			mSelectedRowIndex = mHoveredRowIndex;
			InvalidateVisual();
			return true;
		}

		return false;
	}

	protected override bool OnMouseUp(MouseButtonEventArgs e)
	{
		if (e.Button == .Left && mIsDraggingSplitter)
		{
			mIsDraggingSplitter = false;
			return true;
		}
		return false;
	}

	protected override bool OnMouseWheel(MouseWheelEventArgs e)
	{
		mScrollOffset = Math.Max(0, mScrollOffset - e.DeltaY * mRowHeight * 3);
		InvalidateVisual();
		return true;
	}
}
