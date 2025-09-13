//---------------------------------------------------------------------------------------
//  FILE:    UIScreenListener_LWOfficerPack
//  AUTHOR:  Amineri (Pavonis Interactive)
//  PURPOSE: Implements event listeners used to interface to other mods
//--------------------------------------------------------------------------------------- 

class UIScreenListener_LWOfficerPack extends UIScreenListener;

var localized string strCommandingOfficerTooltipTitle;
var localized string strCommandingOfficerTooltip;
var localized string strSubordinateOfficerTooltipTitle;
var localized string strSubordinateOfficerTooltip;

// Has this registered this game session ?
var bool bRegisteredForEvents; 
// Has this registered since a tactical/strategy switch ?
var bool bLastUpdateStrategy; 

var private string PathToArmoryMainMenu;
var private string PathToLeaderAbilityButton;

//var UIArmory_MainMenu ArmoryMainMenu;
//var UIListItemString LeaderAbilityButton;

var delegate<OnItemSelectedCallback> NextOnSelectionChanged;

delegate OnItemSelectedCallback(UIList _list, int itemIndex);

private function bool IsInStrategy()
{
	return ((`HQGAME  != none) && (`HQPC != None) && (`HQPRES != none));
}



event OnInit(UIScreen Screen)
{
	// Reset switch in tactical so we re-register back in strategy
	if (UITacticalHUD(Screen) == none)
	{
		RegisterForEvents();
		bRegisteredForEvents = false;
	}
	if (IsInStrategy() && !bRegisteredForEvents)
	{
		RegisterForEvents();
		bRegisteredForEvents = true;
	}
}

function RegisterForEvents()
{
	local Object ThisObj;
	local X2EventManager EventManager;
	
	ThisObj = self;

	EventManager = `XEVENTMGR;
	EventManager.UnRegisterFromAllEvents(ThisObj);

	EventManager.RegisterForEvent(ThisObj, 'OnUpdateSquadSelect_ListItem', AddOfficerIcon_SquadSelectListItem,,,,true); // hook to add officer icon to SquadSelect_ListItem

	EventManager.RegisterForEvent(ThisObj, 'OnSoldierListItemUpdateDisabled', SetDisabledOfficerListItems,,,,true);  // hook to disable selecting officers if officer already on mission
	EventManager.RegisterForEvent(ThisObj, 'OnSoldierListItemUpdate_End', AddOfficerIcon_PersonnelListItem,,,,true); // hook to add officer icon to soldier list items in UIPersonnel
	EventManager.RegisterForEvent(ThisObj, 'OverrideGetPersonnelStatusSeparate', CheckOfficerMissionStatus,,,,true); // hook to override status for officers warned from going on mission

	EventManager.RegisterForEvent(ThisObj, 'OnArmoryMainMenuUpdate', AddArmoryMainMenuItem,,,,true);

	EventManager.RegisterForEvent(ThisObj, 'OnDismissSoldier', CleanUpComponentStateOnDismiss,,,,true);

	EventManager.RegisterForEvent(ThisObj, 'SoldierRankName', OverrideOfficerRankName,,,,true);
	EventManager.RegisterForEvent(ThisObj, 'SoldierShortRankName', OverrideOfficerShortRankName,,,,true);
	EventManager.RegisterForEvent(ThisObj, 'SoldierRankIcon', OverrideOfficerRankIcon,,,,true);

	EventManager.RegisterForEvent(ThisObj, 'OnDistributeTacticalGameEndXP', UpdateOfficerLeadership, ELD_OnStateSubmitted,,,true); 
}

function EventListenerReturn UpdateOfficerLeadership(Object EventData, Object EventSource, XComGameState GameState, Name InEventID, Object CallbackData)
{
	local bool PlayerWonMission;
	local StateObjectReference UnitRef, CommandingRef;
	local X2MissionSourceTemplate MissionSource;
	local XComGameState NewGameState;
	local XComGameState_BattleData BattleState;
	local XComGameState_HeadquartersXCom XComHQ;
	local XComGameState_MissionSite MissionState;
	local XComGameState_Unit UnitState, CommandingUnit;
	local XComGameState_Unit_LWOfficer OfficerState;
	local XComGameState_XpManager XpManager;
	local XComGameStateHistory History;
	local XGBattle_SP Battle;

	XComHQ = XComGameState_HeadquartersXCom(EventData);
	if (XComHQ == none)
	{
		return ELR_NoInterrupt;
	}

	XpManager = XComGameState_XpManager(EventSource);
	if (XpManager == none)
	{
		`REDSCREEN("OnAddMissionEncountersToUnits event triggered with invalid event source.");
		return ELR_NoInterrupt;
	}

	History = `XCOMHISTORY;

	// Get commanding officer
	foreach XComHQ.Squad(UnitRef)
	{
		if (UnitRef.ObjectID == 0)
		{
			continue;
		}

		UnitState = XComGameState_Unit(History.GetGameStateForObjectID(UnitRef.ObjectID));
		if (UnitState == none)
		{
			continue;
		}

		if (class'LWOfficerUtilities'.static.IsHighestRankOfficerInSquad(UnitState, XComHQ))
		{
			OfficerState = class'LWOfficerUtilities'.static.GetOfficerComponent(UnitState);
			if (OfficerState != none)
			{
				CommandingUnit = UnitState;
				CommandingRef = UnitRef;
				break;
			}
		}
	}

	if (OfficerState == none)
	{
		return ELR_NoInterrupt; 
	}
	if (CommandingUnit.bCaptured) 
	{ 
		return ELR_NoInterrupt; 
	}
	if (CommandingUnit.IsDead())
	{
		return ELR_NoInterrupt;
	}

	// Determine if strategy objectives were met
	BattleState = XComGameState_BattleData(History.GetSingleGameStateObjectForClass(class'XComGameState_BattleData'));
	if ((BattleState != none) && (BattleState.m_iMissionID != XComHQ.MissionRef.ObjectID))
	{
		`REDSCREEN("LongWar: Mismatch in BattleState and XComHQ MissionRef when updating Officer Leadership Data");
		return ELR_NoInterrupt;
	}
	Battle = XGBattle_SP(`BATTLE);
	if (Battle == none)
	{
		return ELR_NoInterrupt;
	}

	MissionState = XComGameState_MissionSite(History.GetGameStateForObjectID(BattleState.m_iMissionID));
	if (MissionState == none)
	{
		return ELR_NoInterrupt;
	}

	PlayerWonMission = true;
	MissionSource = MissionState.GetMissionSource();
	if (MissionSource.WasMissionSuccessfulFn != none)
	{
		PlayerWonMission = MissionSource.WasMissionSuccessfulFn(BattleState);
	}

	if (!PlayerWonMission)
	{ 
		return ELR_NoInterrupt;
	}

	// Build NewGameState change container
	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("Update Officer Leadership Data post-mission");
	OfficerState = XComGameState_Unit_LWOfficer(NewGameState.CreateStateObject(class'XComGameState_Unit_LWOfficer', OfficerState.ObjectID));
	NewGameState.AddStateObject(OfficerState);

	foreach XComHQ.Squad(UnitRef)
	{
		if (UnitRef.ObjectID == 0)
		{
			continue;
		}
		// Don't count the unit itself
		if (UnitRef.ObjectID == CommandingRef.ObjectID)
		{
			continue;
		} 

		UnitState = XComGameState_Unit(History.GetGameStateForObjectID(UnitRef.ObjectID));
		
		if ((UnitState == none) || UnitState.IsDead() || UnitState.bCaptured)
		{
			continue;
		}
		// Exclude rebels from counting toward leadership bonuses -- ID 1582
		if (UnitState.GetSoldierClassTemplateName() == 'LWS_RebelSoldier')
		{
			continue;
		} 

		OfficerState.AddSuccessfulMissionToLeaderShip(UnitRef, NewGameState);
	}

	if (NewGameState.GetNumGameStateObjects() > 0)
	{
		`GAMERULES.SubmitGameState(NewGameState);
	}
	else
	{
		History.CleanupPendingGameState(NewGameState);
	}

	return ELR_NoInterrupt;
}

function EventListenerReturn OverrideOfficerRankName(Object EventData, Object EventSource, XComGameState NewGameState, Name InEventID, Object CallbackData)
{
	local XComGameState_Unit UnitState;
	local XComGameState_Unit_LWOfficer OfficerState;
	local XComLWTuple OverrideTuple;
	
	OverrideTuple = XComLWTuple(EventData);
	if (OverrideTuple == none)
	{
		`REDSCREEN("Override event triggered with invalid event data.");
		return ELR_NoInterrupt;
	}

	UnitState = XComGameState_Unit(EventSource);
	if (UnitState == none)
	{
		return ELR_NoInterrupt;
	}

	if (OverrideTuple.Id != 'SoldierRankName')
	{
		return ELR_NoInterrupt;
	}

	OfficerState = class'LWOfficerUtilities'.static.GetOfficerComponent(UnitState);
	if ((OfficerState != none) && (OfficerState.GetOfficerRank() > 0) && (OverrideTuple.Data[0].i == -1))
	{
		OverrideTuple.Data[1].s = class'LWOfficerUtilities'.static.GetLWOfficerRankName(OfficerState.GetOfficerRank());
	}

	return ELR_NoInterrupt;
}

function EventListenerReturn OverrideOfficerShortRankName(Object EventData, Object EventSource, XComGameState NewGameState, Name InEventID, Object CallbackData)
{
	local XComGameState_Unit UnitState;
	local XComGameState_Unit_LWOfficer OfficerState;
	local XComLWTuple OverrideTuple;
	
	OverrideTuple = XComLWTuple(EventData);
	if (OverrideTuple == none)
	{
		`REDSCREEN("Override event triggered with invalid event data.");
		return ELR_NoInterrupt;
	}

	UnitState = XComGameState_Unit(EventSource);
	if (UnitState == none)
	{
		return ELR_NoInterrupt;
	}

	if (OverrideTuple.Id != 'SoldierShortRankName')
	{
		return ELR_NoInterrupt;
	}

	OfficerState = class'LWOfficerUtilities'.static.GetOfficerComponent(UnitState);
	if ((OfficerState != none) && (OfficerState.GetOfficerRank() > 0) && (OverrideTuple.Data[0].i == -1))
	{
		OverrideTuple.Data[1].s = class'LWOfficerUtilities'.static.GetLWOfficerShortRankName(OfficerState.GetOfficerRank());
	}

	return ELR_NoInterrupt;
}

function EventListenerReturn OverrideOfficerRankIcon(Object EventData, Object EventSource, XComGameState NewGameState, Name InEventID, Object CallbackData)
{
	local XComGameState_Unit UnitState;
	local XComGameState_Unit_LWOfficer OfficerState;
	local XComLWTuple OverrideTuple;
	
	OverrideTuple = XComLWTuple(EventData);
	if (OverrideTuple == none)
	{
		`REDSCREEN("Override event triggered with invalid event data.");
		return ELR_NoInterrupt;
	}

	UnitState = XComGameState_Unit(EventSource);
	if (UnitState == none)
	{
		return ELR_NoInterrupt;
	}

	if (OverrideTuple.Id != 'SoldierRankIcon')
	{
		return ELR_NoInterrupt;
	}

	OfficerState = class'LWOfficerUtilities'.static.GetOfficerComponent(UnitState);
	if ((OfficerState != none) && (OfficerState.GetOfficerRank() > 0) && (OverrideTuple.Data[0].i == -1))
	{
		OverrideTuple.Data[1].s = class'LWOfficerUtilities'.static.GetRankIcon(OfficerState.GetOfficerRank());
	}

	return ELR_NoInterrupt;
}

function EventListenerReturn AddArmoryMainMenuItem(Object EventData, Object EventSource, XComGameState NewGameState, Name InEventID, Object CallbackData)
{
	local UIList List;
	local XComGameState_Unit Unit;
	local UIArmory_MainMenu ArmoryMainMenu;
	local UIListItemString LeaderAbilityButton;

	// `LOG("AddArmoryMainMenuItem: Starting.");

	List = UIList(EventData);
	if (List == none)
	{
		`REDSCREEN("Add Armory MainMenu event triggered with invalid event data.");
		return ELR_NoInterrupt;
	}
	ArmoryMainMenu = UIArmory_MainMenu(EventSource);
	if (ArmoryMainMenu == none)
	{
		`REDSCREEN("Add Armory MainMenu event triggered with invalid event source.");
		return ELR_NoInterrupt;
	}
	PathToArmoryMainMenu = PathName(ArmoryMainMenu);

	Unit = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(ArmoryMainMenu.UnitReference.ObjectID));

	// -------------------------------------------------------------------------------
	// Leader Abilities: 
	if (class'LWOfficerUtilities'.static.IsOfficer(Unit) || class'UIArmory_LWOfficerPromotion'.default.ALWAYSSHOW) 
	{
		LeaderAbilityButton = ArmoryMainMenu.Spawn(class'UIListItemString', List.ItemContainer).InitListItem(CAPS(class'UIScreenListener_Armory_MainMenu_LWOfficerPack'.default.strOfficerMenuOption));
		LeaderAbilityButton.ButtonBG.OnClickedDelegate = OnOfficerButtonCallback;

		PathToLeaderAbilityButton = PathName(LeaderAbilityButton);

		if (NextOnSelectionChanged == none)
		{
			NextOnSelectionChanged = List.OnSelectionChanged;
			List.OnSelectionChanged = OnSelectionChanged;
		}
		List.MoveItemToBottom(FindDismissListItem(List));
	}
	
	return ELR_NoInterrupt;
}

// Callback handler for list button -- invokes the LW officer ability UI
simulated function OnOfficerButtonCallback(UIButton kButton)
{
	local UIArmory_LWOfficerPromotion OfficerScreen;
	local XComHQPresentationLayer HQPres;
	local UIArmory_MainMenu ArmoryMainMenu;
	
	HQPres = `HQPRES;
	ArmoryMainMenu = UIArmory_MainMenu(FindObject(PathToArmoryMainMenu, class'UIArmory_MainMenu'));

	OfficerScreen = UIArmory_LWOfficerPromotion(HQPres.ScreenStack.Push(HQPres.Spawn(class'UIArmory_LWOfficerPromotion', HQPres), HQPres.Get3DMovie()));
	OfficerScreen.InitPromotion(ArmoryMainMenu.GetUnitRef(), false);
	// KDM : Previously, the officer pawn could be rotated when accessing the officer screen through the officer slot, but not when
	// accessing it through the 'Officer Abilities' menu button. Turns out it was missing a call to CreateSoldierPawn(); this has
	// been rectified below.
	OfficerScreen.CreateSoldierPawn();
}

// Callback handler for list button info at bottom of screen
simulated function OnSelectionChanged(UIList ContainerList, int ItemIndex)
{
	local UIArmory_MainMenu ArmoryMainMenu;
	local UIListItemString LeaderAbilityButton;

	LeaderAbilityButton = UIListItemString(FindObject(PathToLeaderAbilityButton, class'UIListItemString'));
	ArmoryMainMenu = UIArmory_MainMenu(FindObject(PathToArmoryMainMenu, class'UIArmory_MainMenu'));

	if (ContainerList.GetItem(ItemIndex) == LeaderAbilityButton) 
	{
		ArmoryMainMenu.MC.ChildSetString("descriptionText", "htmlText", class'UIUtilities_Text'.static.AddFontInfo(class'UIScreenListener_Armory_MainMenu_LWOfficerPack'.default.OfficerListItemDescription, true));
		return;
	}
	
	NextOnSelectionChanged(ContainerList, ItemIndex);
}

simulated function UIListItemString FindDismissListItem(UIList List)
{
	local int Idx;
	local UIListItemString Current;
	local UIArmory_MainMenu ArmoryMainMenu;

	ArmoryMainMenu = UIArmory_MainMenu(FindObject(PathToArmoryMainMenu, class'UIArmory_MainMenu'));

	for (Idx = 0; Idx < List.ItemCount ; Idx++)
	{
		Current = UIListItemString(List.GetItem(Idx));
		// `log("Dismiss Search: Text=" $ Current.Text $ ", DismissName=" $ ArmoryMainMenu.m_strDismiss);
		if (Current.Text == ArmoryMainMenu.m_strDismiss)
		{
			return Current;
		}
	}
	
	return none;
}

function EventListenerReturn AddOfficerIcon_SquadSelectListItem(Object EventData, Object EventSource, XComGameState NewGameState, Name InEventID, Object CallbackData)
{
	local UIIcon Icon;
	local UISquadSelect_ListItem ListItem;
	local XComGameState_Unit Unit;
	
	ListItem = UISquadSelect_ListItem(EventSource);
	if (ListItem == none)
	{
		`REDSCREEN("Add Officer Icon event triggered with invalid source.");
		return ELR_NoInterrupt;
	}

	Unit = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(ListItem.GetUnitRef().ObjectID));
	
	Icon = UIIcon(ListItem.GetChildByName('SquadSelect_OfficerIcon_LW', false));
	if (class'LWOfficerUtilities'.static.IsOfficer(Unit))
	{
		if (Icon == none)
		{
			Icon = ListItem.Spawn(class'UISquadSelect_OfficerIcon', ListItem.DynamicContainer).InitIcon('SquadSelect_OfficerIcon_LW', class'LWOfficerUtilities'.static.GetGenericIcon(), true, true, 18);
			Icon.Hide();
			Icon.OriginBottomRight();
			Icon.SetPosition(50.5, 265);
			Icon.DisableMouseAutomaticColor();
			Icon.bDisableSelectionBrackets = true;
		}
		Icon.Show();
		if (class'LWOfficerUtilities'.static.IsHighestRankOfficerInSquad(Unit))
		{
			Icon.SetBGColorState(eUIState_Warning);
			Icon.SetToolTipText(strCommandingOfficerTooltip, strCommandingOfficerTooltipTitle,,, true, class'UIUtilities'.const.ANCHOR_BOTTOM_LEFT, false, 0.5);
		}
		else
		{
			Icon.SetBGColorState(eUIState_Normal);
			Icon.SetToolTipText(strSubordinateOfficerTooltip, strSubordinateOfficerTooltipTitle,,, true, class'UIUtilities'.const.ANCHOR_BOTTOM_LEFT, false, 0.5);
		}
	} 
	else 
	{
		if (Icon != none)
		{
			Icon.Hide();
		}
	}

	return ELR_NoInterrupt;
}

function EventListenerReturn SetDisabledOfficerListItems(Object EventData, Object EventSource, XComGameState NewGameState, Name InEventID, Object CallbackData)
{
	local UIPersonnel_ListItem ListItem;
	
	// Only do this for squadselect
	if (!IsInSquadSelect())
	{
		return ELR_NoInterrupt;
	}

	ListItem = UIPersonnel_ListItem(EventData);
	if (ListItem == none)
	{
		`REDSCREEN("Set Disabled Officer List Items event triggered with invalid event data.");
		return ELR_NoInterrupt;
	}

	return ELR_NoInterrupt;
}

function bool IsInSquadSelect()
{
	local int Index;
	local UIScreenStack ScreenStack;

	ScreenStack = `SCREENSTACK;
	for (Index = 0; Index < ScreenStack.Screens.Length; ++Index)
	{
		if (ScreenStack.Screens[Index].IsA('UISquadSelect'))
		{
			return true;
		}
	}

	return false; 
}

function EventListenerReturn AddOfficerIcon_PersonnelListItem(Object EventData, Object EventSource, XComGameState NewGameState, Name InEventID, Object CallbackData)
{
	local UIIcon OfficerIcon;
	local UIPersonnel_SoldierListItem ListItem;
	local XComGameState_Unit Unit;
	
	ListItem = UIPersonnel_SoldierListItem(EventData);
	if (ListItem == none)
	{
		`REDSCREEN("AddOfficerIcon_PersonnelListItem event triggered with invalid event data.");
		return ELR_NoInterrupt;
	}

	Unit = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(ListItem.UnitRef.ObjectID));
	if (class'LWOfficerUtilities'.static.IsOfficer(Unit))
	{
		OfficerIcon = ListItem.Spawn(class'UIIcon', ListItem);
		OfficerIcon.bAnimateOnInit = false;
		// KDM : Remove the officer icon's selection brackets since they are unnecessary and look odd.
		OfficerIcon.bDisableSelectionBrackets = true;
		// KDM : Icons shouldn't be navigable, else they mess with controller navigation.
		OfficerIcon.bIsNavigable = false;
		OfficerIcon.InitIcon('abilityIcon1MC', class'LWOfficerUtilities'.static.GetGenericIcon(), false, true, 18);
		OfficerIcon.OriginTopLeft();
		OfficerIcon.SetPosition(101, 24);
	}

	return ELR_NoInterrupt;
}

