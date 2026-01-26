namespace ImpactArena;

using System;
using System.Collections;

enum PlayerTitle
{
	Rookie,
	Fighter,
	Warrior,
	Slayer,
	Champion,
	Legend,
	Destroyer,
	Godlike
}

enum AchievementType
{
	// Kill milestones
	FirstBlood,
	Killer25,
	Killer100,
	Killer250,
	Killer500,
	Killer1000,
	Killer2500,
	Killer5000,

	// Wave milestones
	Wave5,
	Wave10,
	Wave15,
	Wave20,

	// Combo milestones
	Combo5,
	Combo10,
	Combo15,

	// Powerup mastery
	ShockwaveMaster,  // 25 kills with shockwave
	EMPMaster,        // 50 kills with EMP
	SpeedDemon,       // 50 kills while speed boosted

	// Special
	Untouchable,      // Complete a wave without taking damage
	Perfectionist,    // Reach wave 5 with full health

	COUNT
}

struct AchievementDef
{
	public StringView Name;
	public StringView Description;
	public PlayerTitle? TitleReward; // If reaching this unlocks a new title
}

class Achievements
{
	// Session stats (persist across deaths within session)
	public int32 TotalKills = 0;
	public int32 HighestWave = 0;
	public int32 HighestCombo = 0;
	public int32 ShockwaveKills = 0;
	public int32 EMPKills = 0;
	public int32 SpeedBoostKills = 0;
	public int32 GamesPlayed = 0;

	// Current game stats (reset each game)
	public int32 CurrentGameKills = 0;
	public int32 CurrentWave = 0;
	public int32 CurrentCombo = 0;
	public bool TookDamageThisWave = false;
	public bool TookDamageThisGame = false;

	// Achievement tracking
	private bool[(int)AchievementType.COUNT] mUnlocked;
	private PlayerTitle mCurrentTitle = .Rookie;

	// Notification queue
	private List<AchievementType> mPendingNotifications = new .() ~ delete _;
	private float mNotificationTimer = 0;
	private AchievementType mCurrentNotification;
	private bool mHasNotification = false;

	// Title notification
	private float mTitleNotificationTimer = 0;
	private PlayerTitle mNewTitle;
	private bool mHasTitleNotification = false;

	public PlayerTitle CurrentTitle => mCurrentTitle;
	public bool HasNotification => mHasNotification;
	public float NotificationTimer => mNotificationTimer;
	public AchievementType CurrentNotification => mCurrentNotification;
	public bool HasTitleNotification => mHasTitleNotification;
	public float TitleNotificationTimer => mTitleNotificationTimer;
	public PlayerTitle NewTitle => mNewTitle;

	private static AchievementDef[(int)AchievementType.COUNT] sAchievementDefs = .(
		// Kill milestones
		.() { Name = "First Blood", Description = "Get your first kill", TitleReward = null },
		.() { Name = "Novice Hunter", Description = "Kill 25 enemies", TitleReward = .Fighter },
		.() { Name = "Seasoned Warrior", Description = "Kill 100 enemies", TitleReward = .Warrior },
		.() { Name = "Deadly Force", Description = "Kill 250 enemies", TitleReward = .Slayer },
		.() { Name = "Unstoppable", Description = "Kill 500 enemies", TitleReward = .Champion },
		.() { Name = "Legendary", Description = "Kill 1000 enemies", TitleReward = .Legend },
		.() { Name = "Annihilator", Description = "Kill 2500 enemies", TitleReward = .Destroyer },
		.() { Name = "Godlike", Description = "Kill 5000 enemies", TitleReward = .Godlike },

		// Wave milestones
		.() { Name = "Survivor", Description = "Reach wave 5", TitleReward = null },
		.() { Name = "Veteran", Description = "Reach wave 10", TitleReward = null },
		.() { Name = "Elite", Description = "Reach wave 15", TitleReward = null },
		.() { Name = "Immortal", Description = "Reach wave 20", TitleReward = null },

		// Combo milestones
		.() { Name = "Combo Starter", Description = "Get a 5x combo", TitleReward = null },
		.() { Name = "Combo Master", Description = "Get a 10x combo", TitleReward = null },
		.() { Name = "Combo King", Description = "Get a 15x combo", TitleReward = null },

		// Powerup mastery
		.() { Name = "Shockwave Master", Description = "Kill 25 with shockwaves", TitleReward = null },
		.() { Name = "EMP Expert", Description = "Kill 50 with EMPs", TitleReward = null },
		.() { Name = "Speed Demon", Description = "Kill 50 while boosted", TitleReward = null },

		// Special
		.() { Name = "Untouchable", Description = "Clear a wave unharmed", TitleReward = null },
		.() { Name = "Perfectionist", Description = "Wave 5 with full health", TitleReward = null }
	);

	public static AchievementDef GetDef(AchievementType type)
	{
		return sAchievementDefs[(int)type];
	}

	public void OnGameStart()
	{
		GamesPlayed++;
		CurrentGameKills = 0;
		CurrentWave = 0;
		CurrentCombo = 0;
		TookDamageThisWave = false;
		TookDamageThisGame = false;
	}

	public void OnWaveStart(int32 wave)
	{
		CurrentWave = wave;
		TookDamageThisWave = false;

		if (wave > HighestWave)
			HighestWave = wave;

		// Check wave milestones
		if (wave >= 5) TryUnlock(.Wave5);
		if (wave >= 10) TryUnlock(.Wave10);
		if (wave >= 15) TryUnlock(.Wave15);
		if (wave >= 20) TryUnlock(.Wave20);

		// Check perfectionist (wave 5 with full health)
		if (wave >= 5 && !TookDamageThisGame)
			TryUnlock(.Perfectionist);
	}

