using System;
using System.Collections;
using Sedulous.Mathematics;
using Sedulous.UI;

namespace Sedulous.Framework.UI;

/// Represents a single action slot in the action bar.
class ActionSlot
{
	private int32 mIndex;
	private TextureHandle mIcon;
	private KeyCode mHotkey = .Unknown;
	private float mCooldownRemaining = 0;
	private int32 mCharges = 0;
	private int32 mMaxCharges = 0;
	private bool mIsUsable = true;
	private String mTooltip = new .() ~ delete _;

	/// Gets the slot index.
	public int32 Index => mIndex;

	/// Gets or sets the icon texture.
	public TextureHandle Icon
	{
		get => mIcon;
		set => mIcon = value;
	}

	/// Gets or sets the hotkey for this action.
	public KeyCode Hotkey
	{
		get => mHotkey;
		set => mHotkey = value;
	}

	/// Gets or sets the cooldown remaining (0 to 1).
	public float CooldownRemaining
	{
		get => mCooldownRemaining;
		set => mCooldownRemaining = Math.Clamp(value, 0, 1);
	}

	/// Gets whether the action is on cooldown.
	public bool IsOnCooldown => mCooldownRemaining > 0;

	/// Gets or sets the current charges.
	public int32 Charges
	{
		get => mCharges;
		set => mCharges = Math.Max(0, value);
	}

	/// Gets or sets the maximum charges.
	public int32 MaxCharges
	{
		get => mMaxCharges;
		set => mMaxCharges = Math.Max(0, value);
	}

	/// Gets whether the slot uses charges.
	public bool HasCharges => mMaxCharges > 0;

	/// Gets or sets whether the action is usable.
	public bool IsUsable
	{
		get => mIsUsable;
		set => mIsUsable = value;
	}

	/// Gets whether the action can be activated.
	public bool CanActivate => mIsUsable && !IsOnCooldown && (!HasCharges || mCharges > 0);

	/// Gets or sets the tooltip text.
	public String Tooltip
	{
		get => mTooltip;
		set
		{
			mTooltip.Set(value);
		}
	}

	public this(int32 index)
	{
		mIndex = index;
	}

	/// Clears the slot.
	public void Clear()
	{
		mIcon = default;
		mHotkey = .Unknown;
		mCooldownRemaining = 0;
		mCharges = 0;
		mMaxCharges = 0;
		mIsUsable = true;
		mTooltip.Clear();
	}
}

/// Action bar / hotbar for game abilities.
class ActionBar : Widget
{
	private int32 mSlotCount = 10;
	private float mSlotSize = 48;
	private float mSlotSpacing = 4;
	private Orientation mOrientation = .Horizontal;
	private List<ActionSlot> mSlots = new .() ~ DeleteContainerAndItems!(_);
	private int32 mHoveredIndex = -1;
	private Color mSlotBackground = Color(40, 40, 40, 255);
	private Color mSlotBorder = Color(60, 60, 60, 255);
	private Color mHoverBorder = Color(100, 149, 237, 255);
	private Color mCooldownOverlay = Color(0, 0, 0, 180);
	private Color mUnusableOverlay = Color(50, 0, 0, 150);

	/// Event raised when a slot is activated.
	public Event<delegate void(int32)> OnSlotActivated ~ _.Dispose();

	/// Gets or sets the number of slots.
	public int32 SlotCount
	{
		get => mSlotCount;
		set
		{
			if (mSlotCount != value)
			{
				mSlotCount = Math.Max(1, value);
				RebuildSlots();
			}
		}
	}

	/// Gets or sets the slot size.
	public float SlotSize
	{
		get => mSlotSize;
		set
		{
			mSlotSize = Math.Max(16, value);
			InvalidateMeasure();
		}
	}

	/// Gets or sets the spacing between slots.
	public float SlotSpacing
	{
		get => mSlotSpacing;
		set
		{
			mSlotSpacing = Math.Max(0, value);
			InvalidateMeasure();
		}
	}

	/// Gets or sets the bar orientation.
	public Orientation Orientation
	{
		get => mOrientation;
		set
		{
			mOrientation = value;
			InvalidateMeasure();
		}
	}

	/// Gets the action slots.
	public List<ActionSlot> Slots => mSlots;

	public this()
	{
		IsFocusable = true;
		RebuildSlots();
	}

	private void RebuildSlots()
	{
		while (mSlots.Count < mSlotCount)
		{
			mSlots.Add(new ActionSlot((int32)mSlots.Count));
		}
		while (mSlots.Count > mSlotCount)
		{
			delete mSlots.PopBack();
		}
		InvalidateMeasure();
		InvalidateVisual();
	}

	/// Gets a slot by index.
	public ActionSlot GetSlot(int32 index)
	{
		if (index >= 0 && index < mSlots.Count)
			return mSlots[index];
		return null;
	}

