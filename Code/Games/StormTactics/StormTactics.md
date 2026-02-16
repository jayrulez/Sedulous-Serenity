# Storm Tactics - Turn-Based Tactical RPG Design & Implementation Plan

A hex-grid turn-based tactical RPG inspired by StormWar, built on the Sedulous-Serenity engine in Beef.

---

## Game Overview

**Core Loop:** Collect units (cards) → Build formations → Fight hex-grid tactical battles → Earn rewards → Upgrade units → Repeat

**Key Pillars:**
- Deep tactical hex-grid combat with varied unit types, skills, and buffs
- Unit collection and progression (star levels, equipment, skill unlocks)
- PvE campaign with story stages plus PvP arena
- Guild and social features
- Data-driven design: all units, skills, buffs, stages defined in config files

---

## Architecture Overview

```
StormTactics/
├── StormTactics.Core/           # Shared data types, configs, enums
├── StormTactics.Battle/         # Battle simulation (deterministic, no rendering)
├── StormTactics.Game/           # Game systems (progression, inventory, economy)
├── StormTactics.Client/         # Client app (rendering, UI, input, audio)
├── StormTactics.Server/         # Server library (auth, sessions, player data, routes)
└── StormTactics.ServerApp/      # Standalone server executable
```

**Separation principle:** The battle simulation (`StormTactics.Battle`) must be pure logic with zero rendering dependencies. This allows:
- Server-side battle validation
- Replay recording/playback
- AI testing without rendering
- Deterministic outcomes

---

## Data-Driven Config Format

All game data (units, skills, buffs, stages, items, equipment) will use the existing **Sedulous.Serialization** framework with the **XML** format. Config structs implement `ISerializable` with `Serialize(Serializer s)` and are loaded/saved via `XmlSerializer`. The engine loads these at startup. Balancing changes require only config edits, no recompilation. XML is human-readable and easy to hand-edit for balancing.

Dependencies: `Sedulous.Serialization`, `Sedulous.Serialization.Xml`, `Sedulous.Xml`.

---

## Phase 1: Core Data Model & Config System

Foundation layer — define all the data structures and the config loading pipeline.

### Checklist

- [x] **Project scaffolding**
  - [x] Create `StormTactics.Core` library project
  - [x] Create `StormTactics.Battle` library project
  - [x] Create `StormTactics.Game` library project
  - [x] Create `StormTactics.Client` application project
  - [x] Register all projects in `BeefSpace.toml`
  - [x] Set up inter-project dependencies

- [x] **Enums & constants** (`StormTactics.Core`)
  - [x] `DamageType` — Physical, Piercing, Magic
  - [x] `MoveType` — Land, Flying
  - [x] `UnitRace` — Human, Undead, Beast, Demon, Elemental, Divine
  - [x] `UnitClass` — Tank, Striker, Ranger, Caster, Healer, Siege
  - [x] `Rarity` — Common (1), Uncommon (2), Rare (3), Epic (4), Legendary (5)
  - [x] `AttackPattern` — Point, Line2, Line3, AroundSelf3, AroundSelfAll, AroundTarget, AllEnemies
  - [x] `BuffFlag` — Positive, Negative
  - [x] `BuffTag` — Stun, Slow, Poison, Burn, Freeze, Silence, Charm, Shield, Regen, AttackUp/Down, DefenseUp/Down, SpeedUp/Down, Immune
  - [x] `SkillMoment` (trigger) — Passive, OnBattleStart, OnActionBegin, OnAttack, OnHit, OnDamaged, OnKill, OnDeath, OnTurnEnd
  - [x] `SkillTarget` — Self, SingleEnemy, SingleAlly, AllEnemies, AllAllies, MostWoundedAlly, RandomEnemy, RandomAlly
  - [x] `Force` — Attacker, Defender
  - [x] `GridState` — Walkable, Blocked, Occupied, Invalid
  - [x] `GameState` — Loading, MainMenu, City, BattlePrepare, Battle, BattleResult, Campaign, Shop, UnitManagement, Arena, Guild, Settings
  - [x] `ItemType` — Material, Consumable, Currency, UnitShard
  - [x] `EquipSlot` — Weapon, Armor, Accessory
  - [x] `CurrencyType` — Gold, Gems, ArenaTokens, GuildTokens
  - [x] `SkillEffectType` — Damage, Heal, ApplyBuff, Dispel, Summon, Counter
  - [x] `StatAttribute` — HP, Damage, Defense, ActionSpeed, MoveRange, AttackRange

- [x] **Core data structures** (`StormTactics.Core`)
  - [x] `UnitConfig` — id, name, rarity, unitClass, race, soldierHP, soldierCount, defense, soldierDamage, damageType, isRanged, attackRange, attackPattern, moveType, moveRange, actionSpeed, skillIds[], icon, modelName
  - [x] `SkillConfig` — id, name, description, icon, moment, target, cooldown, chance, maxUsesPerBattle, effects[] (SkillEffect: type, value, buffId, summonUnitId, dispelCount)
  - [x] `BuffConfig` — id, name, description, icon, flag, tag, duration, canDispel, dotDamage, hotHeal, statModifiers[] (StatModifier: attribute, flatValue, percentValue)
  - [x] `StageConfig` — id, name, chapter, difficulty, staminaCost, recommendedPower, unlockStageId, enemyFormation[] (FormationSlot), rewards[] (RewardEntry)
  - [x] `ItemConfig` — id, name, description, icon, type, stackMax
  - [x] `EquipConfig` — id, name, description, icon, slot, rarity, requiredLevel, statBonuses[]
  - [x] `HeroLevelConfig` — level, expRequired, maxStamina, maxFormationSlots
  - [x] `StarLevelConfig` — unitId, starLevel, shardsRequired, hpMultiplier, damageMultiplier, defenseMultiplier, unlockedSkillIds[]
  - [x] `ShopItemConfig` — id, itemId, quantity, cost, currencyType, purchaseLimit, refreshGroup
  - [x] Helper types: `StatModifier`, `SkillEffect`, `FormationSlot`, `RewardEntry` (all ISerializable)
  - [x] String fields for asset references (icons, models) — will become ResourceRef when asset pipeline is integrated

