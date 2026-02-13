namespace StormTactics.Client;

using System;
using System.Collections;
using Sedulous.GUI;
using Sedulous.Mathematics;
using Sedulous.Drawing;
using Sedulous.Foundation.Core;
using StormTactics.Core;
using StormTactics.Game;
using StormTactics.Battle;

delegate void FormationBackDelegate();
delegate void FormationSaveDelegate();

/// Formation management screen: preset tabs, unit list, hex grid placement.
class FormationScreen
{
	private Grid mRoot ~ delete _;

	// Preset tabs
	private StackPanel mPresetTabPanel;
	private Button mNewPresetBtn ~ { mPresetTabPanel?.RemoveChild(_, false); delete _; };

	// Unit list (left)
	private StackPanel mUnitListPanel;
	private ScrollViewer mUnitListScroll;

	// Hex grid (center) — matches battle hex coordinate system
	// Owned by the UI tree (child of centerWrapper → mRoot), deleted when mRoot is deleted
	private HexGridControl mHexGrid;

	// Formation grid dimensions — derived from battle deployment zone constants
	private const int32 GRID_COLS = BattleConstants.DEPLOY_COLUMNS;
	private const int32 GRID_ROWS = BattleConstants.DEPLOY_ROWS;

	// Unit count display
	private TextBlock mUnitCountLabel;

	// State
	private int32 mActivePresetIndex;
	private int32 mSelectedUnitId = -1;
	private int32 mMaxFormationSlots = 8;
	private Dictionary<int32, OwnedImageData> mIconCache = new .() ~ { for (let v in _.Values) delete v; delete _; };

	// Events
	private EventAccessor<FormationBackDelegate> mOnBack = new .() ~ delete _;
	private EventAccessor<FormationSaveDelegate> mOnSave = new .() ~ delete _;

	public EventAccessor<FormationBackDelegate> OnBack => mOnBack;
	public EventAccessor<FormationSaveDelegate> OnSave => mOnSave;
	public UIElement RootElement => mRoot;

	// References kept for refresh
	private PlayerSaveData mSave;
	private ConfigDatabase mConfigs;
	private FormationManager mFormationMgr;

	public this()
	{
		BuildUI();
	}

	private void BuildUI()
	{
		mRoot = new Grid();
		mRoot.Background = Color(12, 14, 22, 255);
		mRoot.HorizontalAlignment = .Stretch;
		mRoot.VerticalAlignment = .Stretch;

		mRoot.RowDefinitions.Add(new .() { Height = .Pixels(48) });  // Top bar
		mRoot.RowDefinitions.Add(new .() { Height = .Pixels(36) });  // Preset tabs
		mRoot.RowDefinitions.Add(new .() { Height = .Star });        // Content

		mRoot.ColumnDefinitions.Add(new .() { Width = .Pixels(220) }); // Unit list
		mRoot.ColumnDefinitions.Add(new .() { Width = .Star });         // Grid area

		BuildTopBar();
		BuildPresetTabs();
		BuildUnitList();
		BuildGridArea();
	}

	private void BuildTopBar()
	{
		let topBar = new Border();
		topBar.Background = Color(18, 22, 32, 240);
		topBar.Padding = Thickness(12, 8, 12, 8);
		GridProperties.SetRow(topBar, 0);
		GridProperties.SetColumnSpan(topBar, 2);

		let content = new DockPanel();
		content.LastChildFill = false;
		content.VerticalAlignment = .Center;
		topBar.Child = content;

		let backBtn = new Button("Back");
		backBtn.Padding = Thickness(16, 4, 16, 4);
		backBtn.Click.Subscribe(new (btn) => { mOnBack.[Friend]Invoke(); });
		DockPanelProperties.SetDock(backBtn, .Left);
		content.AddChild(backBtn);

		let title = new TextBlock("FORMATION");
		title.Foreground = Color(255, 215, 80);
		title.FontSize = 20;
		title.Margin = Thickness(16, 0, 0, 0);
		title.VerticalAlignment = .Center;
		DockPanelProperties.SetDock(title, .Left);
		content.AddChild(title);

		// Save button (right)
		let saveBtn = new Button("Save");
		saveBtn.Padding = Thickness(16, 4, 16, 4);
		saveBtn.Click.Subscribe(new (btn) => { mOnSave.[Friend]Invoke(); });
		DockPanelProperties.SetDock(saveBtn, .Right);
		content.AddChild(saveBtn);

		mRoot.AddChild(topBar);
	}