	public void OnWaveComplete()
	{
		// Check untouchable (completed wave without damage)
		if (!TookDamageThisWave)
			TryUnlock(.Untouchable);
	}

	public void OnKill(bool hasSpeedBoost)
	{
		TotalKills++;
		CurrentGameKills++;

		if (hasSpeedBoost)
			SpeedBoostKills++;

		// Check kill milestones
		if (TotalKills >= 1) TryUnlock(.FirstBlood);
		if (TotalKills >= 25) TryUnlock(.Killer25);
		if (TotalKills >= 100) TryUnlock(.Killer100);
		if (TotalKills >= 250) TryUnlock(.Killer250);
		if (TotalKills >= 500) TryUnlock(.Killer500);
		if (TotalKills >= 1000) TryUnlock(.Killer1000);
		if (TotalKills >= 2500) TryUnlock(.Killer2500);
		if (TotalKills >= 5000) TryUnlock(.Killer5000);

		// Check speed demon
		if (SpeedBoostKills >= 50) TryUnlock(.SpeedDemon);
	}

	public void OnShockwaveKills(int32 count)
	{
		ShockwaveKills += count;
		if (ShockwaveKills >= 25) TryUnlock(.ShockwaveMaster);
	}

	public void OnEMPKills(int32 count)
	{
		EMPKills += count;
		if (EMPKills >= 50) TryUnlock(.EMPMaster);
	}

	public void OnCombo(int32 comboCount)
	{
		CurrentCombo = comboCount;
		if (comboCount > HighestCombo)
			HighestCombo = comboCount;

		// Check combo milestones
		if (comboCount >= 5) TryUnlock(.Combo5);
		if (comboCount >= 10) TryUnlock(.Combo10);
		if (comboCount >= 15) TryUnlock(.Combo15);
	}

	public void OnDamageTaken()
	{
		TookDamageThisWave = true;
		TookDamageThisGame = true;
	}

	private void TryUnlock(AchievementType type)
	{
		if (mUnlocked[(int)type])
			return;

		mUnlocked[(int)type] = true;
		mPendingNotifications.Add(type);

		// Check for title reward
		let def = sAchievementDefs[(int)type];
		if (def.TitleReward.HasValue)
		{
			let newTitle = def.TitleReward.Value;
			if ((int)newTitle > (int)mCurrentTitle)
			{
				mCurrentTitle = newTitle;
				mNewTitle = newTitle;
				mHasTitleNotification = true;
				mTitleNotificationTimer = 4.0f; // Title notifications last longer
			}
		}
	}

	public bool IsUnlocked(AchievementType type)
	{
		return mUnlocked[(int)type];
	}

	public void Update(float dt)
	{
		// Handle notification display
		if (mHasNotification)
		{
			mNotificationTimer -= dt;
			if (mNotificationTimer <= 0)
				mHasNotification = false;
		}
		else if (mPendingNotifications.Count > 0)
		{
			mCurrentNotification = mPendingNotifications[0];
			mPendingNotifications.RemoveAt(0);
			mNotificationTimer = 3.0f;
			mHasNotification = true;
		}

		// Handle title notification
		if (mHasTitleNotification)
		{
			mTitleNotificationTimer -= dt;
			if (mTitleNotificationTimer <= 0)
				mHasTitleNotification = false;
		}
	}

	public static void GetTitleString(PlayerTitle title, String outStr)
	{
		switch (title)
		{
		case .Rookie: outStr.Append("Rookie");
		case .Fighter: outStr.Append("Fighter");
		case .Warrior: outStr.Append("Warrior");
		case .Slayer: outStr.Append("Slayer");
		case .Champion: outStr.Append("Champion");
		case .Legend: outStr.Append("Legend");
		case .Destroyer: outStr.Append("Destroyer");
		case .Godlike: outStr.Append("Godlike");
		}
	}

	public int32 GetKillsToNextTitle()
	{
		switch (mCurrentTitle)
		{
		case .Rookie: return 25 - TotalKills;
		case .Fighter: return 100 - TotalKills;
		case .Warrior: return 250 - TotalKills;
		case .Slayer: return 500 - TotalKills;
		case .Champion: return 1000 - TotalKills;
		case .Legend: return 2500 - TotalKills;
		case .Destroyer: return 5000 - TotalKills;
		case .Godlike: return 0; // Max title
		}
	}

	public float GetTitleProgress()
	{
		int32 prevThreshold = 0;
		int32 nextThreshold = 0;

		switch (mCurrentTitle)
		{
		case .Rookie: prevThreshold = 0; nextThreshold = 25;
		case .Fighter: prevThreshold = 25; nextThreshold = 100;
		case .Warrior: prevThreshold = 100; nextThreshold = 250;
		case .Slayer: prevThreshold = 250; nextThreshold = 500;
		case .Champion: prevThreshold = 500; nextThreshold = 1000;
		case .Legend: prevThreshold = 1000; nextThreshold = 2500;
		case .Destroyer: prevThreshold = 2500; nextThreshold = 5000;
		case .Godlike: return 1.0f; // Max title
		}

		let range = nextThreshold - prevThreshold;
		let progress = TotalKills - prevThreshold;
		return Math.Clamp((float)progress / (float)range, 0.0f, 1.0f);
	}
}