- [x] **Config loader system** (using `Sedulous.Serialization` + XML)
  - [x] All config structs implement `ISerializable` with `Serialize(Serializer s)`
  - [x] Load configs via `XmlSerializer.CreateReader()`
  - [x] `ConfigDatabase` class — central registry of all loaded configs
  - [x] Loader for each config type (UnitConfig, SkillConfig, BuffConfig, etc.)
  - [x] Validation pass on load (check all referenced IDs exist, no broken links)
  - [x] ~~Hot-reload support for development iteration~~ (deferred — not needed in early dev; configs reload by restarting)

- [x] **Write initial test configs** (`Assets/StormTactics/configs/`)
  - [x] 10 sample unit configs covering all classes (`units.xml`)
  - [x] 15 sample skill configs (passive, active, triggered) (`skills.xml`)
  - [x] 10 sample buff configs (positive and negative) (`buffs.xml`)
  - [x] 5 sample stage configs (`stages.xml`)
  - [x] Sample item and equipment configs (`items.xml`, `equips.xml`, `shop.xml`, `hero_levels.xml`, `star_levels.xml`)

---

## Phase 2: Hex Grid & Pathfinding

The tactical foundation — hex grid math, coordinate systems, pathfinding.

### Checklist

- [x] **Hex coordinate system** (`StormTactics.Battle`)
  - [x] `HexCoord` struct — axial coordinates (q, r) with conversions
  - [x] Hex distance calculation
  - [x] Hex neighbor enumeration (6 directions)
  - [x] Hex line drawing (for line-of-sight and line attacks)
  - [x] Hex ring and spiral enumeration (for AOE patterns)
  - [x] Axial ↔ offset coordinate conversion
  - [x] Hex ↔ world-space (pixel) coordinate conversion

- [x] **HexGrid class**
  - [x] Grid creation with configurable columns × rows
  - [x] Cell state management (walkable, blocked, occupied)
  - [x] Get/set occupying unit per cell
  - [x] Query cells in range (movement range, attack range)
  - [x] Query cells matching attack pattern (Point, Line2, Line3, AroundSelf, AroundTarget, All)
  - [x] Validate coordinate bounds

- [x] **Pathfinding**
  - [x] A* pathfinder for hex grid
  - [x] Movement cost calculation (uniform for land; flying ignores obstacles)
  - [x] Path result: list of HexCoord via outPath parameter
  - [x] Reachable-cells query (all cells within N steps)
  - [x] Blocked-cell handling (units block movement, not just terrain)

- [x] **Unit tests** (`StormTactics.Tests`)
  - [x] Hex math correctness (distance, neighbors, rings)
  - [x] Pathfinding basic cases (open field, obstacles, unreachable)
  - [x] Attack pattern cell queries

---

## Phase 3: Battle Simulation (Core Logic)

Pure-logic battle system with no rendering. This is the heart of the game.

### Checklist

- [x] **Unit runtime state** (`BattleUnit`)
  - [x] Reference to `UnitConfig`
  - [x] Current HP, max HP
  - [x] Current soldier count (HP / soldierHP, affects damage output)
  - [x] Position (`HexCoord`)
  - [x] Force (attacker/defender)
  - [x] Action timer (time until next turn)
  - [x] Active buffs list (buff instance with remaining duration)
  - [x] Skill cooldown trackers
  - [x] Status flags (alive, stunned, charmed, silenced)
  - [x] Formation slot index
  - [x] Stat modifiers from buffs/equipment (cached, recalculated on buff change)

- [x] **Turn order system**
  - [x] Speed-based action scheduling: `timeToAct = TIME_UNIT / actionSpeed`
  - [x] Priority queue or sorted list of units by remaining time
  - [x] Advance time to next unit's action
  - [x] Handle ties (defender-favored or random)
  - [x] `GetNextUnit()` → returns the unit whose turn it is

- [x] **Action system**
  - [x] `BattleAction` base with subtypes: Move, Attack, UseSkill, Wait
  - [x] Movement execution — validate path, update grid, update position
  - [x] Attack execution — select target, calculate damage, apply damage
  - [x] Skill execution — check cooldown/conditions, resolve skill effects
  - [x] Action validation (can this unit do this action right now?)

- [x] **Damage calculation**
  - [x] Base formula: `rawDamage = attackerSoldierCount * soldierDamage * multiplier`
  - [x] Defense reduction: `finalDamage = rawDamage * (1 - defenseReduction)`
  - [x] Damage type interactions (piercing ignores some armor, magic ignores physical defense)
  - [x] Soldier count update after taking damage: `remainingSoldiers = ceil(currentHP / soldierHP)`
  - [x] Overkill handling
  - [x] Damage events for buff triggers

- [x] **Healing system**
  - [x] Heal amount calculation
  - [x] HP cap enforcement
  - [x] Soldier count restoration
  - [x] Heal events for buff triggers

- [x] **Buff/debuff system**
  - [x] `BuffInstance` — config ref, remaining duration, source unit
  - [x] Apply buff: add to unit, recalculate stats
  - [x] Remove buff: remove from unit, recalculate stats
  - [x] Tick buffs on turn start/end: reduce duration, apply DoT/HoT
  - [x] Dispel: remove N positive/negative buffs
  - [x] Buff stacking rules (same buff refreshes duration? stacks? replaces?)
  - [x] Immunity checks (certain units immune to certain buff tags)