	private void BuildPresetTabs()
	{
		let tabBar = new Border();
		tabBar.Background = Color(16, 18, 28, 255);
		tabBar.Padding = Thickness(8, 4, 8, 4);
		GridProperties.SetRow(tabBar, 1);
		GridProperties.SetColumnSpan(tabBar, 2);

		mPresetTabPanel = new StackPanel();
		mPresetTabPanel.Orientation = .Horizontal;
		mPresetTabPanel.Spacing = 6;
		mPresetTabPanel.VerticalAlignment = .Center;
		tabBar.Child = mPresetTabPanel;

		mNewPresetBtn = new Button("+");
		mNewPresetBtn.Padding = Thickness(10, 2, 10, 2);
		mNewPresetBtn.Click.Subscribe(new (btn) => {
			if (mFormationMgr != null && mFormationMgr.PresetCount < BattleConstants.MAX_FORMATION_PRESETS)
			{
				let name = scope String();
				name.AppendF("Preset {}", mFormationMgr.PresetCount + 1);
				if (mFormationMgr.CreatePreset(name))
				{
					mActivePresetIndex = mFormationMgr.PresetCount - 1;
					mFormationMgr.SetActivePreset(mActivePresetIndex);
					// Defer tree rebuild — this button is in the panel being cleared
					if (mRoot.Context != null)
						mRoot.Context.MutationQueue.QueueAction(new () => { RefreshAll(); });
					else
						RefreshAll();
				}
			}
		});

		mRoot.AddChild(tabBar);
	}

	private void BuildUnitList()
	{
		let listBorder = new Border();
		listBorder.Background = Color(16, 18, 28, 255);
		listBorder.Padding = Thickness(6, 6, 6, 6);
		GridProperties.SetRow(listBorder, 2);
		GridProperties.SetColumn(listBorder, 0);

		mUnitListScroll = new ScrollViewer();
		mUnitListScroll.VerticalScrollBarVisibility = .Auto;
		mUnitListScroll.HorizontalScrollBarVisibility = .Disabled;
		listBorder.Child = mUnitListScroll;

		mUnitListPanel = new StackPanel();
		mUnitListPanel.Orientation = .Vertical;
		mUnitListPanel.Spacing = 3;
		mUnitListScroll.Content = mUnitListPanel;

		mRoot.AddChild(listBorder);
	}

	private void BuildGridArea()
	{
		let gridBorder = new Border();
		gridBorder.Background = Color(20, 24, 36, 255);
		gridBorder.Padding = Thickness(16, 16, 16, 16);
		GridProperties.SetRow(gridBorder, 2);
		GridProperties.SetColumn(gridBorder, 1);

		let centerWrapper = new StackPanel();
		centerWrapper.Orientation = .Vertical;
		centerWrapper.HorizontalAlignment = .Center;
		centerWrapper.VerticalAlignment = .Center;
		centerWrapper.Spacing = 8;
		gridBorder.Child = centerWrapper;

		let gridLabel = new TextBlock("Click a cell to place the selected unit");
		gridLabel.Foreground = Color(120, 120, 140);
		gridLabel.FontSize = 13;
		gridLabel.TextAlignment = .Center;
		gridLabel.HorizontalAlignment = .Center;
		centerWrapper.AddChild(gridLabel);

		// Unit count
		mUnitCountLabel = new TextBlock("");
		mUnitCountLabel.Foreground = Color(150, 150, 170);
		mUnitCountLabel.FontSize = 13;
		mUnitCountLabel.TextAlignment = .Center;
		mUnitCountLabel.HorizontalAlignment = .Center;
		centerWrapper.AddChild(mUnitCountLabel);

		// Hex grid matching the battle deployment zone layout
		mHexGrid = new HexGridControl(GRID_COLS, GRID_ROWS, 34);
		mHexGrid.HorizontalAlignment = .Center;
		mHexGrid.OnCellClicked.Subscribe(new (col, row) => {
			OnGridCellClicked(col, row);
		});
		centerWrapper.AddChild(mHexGrid);

		mRoot.AddChild(gridBorder);
	}