	/// Activates a slot by index.
	public bool ActivateSlot(int32 index)
	{
		let slot = GetSlot(index);
		if (slot != null && slot.CanActivate)
		{
			OnSlotActivated(index);
			return true;
		}
		return false;
	}

	/// Gets the slot index at a local position.
	private int32 GetSlotAtPosition(Vector2 localPos)
	{
		let bounds = ContentBounds;
		let cellSize = mSlotSize + mSlotSpacing;

		float rel;
		if (mOrientation == .Horizontal)
			rel = localPos.X - bounds.X;
		else
			rel = localPos.Y - bounds.Y;

		let index = (int32)(rel / cellSize);
		if (index < 0 || index >= mSlotCount)
			return -1;

		// Check if in slot bounds (not spacing)
		let slotStart = index * cellSize;
		if (rel >= slotStart && rel < slotStart + mSlotSize)
			return index;

		return -1;
	}

	private RectangleF GetSlotBounds(int32 index)
	{
		let bounds = ContentBounds;
		let cellSize = mSlotSize + mSlotSpacing;

		if (mOrientation == .Horizontal)
		{
			return RectangleF(
				bounds.X + index * cellSize,
				bounds.Y,
				mSlotSize,
				mSlotSize
			);
		}
		else
		{
			return RectangleF(
				bounds.X,
				bounds.Y + index * cellSize,
				mSlotSize,
				mSlotSize
			);
		}
	}

	protected override bool OnMouseMove(MouseMoveEventArgs e)
	{
		let index = GetSlotAtPosition(e.Position);
		if (index != mHoveredIndex)
		{
			mHoveredIndex = index;
			InvalidateVisual();
		}
		return base.OnMouseMove(e);
	}

	protected override bool OnMouseDown(MouseButtonEventArgs e)
	{
		if (e.Button == .Left)
		{
			let index = GetSlotAtPosition(e.Position);
			if (index >= 0)
			{
				ActivateSlot(index);
				return true;
			}
		}
		return base.OnMouseDown(e);
	}

	protected override bool OnMouseLeave(MouseEventArgs e)
	{
		mHoveredIndex = -1;
		InvalidateVisual();
		return base.OnMouseLeave(e);
	}

	protected override bool OnKeyDown(KeyEventArgs e)
	{
		// Check for hotkey match
		for (let slot in mSlots)
		{
			if (slot.Hotkey != .Unknown && slot.Hotkey == e.Key)
			{
				if (ActivateSlot(slot.Index))
				{
					e.Handled = true;
					return true;
				}
			}
		}

		// Number keys 1-0 as default hotkeys
		int32 numIndex = -1;
		if (e.Key >= .Num1 && e.Key <= .Num9)
			numIndex = (int32)e.Key - (int32)KeyCode.Num1;
		else if (e.Key == .Num0)
			numIndex = 9;

		if (numIndex >= 0 && numIndex < mSlotCount)
		{
			if (ActivateSlot(numIndex))
			{
				e.Handled = true;
				return true;
			}
		}

		return base.OnKeyDown(e);
	}

	protected override void OnRender(DrawContext dc)
	{
		for (int32 i = 0; i < mSlots.Count; i++)
		{
			let slot = mSlots[i];
			let bounds = GetSlotBounds(i);
			RenderSlot(dc, slot, bounds, i == mHoveredIndex);
		}
	}

	private void RenderSlot(DrawContext dc, ActionSlot slot, RectangleF bounds, bool isHovered)
	{
		// Background
		dc.FillRect(bounds, mSlotBackground);

		// Icon
		if (slot.Icon.IsValid)
		{
			let iconTint = slot.IsUsable ? Color.White : Color(128, 128, 128, 255);
			dc.DrawImage(slot.Icon, bounds, iconTint);
		}

		// Cooldown overlay
		if (slot.IsOnCooldown)
		{
			let cooldownHeight = bounds.Height * slot.CooldownRemaining;
			let cooldownBounds = RectangleF(
				bounds.X,
				bounds.Y + bounds.Height - cooldownHeight,
				bounds.Width,
				cooldownHeight
			);
			dc.FillRect(cooldownBounds, mCooldownOverlay);
		}

		// Unusable overlay
		if (!slot.IsUsable)
		{
			dc.FillRect(bounds, mUnusableOverlay);
		}

		// Border
		let borderColor = isHovered ? mHoverBorder : mSlotBorder;
		dc.DrawRect(bounds, borderColor, isHovered ? 2 : 1);
	}

	protected override Vector2 MeasureOverride(Vector2 availableSize)
	{
		let totalSize = mSlotCount * mSlotSize + (mSlotCount - 1) * mSlotSpacing;
		if (mOrientation == .Horizontal)
			return Vector2(totalSize, mSlotSize);
		else
			return Vector2(mSlotSize, totalSize);
	}
}