- [x] **Skill system**
  - [x] Skill trigger evaluation — check moment, conditions, proc chance
  - [x] Skill effect resolution — damage, heal, apply buff, dispel, summon, counter-attack
  - [x] Passive skill registration (evaluated automatically at their trigger moment)
  - [x] Active skill AI/player selection
  - [x] Cooldown tracking and reset
  - [x] Counter-attack skill: triggers when unit is attacked, limited uses per turn
  - [x] AOE skill: resolve effect on all targets in pattern

- [x] **Battle flow controller** (`BattleSimulation`)
  - [x] `Initialize(attackerFormation, defenderFormation, stageConfig)` — place units on grid
  - [x] `Step()` — advance to next action, resolve it, return events
  - [x] `IsFinished()` — check win/loss/draw conditions
  - [x] `GetResult()` — winner, surviving units, rewards, stats
  - [x] Battle event log (for replay and UI): UnitMoved, UnitAttacked, DamageDealt, UnitDied, BuffApplied, SkillUsed, etc.
  - [x] Max turn limit (prevent infinite battles)

- [x] **AI system**
  - [x] `BattleAI` — decides actions for computer-controlled units
  - [x] Target selection heuristics: lowest HP, highest threat, type advantage
  - [x] Movement heuristics: move toward nearest attackable target, stay in range
  - [x] Skill usage heuristics: use heal when ally below threshold, use AOE when enemies clustered
  - [x] Priority system: heal > buff > attack
  - [x] Difficulty levels (random choices vs. optimal play)

- [x] **Battle events**
  - [x] `BattleEvent` union/enum with data for each event type
  - [x] Event queue populated during `Step()`
  - [x] Events consumed by client for animation/UI (or by server for validation)
  - [x] Replay: full battle reproducible from initial state + event log

- [x] **Unit tests** (`BattleSimulationTests`)
  - [x] Damage calculation correctness
  - [x] Turn order with varying speeds
  - [x] Buff application and expiry
  - [x] Skill trigger conditions (cooldowns)
  - [x] Win/loss detection
  - [x] Full battle simulation (known outcome with fixed seed)

---

## Phase 4: Client Foundation & Battle Rendering

Bring the battle to life with the Sedulous engine.

### Checklist

- [x] **Application setup** (`StormTactics.Client`)
  - [x] Extend `Application` from Sedulous.Framework.Runtime
  - [x] Register required subsystems (Scene, Render)
  - [x] Game state machine (Campaign → BattlePrepare → Battle → result → Campaign loop)
  - [ ] Asset loading pipeline (placeholder meshes for now)
  - [x] Frame update loop delegating to current game state

- [x] **Hex grid rendering**
  - [x] Hex tile mesh generation (flat hexagons — procedural StaticMesh)
  - [x] Grid layout matching battle simulation coordinates
  - [x] Cell highlighting (selected = yellow, extensible)
  - [x] Hover detection — screen ray → hex coordinate mapping
  - [x] Grid lines / cell border rendering (DebugRenderFeature)
  - [x] Team color coding (attacker side vs defender side)

- [x] **Unit rendering** (placeholder cylinders — designed for real asset swap)
  - [x] Placeholder unit meshes (cylinders) with fallback warnings for missing models
  - [x] Place units on hex grid at correct world positions
  - [ ] Unit idle animation (needs real assets)
  - [x] Unit walk/move animation along path (smooth interpolation)
  - [x] Unit attack animation (lunge toward target)
  - [x] Unit hit/damage reaction animation (flash red)
  - [x] Unit death animation (sink + shrink)
  - [x] Unit facing direction (face toward target during attack)
  - [x] Health bar above each unit (debug text overlay)
  - [x] Soldier count display (debug text above unit)
  - [x] Buff/debuff icons near unit

- [x] **Battle camera**
  - [x] Fixed isometric/top-down camera viewing the hex grid
  - [x] Camera pan (WASD, scales with zoom)
  - [x] Camera zoom (Q/E/mouse wheel)
  - [x] Camera focus on active unit during their turn
  - [x] Smooth camera transitions between points of interest

- [x] **Battle animation sequencer**
  - [x] Consume `BattleEvent` queue from simulation
  - [x] Map events to visual sequences (move → attack → damage flash → death)
  - [x] Sequential playback with timing
  - [x] Speed control (1x, 2x, 4x, skip all)
  - [x] Wait for animation completion before next event
  - [ ] Particle effects for skills (fire, lightning, heal glow, etc.)
  - [x] Floating damage numbers
  - [x] Floating heal numbers (green)

- [x] **Battle VFX** (placeholder debug shapes — real particles pending)
  - [ ] Attack impact effects (slash, arrow hit, spell hit)
  - [x] Skill cast effects (expanding circle at caster)
  - [x] Buff/debuff application effects (rising/shrinking rings)
  - [x] Death/despawn effect (sink + shrink animation)
  - [ ] AOE area highlight before skill resolution
  - [x] Critical hit emphasis (larger floating number with "!")

---

## Phase 5: Battle UI

The interface layer for tactical combat.

### Checklist

- [x] **Battle HUD** (retained-mode UI via Sedulous.GUI / UISubsystem)
  - [x] Turn order bar (horizontal strip showing upcoming unit turns)
  - [x] Current unit info panel (name, HP bar, class, ATK/DEF/SPD stats)
  - [x] Action buttons (Move, Attack, Skill, Wait/End Turn)
  - [x] Skill selection panel (list active skills with cooldowns)
  - [x] Target info panel (shows stats of hovered/targeted enemy)
  - [x] Battle speed controls (1x, 2x, 4x, Step, Auto, Skip)
  - [ ] Pause/settings button

- [x] **Player interaction flow**
  - [x] Player's turn: highlight active unit → show action buttons
  - [x] Move action: show reachable cells → click to move → animate
  - [x] Attack action: show attackable targets → click target → resolve & animate
  - [x] Skill action: show skill panel → select skill → show valid targets → click → resolve
  - [x] Auto-battle toggle: AI controls player units
  - [x] Move + action in same turn (move then attack/skill/wait)
  - [x] Undo move (before committing attack)