	private void OnGridCellClicked(int32 gridX, int32 gridY)
	{
		if (mFormationMgr == null || mSave == null || mConfigs == null) return;

		let preset = mFormationMgr.GetPreset(mActivePresetIndex);
		if (preset == null) return;

		// Check if there's already a unit at this position
		FormationUnitSlot existingSlot = null;
		for (let slot in preset.mSlots)
		{
			if (slot.mGridX == gridX && slot.mGridY == gridY)
			{
				existingSlot = slot;
				break;
			}
		}

		if (existingSlot != null)
		{
			// Click on occupied cell: remove unit from formation
			mFormationMgr.RemoveUnitFromPreset(mActivePresetIndex, existingSlot.mUnitId);
			RefreshAll();
			return;
		}

		// Place selected unit
		if (mSelectedUnitId >= 0)
		{
			bool alreadyInFormation = mFormationMgr.IsUnitInPreset(mActivePresetIndex, mSelectedUnitId);

			// If adding a new unit, check the slot limit
			if (!alreadyInFormation && preset.mSlots.Count >= mMaxFormationSlots)
				return;

			if (alreadyInFormation)
				mFormationMgr.MoveUnitInPreset(mActivePresetIndex, mSelectedUnitId, gridX, gridY);
			else
				mFormationMgr.AddUnitToPreset(mActivePresetIndex, mSelectedUnitId, gridX, gridY);

			mSelectedUnitId = -1;
			RefreshAll();
		}
	}

	/// Initialize references and refresh.
	public void Show(PlayerSaveData save, ConfigDatabase configs, FormationManager formationMgr, int32 maxSlots)
	{
		mSave = save;
		mConfigs = configs;
		mFormationMgr = formationMgr;
		mMaxFormationSlots = maxSlots;
		mActivePresetIndex = save.mActiveFormationIndex;
		mSelectedUnitId = -1;
		RefreshAll();
	}

	private void RefreshAll()
	{
		RefreshPresetTabs();
		RefreshUnitList();
		RefreshGrid();
	}

	private void RefreshPresetTabs()
	{
		// Detach persistent button before clearing to prevent it from being queued for deletion
		mPresetTabPanel.RemoveChild(mNewPresetBtn, false);
		mPresetTabPanel.ClearChildren();

		for (int32 i = 0; i < mFormationMgr.PresetCount; i++)
		{
			let preset = mFormationMgr.GetPreset(i);
			let tabIdx = i;

			let tab = new Button(preset.mName);
			tab.Padding = Thickness(12, 2, 12, 2);
			if (i == mActivePresetIndex)
				tab.[Friend]mBackground = Color(60, 70, 100, 255);
			tab.Click.Subscribe(new (btn) => {
				mActivePresetIndex = tabIdx;
				mFormationMgr.SetActivePreset(tabIdx);
				mSelectedUnitId = -1;
				// Defer tree rebuild to avoid modifying tree during event processing
				if (mRoot.Context != null)
					mRoot.Context.MutationQueue.QueueAction(new () => { RefreshAll(); });
				else
					RefreshAll();
			});
			mPresetTabPanel.AddChild(tab);
		}

		// Only show "+" button if under the preset limit
		if (mFormationMgr.PresetCount < BattleConstants.MAX_FORMATION_PRESETS)
			mPresetTabPanel.AddChild(mNewPresetBtn);
	}

