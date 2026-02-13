namespace StormTactics.Client;

using System;
using System.Collections;
using Sedulous.Drawing;
using StormTactics.Core;

/// Generates placeholder OwnedImageData icons (64x64 RGBA8) for units, items, and equips.
/// Icons use class/type-based gradient fills with rarity-colored borders.
static class IconGenerator
{
	public const uint32 ICON_SIZE = 64;
	private const int32 BORDER = 3;

	// --- Rarity border colors ---

	private static void GetRarityColor(Rarity rarity, out uint8 r, out uint8 g, out uint8 b)
	{
		switch (rarity)
		{
		case .Common:    r = 180; g = 180; b = 180; // Gray
		case .Uncommon:  r = 60;  g = 180; b = 60;  // Green
		case .Rare:      r = 60;  g = 120; b = 220; // Blue
		case .Epic:      r = 160; g = 60;  b = 220; // Purple
		case .Legendary: r = 240; g = 180; b = 40;  // Gold
		default:         r = 128; g = 128; b = 128;
		}
	}

	// --- Unit class gradient colors ---

	private static void GetUnitClassColors(UnitClass unitClass,
		out uint8 topR, out uint8 topG, out uint8 topB,
		out uint8 botR, out uint8 botG, out uint8 botB)
	{
		switch (unitClass)
		{
		case .Infantry:
			topR = 140; topG = 80;  topB = 60;   // Brown
			botR = 90;  botG = 50;  botB = 35;
		case .Cavalry:
			topR = 60;  topG = 100; topB = 160;  // Steel blue
			botR = 40;  botG = 65;  botB = 105;
		case .Ranged:
			topR = 60;  topG = 140; topB = 60;   // Forest green
			botR = 35;  botG = 90;  botB = 35;
		case .Mage:
			topR = 120; topG = 60;  topB = 160;  // Purple
			botR = 75;  botG = 35;  botB = 105;
		case .Support:
			topR = 200; topG = 180; topB = 80;   // Gold/yellow
			botR = 140; botG = 120; botB = 50;
		case .Siege:
			topR = 100; topG = 100; topB = 100;  // Gray
			botR = 60;  botG = 60;  botB = 60;
		default:
			topR = 80; topG = 80; topB = 80;
			botR = 50; botG = 50; botB = 50;
		}
	}

	// --- Item type colors ---

	private static void GetItemTypeColors(ItemType itemType,
		out uint8 topR, out uint8 topG, out uint8 topB,
		out uint8 botR, out uint8 botG, out uint8 botB)
	{
		switch (itemType)
		{
		case .Material:
			topR = 140; topG = 120; topB = 80;   // Tan
			botR = 90;  botG = 75;  botB = 50;
		case .Consumable:
			topR = 180; topG = 60;  topB = 60;   // Red
			botR = 120; botG = 35;  botB = 35;
		case .Currency:
			topR = 220; topG = 190; topB = 60;   // Gold
			botR = 160; botG = 130; botB = 40;
		case .UnitShard:
			topR = 100; topG = 180; topB = 220;  // Cyan
			botR = 60;  botG = 120; botB = 160;
		default:
			topR = 80; topG = 80; topB = 80;
			botR = 50; botG = 50; botB = 50;
		}
	}

	// --- Equip slot colors ---

	private static void GetEquipSlotColors(EquipSlot slot,
		out uint8 topR, out uint8 topG, out uint8 topB,
		out uint8 botR, out uint8 botG, out uint8 botB)
	{
		switch (slot)
		{
		case .Weapon:
			topR = 180; topG = 80;  topB = 60;   // Fiery red
			botR = 120; botG = 50;  botB = 35;
		case .Armor:
			topR = 80;  topG = 100; topB = 160;  // Steel blue
			botR = 50;  botG = 65;  botB = 105;
		case .Accessory:
			topR = 140; topG = 180; topB = 80;   // Lime green
			botR = 90;  botG = 120; botB = 50;
		default:
			topR = 80; topG = 80; topB = 80;
			botR = 50; botG = 50; botB = 50;
		}
	}

	// --- Icon Generation ---

	/// Generate a unit icon with class-based gradient and rarity border.
	/// Caller owns the returned OwnedImageData.
	public static OwnedImageData GenerateUnitIcon(UnitClass unitClass, Rarity rarity)
	{
		uint8 borderR, borderG, borderB;
		GetRarityColor(rarity, out borderR, out borderG, out borderB);

		uint8 topR, topG, topB, botR, botG, botB;
		GetUnitClassColors(unitClass, out topR, out topG, out topB, out botR, out botG, out botB);

		return CreateGradientIcon(topR, topG, topB, botR, botG, botB, borderR, borderG, borderB);
	}

	/// Generate an item icon with type-based colors and common gray border.
	public static OwnedImageData GenerateItemIcon(ItemType itemType)
	{
		uint8 topR, topG, topB, botR, botG, botB;
		GetItemTypeColors(itemType, out topR, out topG, out topB, out botR, out botG, out botB);

		return CreateGradientIcon(topR, topG, topB, botR, botG, botB, 160, 160, 160);
	}

	/// Generate an equip icon with slot-based colors and rarity border.
	public static OwnedImageData GenerateEquipIcon(EquipSlot slot, Rarity rarity)
	{
		uint8 borderR, borderG, borderB;
		GetRarityColor(rarity, out borderR, out borderG, out borderB);

		uint8 topR, topG, topB, botR, botG, botB;
		GetEquipSlotColors(slot, out topR, out topG, out topB, out botR, out botG, out botB);

		return CreateGradientIcon(topR, topG, topB, botR, botG, botB, borderR, borderG, borderB);
	}

	/// Create a 64x64 RGBA8 gradient icon with a colored border.
	private static OwnedImageData CreateGradientIcon(
		uint8 topR, uint8 topG, uint8 topB,
		uint8 botR, uint8 botG, uint8 botB,
		uint8 borderR, uint8 borderG, uint8 borderB)
	{
		let pixels = new uint8[ICON_SIZE * ICON_SIZE * 4];

		for (uint32 y = 0; y < ICON_SIZE; y++)
		{
			for (uint32 x = 0; x < ICON_SIZE; x++)
			{
				let idx = (y * ICON_SIZE + x) * 4;
				bool isBorder = x < BORDER || x >= ICON_SIZE - BORDER ||
								y < BORDER || y >= ICON_SIZE - BORDER;

				if (isBorder)
				{
					pixels[idx + 0] = borderR;
					pixels[idx + 1] = borderG;
					pixels[idx + 2] = borderB;
					pixels[idx + 3] = 255;
				}
				else
				{
					// Vertical gradient
					float t = (float)y / (float)(ICON_SIZE - 1);
					pixels[idx + 0] = (uint8)((float)topR + t * (float)((int32)botR - (int32)topR));
					pixels[idx + 1] = (uint8)((float)topG + t * (float)((int32)botG - (int32)topG));
					pixels[idx + 2] = (uint8)((float)topB + t * (float)((int32)botB - (int32)topB));
					pixels[idx + 3] = 255;
				}
			}
		}

		return new OwnedImageData(ICON_SIZE, ICON_SIZE, .RGBA8, pixels);
	}
}