- [x] **Battle results screen**
  - [x] Victory / Defeat / Draw banner (overlay with result text)
  - [x] Star rating (based on remaining HP, turns taken, units lost)
  - [x] Battle stats display (turns, survivors, kills, damage, healing)
  - [x] EXP gained (shown in rewards section)
  - [x] Loot/rewards display (gold, EXP, item drops)
  - [x] "Continue" button (returns to city hub)

- [x] **Pre-battle (deployment) screen**
  - [x] Show enemy formation preview (red-highlighted defender hexes)
  - [x] Player's deployment grid (their side of the hex map)
  - [x] Click-to-select and click-to-swap/move units in deployment zone
  - [x] Unit info on hover (via bottom panel after battle starts; hint text during deploy)
  - [x] Formation preset selection and roster add/remove during deployment
  - [x] Save current deployment as formation preset
  - [x] "Start Battle" button
  - [ ] Recommended power level indicator

---

## Phase 6: Metagame Systems

Everything outside of battle — the RPG progression layer. Uses XML save/load via `SaveManager`. City hub is the central navigation screen. Placeholder icons generated programmatically via `IconGenerator` (64x64 RGBA8 `OwnedImageData`).

### Checklist

- [x] **Save system** (`SaveManager`, `PlayerSaveData`)
  - [x] XML save/load via `XmlSerializer` to `{AssetDir}/StormTactics/save/player_save.xml`
  - [x] Auto-save on return to city hub and on exit
  - [x] New game initialization with starter units (Footman, Archer, Priest)

- [x] **Player profile system** (`PlayerManager`)
  - [x] Player level and EXP with level-up
  - [x] Stamina system (spent to enter battles, scales with hero level, regenerates over time)
  - [x] Currency tracking (gold, gems)
  - [x] Stage unlock and clear tracking with star ratings

- [x] **City hub screen** (`CityHubScreen`)
  - [x] Player info bar (level, EXP, gold, gems, stamina)
  - [x] Navigation grid: Campaign, Roster, Inventory, Formation, Shop, Gacha
  - [x] Central screen — all metagame screens navigate back to city

- [x] **Reward processing** (`RewardProcessor`)
  - [x] Post-battle rewards (gold, EXP, item drops with chance)
  - [x] Rewards displayed on battle result overlay
  - [x] Stage clear tracking and star recording

- [x] **Unit collection / roster** (`RosterManager`, `RosterScreen`)
  - [x] Unit roster with scrollable card list and detail panel
  - [x] Unit shard collection (gacha duplicates → shards)
  - [x] Star-level upgrade: spend shards to promote (1★ → 5★) with skill unlock
  - [x] Per-star stat scaling via `StarLevelConfig` multipliers
  - [x] Unit level system (gain EXP from battles or consumables, +2% stats/level)
  - [x] Unit detail view (icon, stats, star display, star-up button, shard progress, EXP, equipment with enhancement level)

- [x] **Equipment system** (`EquipmentManager`, `EquipSelectPopup`)
  - [x] Equipment slots per unit (Weapon, Armor, Accessory)
  - [x] Equip / unequip via modal popup (Sedulous.GUI `Popup` class)
  - [x] Equipment enhancement (spend gold + Enhancement Stones, +10% per level, max +10)
  - [x] Equipment stat bonuses applied to effective stats
  - [x] Equipment rarity tiers (shown in roster detail view)

- [x] **Inventory / bag system** (`InventoryManager`, `InventoryScreen`)
  - [x] Item storage with stack counts
  - [x] Item usage (consumables: EXP potions, stamina refills, gold chests)
  - [x] Item acquisition (battle rewards, shop, mail)
  - [x] Item sell for gold
  - [x] Grid layout with icons, selected item detail panel

- [x] **Gacha / card draw system** (`GachaManager`, `GachaScreen`)
  - [x] Single draw (300 gems) and multi-draw 10x (2700 gems)
  - [x] Rarity probability tables (3% Legendary, 12% Epic, 35% Rare, 50% Common)
  - [x] Pity system (guaranteed Legendary at 90 pulls)
  - [x] Duplicate handling (existing unit → shards)
  - [x] Result display with rarity borders, "NEW!" or shard count
  - [x] Draw animation (sequential card reveal with skip button)

- [x] **Shop system** (`ShopManager`, `ShopScreen`)
  - [x] Item listings with costs, Buy buttons, currency display
  - [x] Buy items with gold or gems
  - [x] Purchase limits with sold-out dimming and daily refresh reset
  - [x] Shop refresh timer (24h cycle, displayed in top bar)
  - [x] Featured/promoted items (gold highlight, sorted to top with FEATURED header)

- [x] **Formation management** (`FormationManager`, `FormationScreen`)
  - [x] Save multiple formation presets (max 4 via `MAX_FORMATION_PRESETS`)
  - [x] Assign units to hex grid positions (2x4 deployment zone via `BattleConstants.DEPLOY_COLUMNS/DEPLOY_ROWS`)
  - [x] Formation slot limit scales with hero level (3→8 over levels 1→10)
  - [x] Preset tabs with create/switch, unit count display
  - [x] Formation preset selection during deployment (in progress)
  - [x] Save deployment as formation preset

---

## Phase 7: Campaign & PvE Content

The PvE content pipeline and campaign structure.

### Checklist

- [x] **Campaign map screen**
  - [x] Chapter/world selection (3 chapters: The Verdant March, The Dark Frontier, The Burning Wastes)
  - [x] Stage nodes with linear unlock progression (15 stages, 5 per chapter)
  - [x] Stage difficulty and star rating display (filled/empty stars)
  - [x] Locked/unlocked state based on progression (grayed out with LOCKED label)
  - [x] Stage info popup (enemies, rewards, stamina cost, recommended power, first-clear bonus)
  - [x] Chapter boss stages (stages 5, 10, 15 — orange highlight, [BOSS] tag, extra rewards)