	private void RefreshUnitList()
	{
		mUnitListPanel.ClearChildren();

		let preset = mFormationMgr.GetPreset(mActivePresetIndex);

		for (let owned in mSave.mOwnedUnits)
		{
			let config = mConfigs.GetUnit(owned.mUnitId);
			if (config == null) continue;

			let unitId = owned.mUnitId;
			bool inFormation = preset != null && mFormationMgr.IsUnitInPreset(mActivePresetIndex, unitId);

			let icon = GetOrCreateIcon(config);

			let card = new Border();
			if (unitId == mSelectedUnitId)
				card.Background = Color(50, 60, 80, 255);
			else if (inFormation)
				card.Background = Color(30, 45, 35, 255);
			else
				card.Background = Color(25, 30, 45, 255);
			card.Padding = Thickness(6, 4, 6, 4);
			card.HorizontalAlignment = .Stretch;

			let row = new StackPanel();
			row.Orientation = .Horizontal;
			row.Spacing = 8;
			row.VerticalAlignment = .Center;
			card.Child = row;

			let iconImg = new Image(icon);
			iconImg.Width = .Fixed(32);
			iconImg.Height = .Fixed(32);
			iconImg.Stretch = .UniformToFill;
			iconImg.IsHitTestVisible = false;
			row.AddChild(iconImg);

			let nameStr = scope String();
			nameStr.Set(config.mName);
			if (inFormation) nameStr.Append(" [F]");

			let nameLabel = new TextBlock(nameStr);
			nameLabel.Foreground = inFormation ? Color(150, 220, 150) : Color(200, 200, 210);
			nameLabel.FontSize = 13;
			nameLabel.IsHitTestVisible = false;
			row.AddChild(nameLabel);

			// Click overlay
			let clickBtn = new Button();
			clickBtn.Background = Color(0, 0, 0, 0);
			clickBtn.HorizontalAlignment = .Stretch;
			clickBtn.VerticalAlignment = .Stretch;
			clickBtn.Padding = Thickness(0);
			clickBtn.Click.Subscribe(new (b) => {
				mSelectedUnitId = unitId;
				// Defer rebuild — this button is in the panel being cleared
				if (mRoot.Context != null)
					mRoot.Context.MutationQueue.QueueAction(new () => { RefreshUnitList(); });
				else
					RefreshUnitList();
			});

			let wrapper = new Grid();
			wrapper.HorizontalAlignment = .Stretch;
			wrapper.RowDefinitions.Add(new .() { Height = .Auto });
			wrapper.ColumnDefinitions.Add(new .() { Width = .Star });
			wrapper.AddChild(card);
			wrapper.AddChild(clickBtn);

			mUnitListPanel.AddChild(wrapper);
		}
	}

	private void RefreshGrid()
	{
		let preset = mFormationMgr.GetPreset(mActivePresetIndex);
		mHexGrid.ClearCells();

		int32 unitCount = 0;

		if (preset != null)
		{
			for (let slot in preset.mSlots)
			{
				if (slot.mGridX < 0 || slot.mGridX >= GRID_COLS) continue;
				if (slot.mGridY < 0 || slot.mGridY >= GRID_ROWS) continue;

				let config = mConfigs.GetUnit(slot.mUnitId);
				if (config != null)
					mHexGrid.SetCell(slot.mGridX, slot.mGridY, Color(40, 65, 80, 255), config.mName);
				else
					mHexGrid.SetCell(slot.mGridX, slot.mGridY, Color(50, 40, 40, 255), "???");
				unitCount++;
			}
		}

		let countStr = scope String();
		countStr.AppendF("Units: {}/{}", unitCount, mMaxFormationSlots);
		mUnitCountLabel.Text = countStr;
		mUnitCountLabel.Foreground = (unitCount >= mMaxFormationSlots) ? Color(200, 180, 80) : Color(150, 150, 170);
	}

	private OwnedImageData GetOrCreateIcon(UnitConfig config)
	{
		if (mIconCache.TryGetValue(config.mId, let existing))
			return existing;

		let icon = IconGenerator.GenerateUnitIcon(config.mUnitClass, config.mRarity);
		mIconCache[config.mId] = icon;
		return icon;
	}
}