function EventListenerReturn CheckOfficerMissionStatus(Object EventData, Object EventSource, XComGameState NewGameState, Name InEventID, Object CallbackData)
{
	local bool bUnitInSquad;
	local XComGameState_HeadquartersXCom HQState;
	local XComGameState_Unit Unit;
	local XComLWTuple PersonnelStrings;
	
	// Only do this for squadselect
	if ((!IsInSquadSelect()) && (GetScreenOrChild('UIPersonnel_SquadBarracks') == none))
	{
		return ELR_NoInterrupt;
	}

	PersonnelStrings = XComLWTuple(EventData);
	if (PersonnelStrings == none)
	{
		`REDSCREEN("Check Officer MissionStatus event triggered with invalid event data.");
		return ELR_NoInterrupt;
	}
	
	Unit = XComGameState_Unit(EventSource);
	if (Unit == none)
	{
		`REDSCREEN("OverrideGetPersonnelStatusSeparate event triggered with invalid source data.");
		return ELR_NoInterrupt;
	}

	HQState = `XCOMHQ;
	bUnitInSquad = HQState.IsUnitInSquad(Unit.GetReference());
	
	if ((GetScreenOrChild ('UISquadSelect') != none) && (GetScreenOrChild('UIPersonnel_SquadBarracks') == none))
	{
		if ((Unit != none) && (PersonnelStrings.Id == 'OverrideGetPersonnelStatusSeparate')) 
		{
			if ((PersonnelStrings.Data.Length == 0) || (PersonnelStrings.Data[0].b != true)) // Not already set by another method
			{
				if ((!bUnitInSquad) && class'LWOfficerUtilities'.static.IsOfficer(Unit) && class'LWOfficerUtilities'.static.HasOfficerInSquad())
				{
					PersonnelStrings.Data.Add(4-PersonnelStrings.Data.Length);
					PersonnelStrings.Data[0].kind = XComLWTVString;
					PersonnelStrings.Data[1].kind = XComLWTVString;
					PersonnelStrings.Data[2].kind = XComLWTVString;
					PersonnelStrings.Data[3].kind = XComLWTVInt;
					PersonnelStrings.Data[0].s = class'UIPersonnel_ListItem_SquadSelect_LWOfficerPack'.default.strOfficerAlreadySelectedStatus;
					PersonnelStrings.Data[1].s = "";
					PersonnelStrings.Data[2].s = "";
					PersonnelStrings.Data[3].i = eUIState_Warning;
				}
			}
		}
	}
	
	return ELR_NoInterrupt;
}

static function UIScreen GetScreenOrChild(name ScreenType)
{
	local int Index;
	local UIScreenStack ScreenStack;
	
	ScreenStack = `SCREENSTACK;
	for (Index = 0; Index < ScreenStack.Screens.Length; ++Index)
	{
		if (ScreenStack.Screens[Index].IsA(ScreenType))
		{
			return ScreenStack.Screens[Index];
		}
	}

	return none; 
}