- [x] **Stage system**
  - [x] Load stage config (enemy formation, battle map, rewards)
  - [x] Pre-battle screen with enemy preview
  - [x] Battle execution
  - [x] Post-battle reward distribution (gold, EXP, gems, items with drop chance)
  - [x] Star rating calculation (3-star system)
  - [x] First-clear bonus rewards (bonus gold + gems on first clear, tracked via star history)
  - [x] Stage sweep (auto-complete 3-starred stages for rewards, spends stamina)

- [x] **Special PvE modes**
  - [x] **Tower/Dungeon** — sequential floors with increasing difficulty, no healing between floors, rewards per floor
  - [x] **Daily challenges** — rotating class/damage-type/race-restricted battles (12 templates, 3 per day, daily reset, deployment filtering)
  - [x] **Boss rush** — single powerful boss with special mechanics
  - [x] **Crusade/Gauntlet** — fight waves with persistent HP across battles, attrition-based unit pool (20 max), enemy HP persists on defeat

- [x] **Difficulty & scaling**
  - [x] Enemy stat scaling per chapter/stage (15 stages with difficulty 1-20, recommended power 100-2800)
  - [x] Recommended power level per stage (displayed in campaign screen and info popup)
  - [x] Hard mode unlock after clearing normal (1.5x enemy stats, Hard AI, 1.5x rewards, sequential unlock)

---

## Phase 8: Server Foundation & Auth

Standalone game server with HTTP-based auth, session management, and player data sync. Client connects to server for login/register and save data persistence.

### Checklist

- [x] **Server project setup**
  - [x] `StormTactics.Server` (BeefLib) — server logic
  - [x] `StormTactics.ServerApp` (ConsoleApp) — server executable
  - [x] Registered in `BeefSpace.toml`

- [x] **Auth system**
  - [x] `PasswordHasher` — SHA1 salt+hash, verify
  - [x] `AccountData` — username, passwordHash, salt, playerId (ISerializable)
  - [x] `AuthManager` — register/login, accounts.xml persistence
  - [x] `Session` / `SessionManager` — in-memory Bearer token sessions with expiry

- [x] **Player data persistence**
  - [x] `PlayerDataStore` — per-player XML file I/O at `server_data/players/{id}.xml`
  - [x] Serialize/deserialize `PlayerSaveData` to/from XML for HTTP transport
  - [x] New player creation with starter data (same as local `SaveManager`)

- [x] **REST API routes**
  - [x] `POST /api/auth/register` — create account + initial player data
  - [x] `POST /api/auth/login` — authenticate, return session token
  - [x] `GET /api/player/data` — return player data as XML (Bearer auth)
  - [x] `POST /api/player/save` — persist player data from XML body (Bearer auth)
  - [x] `JsonHelper` — minimal flat JSON builder/parser for auth responses

- [x] **Server executable**
  - [x] `GameServer` — wraps HttpServer, owns all components, registers routes
  - [x] `ServerConfig` — port, data dir, session timeout
  - [x] `Program.bf` — CLI with `--port` and `--data-dir` args, main update loop

- [x] **Client integration**
  - [x] `ServerSaveManager` — HTTP client for auth + player data sync
  - [x] `LoginScreen` — username/password UI with login/register buttons
  - [x] Server mode default (use `--local` for local saves)
  - [x] `DoSave()` abstraction replacing all direct save calls
  - [x] `GetSaveData()` helper for transparent server/local data access

---

## Phase 9: PvP Arena

Player-versus-player competitive mode.

### Checklist

- [ ] **Arena system**
  - [ ] Arena ranking/ladder (ELO or tier-based)
  - [ ] Matchmaking (match against similar-rank players)
  - [ ] Asynchronous PvP: fight AI-controlled versions of other players' teams
  - [ ] Defense formation (separate from attack formation)
  - [ ] Arena tickets / entry limits per day
  - [ ] Season resets with rewards based on final rank
  - [ ] Arena shop (buy items with arena currency)

- [ ] **Battle log**
  - [ ] Record of recent arena fights (attacks and defenses)
  - [ ] Replay viewing
  - [ ] Revenge option (attack someone who attacked you)

- [ ] **Leaderboard**
  - [ ] Top players list with rank, name, power level, formation preview
  - [ ] Player search

---

## Phase 10: Social & Guild Systems

Community and social features.

### Checklist

- [ ] **Friends system**
  - [ ] Add/remove friends
  - [ ] Friend list with online status
  - [ ] Visit friend's profile (view their team)
  - [ ] Send/receive daily gifts

- [ ] **Guild system**
  - [ ] Create / join / leave guild
  - [ ] Guild roster with roles (leader, officer, member)
  - [ ] Guild level and EXP (from member contributions)
  - [ ] Guild chat channel
  - [ ] Guild daily sign-in (rewards)
  - [ ] Guild shop (spend guild currency)

- [ ] **Guild wars** (future PvP expansion)
  - [ ] Guild vs guild scheduled battles
  - [ ] Territory control
  - [ ] Participation rewards

- [ ] **Mail system**
  - [ ] System mail (rewards, announcements)
  - [ ] Player-to-player mail
  - [ ] Attachment collection (claim items from mail)
  - [ ] Auto-expire old mail

- [ ] **Chat system**
  - [ ] Global chat channel
  - [ ] Guild chat channel
  - [ ] Private messages
  - [ ] Chat moderation (profanity filter, mute)

---

## Phase 11: City/Base Hub

The main non-combat screen where players manage everything.

### Checklist

- [ ] **City screen**
  - [ ] Visual hub with interactive building icons
  - [ ] Quick access to: Battle, Arena, Shop, Inventory, Units, Guild, Mail, Settings
  - [ ] Player info bar (level, stamina, gold, gems)
  - [ ] Notification badges on buildings with actionable content
  - [ ] Daily task / quest tracker widget

