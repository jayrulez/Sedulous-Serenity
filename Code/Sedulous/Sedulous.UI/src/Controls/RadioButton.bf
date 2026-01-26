using System;
using System.Collections;
using Sedulous.Drawing;
using Sedulous.Mathematics;

namespace Sedulous.UI;

/// A radio button that allows selection from a mutually exclusive group.
public class RadioButton : ToggleButton
{
	private static Dictionary<String, List<RadioButton>> sGroups = new .() ~ {
		for (let pair in _)
		{
			delete pair.key;
			delete pair.value;
		}
		delete _;
	};

	private String mGroupName ~ delete _;
	private const float RadioSize = 16.0f;
	private const float RadioSpacing = 6.0f;

	/// The name of the group this radio button belongs to.
	/// Radio buttons with the same group name are mutually exclusive.
	public StringView GroupName
	{
		get => mGroupName ?? "";
		set
		{
			let oldGroup = mGroupName;

			// Remove from old group
			if (oldGroup != null)
			{
				if (sGroups.TryGetValue(oldGroup, let list))
				{
					list.Remove(this);
					if (list.Count == 0)
					{
						// Find and delete the key, then remove from dictionary
						for (let pair in sGroups)
						{
							if (pair.value == list)
							{
								let keyToDelete = pair.key;
								sGroups.Remove(keyToDelete);
								delete keyToDelete;
								break;
							}
						}
						delete list;
					}
				}
			}

			// Set new group name
			if (value.Length > 0)
			{
				if (mGroupName == null)
					mGroupName = new String();
				mGroupName.Set(value);

				// Add to new group
				List<RadioButton> groupList;
				if (sGroups.TryGetValue(mGroupName, out groupList))
				{
					groupList.Add(this);
				}
				else
				{
					let newKey = new String(mGroupName);
					groupList = new List<RadioButton>();
					groupList.Add(this);
					sGroups[newKey] = groupList;
				}
			}
			else
			{
				delete mGroupName;
				mGroupName = null;
			}
		}
	}

	public this()
	{
		// Radio buttons don't support three-state
		IsThreeState = false;
	}

	public this(StringView text) : this()
	{
		ContentText = text;
	}

	public this(StringView text, StringView groupName) : this(text)
	{
		GroupName = groupName;
	}

	public ~this()
	{
		// Remove from group on destruction
		if (mGroupName != null)
		{
			if (sGroups.TryGetValue(mGroupName, let list))
			{
				list.Remove(this);
				if (list.Count == 0)
				{
					// Find the key, remove from dictionary, then delete
					for (let pair in sGroups)
					{
						if (pair.value == list)
						{
							let keyToDelete = pair.key;
							sGroups.Remove(keyToDelete);
							delete keyToDelete;
							break;
						}
					}
					delete list;
				}
			}
		}
	}

	protected override void OnClick()
	{
		// Radio buttons can only be checked, not unchecked by clicking
		if (IsChecked != true)
		{
			// Uncheck siblings in the same group
			UncheckSiblings();
			IsChecked = true;
		}

		// Fire the click event directly (we already handled the checked state above)
		Click.[Friend]Invoke(this);
	}

	/// Unchecks all other radio buttons in the same group.
	private void UncheckSiblings()
	{
		if (mGroupName == null)
		{
			// No group - uncheck siblings in same parent (if parent is a CompositeControl)
			if (let composite = Parent as CompositeControl)
			{
				for (let child in composite.Children)
				{
					if (let radio = child as RadioButton)
					{
						if (radio != this && radio.mGroupName == null)
							radio.IsChecked = false;
					}
				}
			}
		}
		else
		{
			// Uncheck all in the named group
			if (sGroups.TryGetValue(mGroupName, let list))
			{
				for (let radio in list)
				{
					if (radio != this)
						radio.IsChecked = false;
				}
			}
		}
	}

	protected override DesiredSize MeasureContent(SizeConstraints constraints)
	{
		// Radio button is the circle plus spacing plus content
		let contentSize = base.MeasureContent(constraints);
		let totalWidth = RadioSize + RadioSpacing + contentSize.Width;
		let totalHeight = Math.Max(RadioSize, contentSize.Height);
		return .(totalWidth, totalHeight);
	}

	protected override void OnRender(DrawContext drawContext)
	{
		let bounds = Bounds;
		let theme = GetTheme();

		// Draw the radio circle
		let circleX = bounds.X + BorderThickness.Left + RadioSize / 2;
		let circleY = bounds.Y + BorderThickness.Top + (bounds.Height - BorderThickness.TotalVertical) / 2;
		let radius = RadioSize / 2;

		// Circle background
		let bgColor = IsEnabled ?
			(theme?.GetColor("Background") ?? Color.White) :
			(theme?.GetColor("Disabled") ?? Color(240, 240, 240));
		drawContext.FillCircle(.(circleX, circleY), radius, bgColor);

		// Circle border
		Color borderColor;
		if (!IsEnabled)
			borderColor = theme?.GetColor("ForegroundDisabled") ?? Color(180, 180, 180);
		else if (IsFocused)
			borderColor = theme?.GetColor("Primary") ?? Color(0, 120, 215);
		else
			borderColor = theme?.GetColor("Border") ?? Color.Gray;
		drawContext.DrawCircle(.(circleX, circleY), radius, borderColor, 1.0f);

		// Draw inner dot if checked
		if (IsChecked == true)
		{
			let dotColor = IsEnabled ?
				(theme?.GetColor("Primary") ?? Color(0, 120, 215)) :
				(theme?.GetColor("ForegroundDisabled") ?? Color(150, 150, 150));
			let dotRadius = radius * 0.5f;
			drawContext.FillCircle(.(circleX, circleY), dotRadius, dotColor);
		}

		// Render content (label) to the right of the radio button
		RenderContent(drawContext);
	}

	protected override void ArrangeContent(RectangleF contentBounds)
	{
		// Offset content to the right of the radio circle
		let offsetBounds = RectangleF(
			contentBounds.X + RadioSize + RadioSpacing,
			contentBounds.Y,
			contentBounds.Width - RadioSize - RadioSpacing,
			contentBounds.Height
		);

		if (Content != null)
		{
			Content.Arrange(offsetBounds);
		}
	}

	protected override void RenderContent(DrawContext drawContext)
	{
		if (Content != null)
		{
			// Content renders itself via the tree
			return;
		}

		// Render text content to the right of the radio with left alignment
		if (ContentText.Length > 0)
		{
			let theme = GetTheme();
			let foreground = Foreground ?? theme?.GetColor("Foreground") ?? Color.Black;
			let contentBounds = ContentBounds;

			// Calculate the text area (offset by radio circle)
			let textBounds = RectangleF(
				contentBounds.X + RadioSize + RadioSpacing,
				contentBounds.Y,
				contentBounds.Width - RadioSize - RadioSpacing,
				contentBounds.Height
			);

			let fontService = GetFontService();
			let cachedFont = GetCachedFont();

			if (fontService != null && cachedFont != null)
			{
				let font = cachedFont.Font;
				let atlas = cachedFont.Atlas;
				let atlasTexture = fontService.GetAtlasTexture(cachedFont);

				if (atlas != null && atlasTexture != null)
				{
					drawContext.DrawText(ContentText, font, atlas, atlasTexture, textBounds, .Left, .Middle, foreground);
				}
			}
		}
	}
}