function EventListenerReturn CleanUpComponentStateOnDismiss(Object EventData, Object EventSource, XComGameState GameState, Name EventID, Object CallbackData)
{
	local XComGameState NewGameState;
	local XComGameState_Unit UnitState, UpdatedUnit;
	local XComGameState_Unit_LWOfficer OfficerState, UpdatedOfficer;

	UnitState = XComGameState_Unit(EventData);
	if (UnitState == none)
	{
		return ELR_NoInterrupt;
	}

	OfficerState = class'LWOfficerUtilities'.static.GetOfficerComponent(UnitState);
	if (OfficerState != none)
	{
		// `LOG("LWOfficerPack: Found OfficerState, Unit=" $ UnitState.GetFullName() $ ", Removing Component.");
		NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("OfficerState cleanup");
		UpdatedUnit = XComGameState_Unit(NewGameState.CreateStateObject(class'XComGameState_Unit', UnitState.ObjectID));
		UpdatedOfficer = XComGameState_Unit_LWOfficer(NewGameState.CreateStateObject(class'XComGameState_Unit_LWOfficer', OfficerState.ObjectID));
		NewGameState.RemoveStateObject(UpdatedOfficer.ObjectID);
		UpdatedUnit.RemoveComponentObject(UpdatedOfficer);
		NewGameState.AddStateObject(UpdatedOfficer);
		NewGameState.AddStateObject(UpdatedUnit);
		if (NewGameState.GetNumGameStateObjects() > 0)
		{
			`GAMERULES.SubmitGameState(NewGameState);
		}
		else
		{
			`XCOMHISTORY.CleanupPendingGameState(NewGameState);
		}
	}

	return ELR_NoInterrupt;
}

event OnRemoved(UIScreen Screen)
{
	if (UIArmory_MainMenu(Screen) != none)
	{
		PathToArmoryMainMenu = "";
		NextOnSelectionChanged = none;
	}
}

defaultproperties
{
	ScreenClass = none;
}