- [ ] **Buildings** (if building management is desired)
  - [ ] Gold mine — passive gold generation, upgradeable
  - [ ] Training ground — passive unit EXP gain
  - [ ] Workshop — equipment crafting/enhancement
  - [ ] Summoning portal — gacha draws
  - [ ] Arena gate — PvP access
  - [ ] Guild hall — guild features

- [ ] **Daily / achievement system**
  - [ ] Daily tasks (complete N battles, draw a card, enhance equipment, etc.)
  - [ ] Daily task reward milestones
  - [ ] Lifetime achievements (collect N units, reach stage X, etc.)
  - [ ] Achievement reward claims

- [ ] **Settings** (basic settings screen implemented: `SettingsScreen`, `GameSettings`)
  - [x] Camera pan mode (normal/inverted)
  - [x] Auto-step enemy turns default (on/off)
  - [x] Default battle speed (1x/2x/4x)
  - [x] Settings persistence in save data
  - [ ] Audio volume (music, SFX)
  - [ ] Graphics quality
  - [ ] Notification preferences
  - [ ] Account linking
  - [ ] Language selection

---

## Phase 12: Tutorial & New Player Experience

Guided onboarding to teach game mechanics.

### Checklist

- [ ] **Tutorial sequence**
  - [ ] Forced first battle with guided steps (move here, attack this)
  - [ ] Explain turn order
  - [ ] Explain unit types and damage types
  - [ ] Explain skills
  - [ ] Guide through first gacha draw
  - [ ] Guide through unit upgrade
  - [ ] Guide through formation setup
  - [ ] Introduce campaign map
  - [ ] Introduce arena

- [ ] **Tutorial framework**
  - [ ] Step-based tutorial config (action required, UI highlight target, dialogue text)
  - [ ] Forced-action mode (block all UI except the tutorial target)
  - [ ] Skip tutorial option for returning players
  - [ ] Tutorial progress tracking (resume where left off)

---

## Phase 13: Audio

Sound design integration.

### Checklist

- [ ] **Music**
  - [ ] Main menu theme
  - [ ] City/hub theme
  - [ ] Battle music (at least 2-3 tracks for variety)
  - [ ] Boss battle theme
  - [ ] Victory fanfare
  - [ ] Defeat theme
  - [ ] Campaign map theme

- [ ] **Sound effects**
  - [ ] UI sounds (button click, tab switch, notification)
  - [ ] Battle SFX (sword slash, arrow fire, spell cast, impact, block)
  - [ ] Unit voice lines (deploy, attack, skill use, death) — optional
  - [ ] Buff/debuff application sound
  - [ ] Damage number pop sound
  - [ ] Gacha draw sounds (anticipation, reveal, rare pull fanfare)
  - [ ] Level up / upgrade sounds
  - [ ] Currency gain/spend sound

---

## Phase 14: Save/Load & Persistence

Local persistence (pre-networking).

### Checklist

- [ ] **Save system**
  - [ ] Player profile (level, EXP, currencies)
  - [ ] Unit roster (all owned units with levels, stars, equipment)
  - [ ] Inventory contents
  - [ ] Formation presets
  - [ ] Campaign progress (cleared stages, star ratings)
  - [ ] Arena rank and history
  - [ ] Settings preferences
  - [ ] Tutorial progress
  - [ ] Achievement progress
  - [ ] Daily task state and reset timer

- [ ] **Serialization format** (using `Sedulous.Serialization` + XML)
  - [ ] Save data structs implement `ISerializable`
  - [ ] Use `XmlSerializer` for save files (same pattern as resource files: version header + serialized data)
  - [ ] Save file versioning (for future migrations)
  - [ ] Integrity checks (detect corruption)

- [ ] **Auto-save**
  - [ ] Save after every significant action (battle completion, purchase, upgrade)
  - [ ] Save on application exit
  - [ ] Load on application start

---

## Phase 15: Polish & Juice

Visual and feel improvements.

### Checklist

- [ ] **UI polish**
  - [ ] Screen transitions (fade, slide)
  - [ ] Button press animations
  - [ ] Panel open/close animations
  - [ ] Tooltip system (hover for details)
  - [ ] Confirmation dialogs for important actions (spend premium currency, sell items)
  - [ ] Loading screen with tips

- [ ] **Battle polish**
  - [ ] Screen shake on big hits
  - [ ] Slow-motion on killing blow
  - [ ] Unit portrait flash when taking damage
  - [ ] Critical hit visual emphasis (larger damage number, flash)
  - [ ] Battle start cinematic (camera sweep, team face-off)
  - [ ] Victory pose animations

- [ ] **Feedback systems**
  - [ ] Damage type color coding (physical=white, piercing=yellow, magic=purple)
  - [ ] Buff/debuff visual clarity (green borders=positive, red borders=negative)
  - [ ] Unit power level indicator (easy/matched/hard color coding in pre-battle)
  - [ ] Clear insufficient-resource messaging

---

## Networking

Networking requirements and available engine libraries for the `StormTactics.Server` project.

### Available Libraries

- **`Sedulous.Net`** — Low-level networking: `TcpClient`/`TcpListener` (non-blocking), `UdpSocket`, `NetBuffer` (big-endian binary serialization), `DnsResolver`, `Base64`, `SHA1`.
- **`Sedulous.Net.HTTP`** — HTTP/1.1 server with game-loop-friendly `Update()`, route registration (`Get`/`Post`), WebSocket upgrade via `OnWebSocketUpgrade` delegate. Also: `HttpClient` (blocking), `WebSocketClient` and `WebSocketConnection` (both non-blocking with `Receive()`).

### Planned Architecture

