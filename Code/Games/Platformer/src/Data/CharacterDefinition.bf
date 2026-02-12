namespace Platformer.Data;

using System;

enum CharacterType
{
	Oobi,   // Purple - Tough
	Oodi,   // Pink - Speedy
	Ooli,   // Orange - High Jump
	Oopi,   // Teal - Lucky
	Oozi    // Brown - Sturdy
}

struct CharacterDefinition
{
	public CharacterType Type;
	public StringView Name;
	public StringView SkillName;
	public StringView SkillDescription;
	public StringView ModelKey;
	public StringView PreviewImage;

	// Skill multipliers (1.0 = default)
	public float MoveSpeedMultiplier;
	public float JumpMultiplier;
	public int32 MaxHealth;
	public float InvincibilityMultiplier;
	public int32 CoinMultiplier;

	public static CharacterDefinition[5] All = .(
		.() {
			Type = .Oobi,
			Name = "Oobi",
			SkillName = "Tough",
			SkillDescription = "4 HP instead of 3",
			ModelKey = "character_oobi",
			PreviewImage = "character-oobi.png",
			MoveSpeedMultiplier = 1.0f,
			JumpMultiplier = 1.0f,
			MaxHealth = 4,
			InvincibilityMultiplier = 1.0f,
			CoinMultiplier = 1
		},
		.() {
			Type = .Oodi,
			Name = "Oodi",
			SkillName = "Speedy",
			SkillDescription = "+25% move speed",
			ModelKey = "character_oodi",
			PreviewImage = "character-oodi.png",
			MoveSpeedMultiplier = 1.25f,
			JumpMultiplier = 1.0f,
			MaxHealth = 3,
			InvincibilityMultiplier = 1.0f,
			CoinMultiplier = 1
		},
		.() {
			Type = .Ooli,
			Name = "Ooli",
			SkillName = "High Jump",
			SkillDescription = "+20% jump height",
			ModelKey = "character_ooli",
			PreviewImage = "character-ooli.png",
			MoveSpeedMultiplier = 1.0f,
			JumpMultiplier = 1.2f,
			MaxHealth = 3,
			InvincibilityMultiplier = 1.0f,
			CoinMultiplier = 1
		},
		.() {
			Type = .Oopi,
			Name = "Oopi",
			SkillName = "Lucky",
			SkillDescription = "Coins worth 2x",
			ModelKey = "character_oopi",
			PreviewImage = "character-oopi.png",
			MoveSpeedMultiplier = 1.0f,
			JumpMultiplier = 1.0f,
			MaxHealth = 3,
			InvincibilityMultiplier = 1.0f,
			CoinMultiplier = 2
		},
		.() {
			Type = .Oozi,
			Name = "Oozi",
			SkillName = "Sturdy",
			SkillDescription = "+50% invincibility time",
			ModelKey = "character_oozi",
			PreviewImage = "character-oozi.png",
			MoveSpeedMultiplier = 1.0f,
			JumpMultiplier = 1.0f,
			MaxHealth = 3,
			InvincibilityMultiplier = 1.5f,
			CoinMultiplier = 1
		}
	);

	/// Gets the definition for a given character type.
	public static CharacterDefinition Get(CharacterType type)
	{
		return All[(int)type];
	}

	/// Gets the enemy fallback model key when the player selects a character
	/// that matches an enemy's default model.
	public static StringView GetEnemyModelKey(EnemyType enemyType, CharacterType playerCharacter)
	{
		// Default enemy → character mappings:
		// Slime → oozi (brown), Bee → ooli (orange), Crab → oodi (pink), Skull → oobi (purple)
		// If player is using the same character, swap enemy to oopi (teal)

		switch (enemyType)
		{
		case .Slime:
			return playerCharacter == .Oozi ? "character_oopi" : "enemy_slime";
		case .Bee:
			return playerCharacter == .Ooli ? "character_oopi" : "enemy_bee";
		case .Crab:
			return playerCharacter == .Oodi ? "character_oopi" : "enemy_crab";
		case .Skull:
			return playerCharacter == .Oobi ? "character_oopi" : "enemy_skull";
		}
	}
}