- **HTTP endpoints** for request/response operations: auth, player data, shop, gacha, inventory, formations.
- **WebSocket** for persistent real-time connections: battle sync, arena matchmaking, chat, presence.
- **`HttpServer.Update()`** called each frame in server game loop — no separate thread needed for HTTP/WebSocket handling.
- **`NetBuffer`** for binary packet serialization over WebSocket (efficient, big-endian).

### Server-Authoritative Systems
- **Battle simulation:** Server must re-simulate or validate battles to prevent cheating. The deterministic `BattleSimulation` class enables this.
- **Player data:** All player state (units, inventory, currencies, progression) must be server-authoritative. Local save is a cache.
- **Economy:** All currency transactions (purchases, rewards, gacha) validated server-side.
- **Gacha RNG:** Server-side random number generation for draws.

### Real-Time Communication
- **PvP matchmaking:** Find opponents, start battles.
- **Chat:** Global, guild, and private messaging in real-time.
- **Friend status:** Online/offline presence.
- **Guild activities:** Sign-in, donations, war coordination.
- **Push notifications:** Mail, arena attacks, guild events.

### Asynchronous Communication
- **Arena defense:** Upload defense formation; opponents fight AI-controlled version.
- **Mail system:** Send/receive messages and attachments.
- **Leaderboards:** Periodic rank updates.
- **Guild war results:** Batched results from guild battles.
- **Daily reset sync:** Server-controlled daily/weekly reset timers.

### Data Sync
- **Login/auth:** Account creation, login, session management.
- **Full state sync on login:** Download all player data on connect.
- **Delta updates:** Push incremental changes (inventory update, EXP gain, etc.) rather than full state.
- **Conflict resolution:** Server wins on any discrepancy.
- **Reconnection:** Resume session after network drop.

### Anti-Cheat
- **Server-side battle validation:** Replay client-submitted battles on server.
- **Rate limiting:** Prevent impossible action frequencies.
- **Receipt validation:** Verify in-app purchase receipts.
- **Anomaly detection:** Flag accounts with impossible stats/progression.

### Protocol Requirements
- **Packet system:** Define structured packets for each client↔server interaction (~50-100 packet types).
- **Binary or compact format:** Minimize bandwidth for mobile.
- **Encryption:** Encrypt sensitive data in transit.
- **Versioning:** Protocol version negotiation for client/server compat.

### Estimated Packet Types
| Category | Examples | Count |
|----------|----------|-------|
| Auth | Login, Logout, Register, SessionResume | ~5 |
| Player | GetProfile, UpdateProfile, LevelUp | ~5 |
| Battle | StartBattle, BattleAction, BattleResult, Replay | ~8 |
| Units | GetRoster, UpgradeUnit, EquipItem, SetFormation | ~10 |
| Inventory | GetBag, UseItem, SellItem | ~5 |
| Shop | GetShop, BuyItem, RefreshShop | ~5 |
| Gacha | DrawCard, GetDrawHistory | ~3 |
| Arena | GetRank, FindOpponent, SubmitResult, GetLog | ~8 |
| Social | AddFriend, RemoveFriend, SendGift, GetFriendList | ~8 |
| Guild | Create, Join, Leave, Donate, GetInfo, Chat | ~12 |
| Mail | GetMail, SendMail, ClaimAttachment, DeleteMail | ~5 |
| Chat | SendMessage, GetHistory | ~4 |
| System | Heartbeat, Error, Announcement, DailyReset | ~5 |
| **Total** | | **~80** |

---

## Required Assets List

All assets will be sourced externally. This is the complete list of what's needed.

### UI Art

| Asset | Description | Format | Quantity |
|-------|-------------|--------|----------|
| Unit portraits | Head/bust art for each unit, used in roster and battle UI | PNG, ~256x256 | 1 per unit type |
| Unit card art | Full illustration for collection screen | PNG, ~512x720 | 1 per unit type |
| Skill icons | Square icons for each skill | PNG, 64x64 or 128x128 | 1 per skill |
| Buff/debuff icons | Small square icons for status effects | PNG, 32x32 or 64x64 | 1 per buff type |
| Item icons | Icons for inventory items | PNG, 64x64 or 128x128 | 1 per item type |
| Equipment icons | Icons for equipment pieces | PNG, 64x64 or 128x128 | 1 per equipment type |
| Rarity frames/borders | Card borders for each rarity tier (common→legendary) | PNG | 5 |
| Class icons | Small icons for unit classes (infantry, cavalry, mage, etc.) | PNG, 32x32 | 1 per class |
| Damage type icons | Icons for physical / piercing / magic | PNG, 32x32 | 3 |
| Currency icons | Gold, gems, arena tokens, guild tokens, stamina | PNG, 48x48 | 5-8 |
| Star icons | Filled and empty stars for unit star level | PNG, 24x24 | 2 |
| Button art | Normal, hover, pressed states for primary/secondary/danger buttons | PNG / 9-slice | 3-5 sets |
| Panel backgrounds | Frames for info panels, popups, tooltips | PNG / 9-slice | 5-10 |
| Tab bar art | Active and inactive tab backgrounds | PNG | 2 per style |
| Progress bars | HP bar, EXP bar, stamina bar, loading bar | PNG | 4-6 |
| Header banners | Decorative headers for screens (Battle, Shop, Arena, etc.) | PNG | 8-12 |
| Background art | Full-screen backgrounds for menus, city, campaign map | PNG, 1920x1080 | 5-8 |
| Campaign map nodes | Stage node icons (cleared, available, locked, boss) | PNG | 4-5 |
| Campaign map paths | Connection lines/roads between nodes | PNG or tileable | 2-3 |
| Notification badge | Red circle with number overlay | PNG | 1 |
| Dialog/popup frame | Modal dialog background | PNG / 9-slice | 2-3 |
| Gacha draw effects | Pull animation frames or sprite sheets | PNG sequence | 1 set |
| Victory / Defeat banners | Large text banners for battle results | PNG | 2 |
| Star rating display | 1-star, 2-star, 3-star result graphics | PNG | 3 |
| Logo | Game logo/title art | PNG | 1 |
| App icon | Application icon | PNG, multiple sizes | 1 set |

### 3D Models (if using 3D battle view)

| Asset | Description | Format | Quantity |
|-------|-------------|--------|----------|
| Unit models | Rigged character models for each unit type | glTF/FBX | 1 per unit type |
| Unit animations | Idle, walk, attack, skill, hit, death per unit | glTF/FBX | 5-6 anims per unit |
| Hex tile model | Single hex tile mesh (flat) | glTF/FBX | 1 base + variants |
| Battle arena floor | Decorative base/floor for battle scene | glTF/FBX | 3-5 themes |
| Prop models | Decorative objects for battle arenas (rocks, crates, banners) | glTF/FBX | 10-20 |

### 2D Sprites (if using 2D/sprite battle view instead of 3D)

| Asset | Description | Format | Quantity |
|-------|-------------|--------|----------|
| Unit sprite sheets | Animated sprites: idle, walk, attack, skill, hit, death | PNG spritesheet | 1 per unit type |
| Hex tile sprites | Hex tile art (grass, stone, etc.) | PNG | 3-5 variants |
| Battle backgrounds | Parallax or static battle backgrounds | PNG, wide | 3-5 themes |

### VFX / Particles

| Asset | Description | Format | Quantity |
|-------|-------------|--------|----------|
| Slash effect | Melee attack hit | Sprite sheet / particle config | 2-3 variants |
| Arrow/projectile | Ranged attack projectile + hit | Sprite sheet / particle config | 2-3 variants |
| Magic cast | Spell casting effect at caster | Sprite sheet / particle config | 3-5 elements |
| Magic impact | Spell hit effect at target | Sprite sheet / particle config | 3-5 elements |
| Heal effect | Green/white healing glow | Sprite sheet / particle config | 1-2 |
| Buff applied | Positive status gain sparkle | Sprite sheet / particle config | 1 |
| Debuff applied | Negative status dark swirl | Sprite sheet / particle config | 1 |
| AOE indicator | Area highlight before AOE skill | Sprite sheet / shader | 1 |
| Critical hit | Extra flash/emphasis on crit | Sprite sheet / particle config | 1 |
| Death/despawn | Unit disappear effect | Sprite sheet / particle config | 1-2 |
| Level up | Level up celebration effect | Sprite sheet / particle config | 1 |
| Gacha reveal | Card reveal sparkle/glow per rarity | Sprite sheet / particle config | 5 |

### Audio

| Asset | Description | Format | Quantity |
|-------|-------------|--------|----------|
| Main menu music | Title/menu BGM loop | OGG/WAV | 1 |
| City/hub music | Peaceful hub BGM loop | OGG/WAV | 1 |
| Battle music | Combat BGM loops | OGG/WAV | 2-3 |
| Boss battle music | Intense boss fight BGM | OGG/WAV | 1 |
| Victory jingle | Short victory fanfare | OGG/WAV | 1 |
| Defeat jingle | Short defeat sting | OGG/WAV | 1 |
| Campaign map music | Overworld/map BGM | OGG/WAV | 1 |
| UI click | Button press sound | OGG/WAV | 1-2 |
| UI confirm | Confirm/purchase sound | OGG/WAV | 1 |
| UI cancel | Back/cancel sound | OGG/WAV | 1 |
| UI tab switch | Tab/page change sound | OGG/WAV | 1 |
| UI notification | Alert/badge pop | OGG/WAV | 1 |
| Sword slash | Melee attack SFX | OGG/WAV | 2-3 |
| Arrow fire | Ranged attack shoot SFX | OGG/WAV | 1-2 |
| Arrow hit | Ranged attack impact SFX | OGG/WAV | 1-2 |
| Spell cast | Magic casting SFX (per element) | OGG/WAV | 3-5 |
| Spell impact | Magic hit SFX (per element) | OGG/WAV | 3-5 |
| Shield block | Damage reduction / block SFX | OGG/WAV | 1 |
| Heal | Healing chime SFX | OGG/WAV | 1 |
| Buff gain | Positive status SFX | OGG/WAV | 1 |
| Debuff gain | Negative status SFX | OGG/WAV | 1 |
| Critical hit | Extra impact SFX for crits | OGG/WAV | 1 |
| Unit death | Death/collapse SFX | OGG/WAV | 1-2 |
| Damage number pop | Subtle pop for floating numbers | OGG/WAV | 1 |
| Gacha draw | Anticipation roll SFX | OGG/WAV | 1 |
| Gacha reveal (common) | Normal reveal | OGG/WAV | 1 |
| Gacha reveal (rare+) | Exciting reveal for rare pulls | OGG/WAV | 1 |
| Level up | Level up SFX | OGG/WAV | 1 |
| Star upgrade | Star promotion SFX | OGG/WAV | 1 |
| Coin / currency | Gold gain SFX | OGG/WAV | 1 |

### Fonts

| Asset | Description | Format | Quantity |
|-------|-------------|--------|----------|
| Primary UI font | Clean sans-serif for all UI text | TTF/OTF | 1 (with bold) |
| Damage number font | Stylized font for floating combat numbers | TTF/OTF or spritesheet | 1 |
| Title/header font | Decorative font for screen titles | TTF/OTF | 1 |

### Summary Counts (Estimated for MVP)

| Category | Estimated Count |
|----------|----------------|
| Unit types (MVP) | 15-20 |
| Skills | 30-40 |
| Buffs/debuffs | 15-20 |
| Items | 20-30 |
| Equipment pieces | 15-25 |
| Campaign stages | 30-50 |
| UI screens | 15-20 |
| Music tracks | 8-10 |
| Sound effects | 40-50 |
| VFX sets | 15-20 |
| Unique art assets (total) | ~200-300 |
