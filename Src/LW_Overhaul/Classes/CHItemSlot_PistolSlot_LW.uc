//---------------------------------------------------------------------------------------
//  FILE:    CHItemSlot_PistolSlot_LW.uc
//  AUTHOR:  Peter Ledbrook
//  PURPOSE: Adds a pistol slot to most soldier classes. Mostly copied from
//           Veehementia's Dedicated Pistol Slot mod, with permission.
//---------------------------------------------------------------------------------------

class CHItemSlot_PistolSlot_LW extends CHItemSlotSet config(LW_Overhaul);

struct PistolSlotOverrideStruct
{
	var name ClassName;
	var name AllowedWeaponCat;
};

var config bool DISABLE_LW_PISTOL_SLOT;
var config array<name> EXCLUDE_FROM_PISTOL_SLOT_CLASSES;
var config array<name> PISTOL_SLOT_WEAPON_CATS;
var config array<PistolSlotOverrideStruct> PISTOL_CLASS_OVERRIDES;

var const array<name> DEFAULT_ALLOWED_WEAPON_CATS;

static function array<X2DataTemplate> CreateTemplates()
{
	local array<X2DataTemplate> Templates;

	if (!default.DISABLE_LW_PISTOL_SLOT)
	{
		`LWTrace("Configuring LWOTC pistol slot");
		Templates.AddItem(CreatePistolSlotTemplate());
	}

	return Templates;
}

static function X2DataTemplate CreatePistolSlotTemplate()
{
	local CHItemSlot Template;

	`CREATE_X2TEMPLATE(class'CHItemSlot', Template, 'PistolSlot');

	Template.InvSlot = eInvSlot_Pistol;
	Template.SlotCatMask = Template.SLOT_WEAPON | Template.SLOT_ITEM;
	// Unused for now
	Template.IsUserEquipSlot = true;
	// Uses unique rule
	Template.IsEquippedSlot = false;
	// Does not bypass unique rule
	Template.BypassesUniqueRule = false;
	Template.IsMultiItemSlot = false;
	Template.IsSmallSlot = false;
	Template.NeedsPresEquip = true;
	Template.ShowOnCinematicPawns = true;

	Template.CanAddItemToSlotFn = CanAddItemToPistolSlot;   // Overridden by CanAddItemToInventory_CH_Improved apparently
	Template.UnitHasSlotFn = HasPistolSlot;
	Template.GetPriorityFn = PistolGetPriority;
	Template.ShowItemInLockerListFn = ShowPistolItemInLockerList;
	Template.GetSlotUnequipBehaviorFn = PistolGetUnequipBehavior;
	Template.ValidateLoadoutFn = SlotValidateLoadout;

	return Template;
}

//Code borrowed from Iridar to remove items from slots.
static function SlotValidateLoadout(CHItemSlot Slot, XComGameState_Unit Unit, XComGameState_HeadquartersXCom XComHQ, XComGameState NewGameState)
{
	local XComGameState_Item	ItemState;
	local string				strDummy;
	local bool					HasSlot;
	local bool					bShouldUnequip;

	ItemState = Unit.GetItemInSlot(Slot.InvSlot, NewGameState);
	HasSlot = Slot.UnitHasSlot(Unit, strDummy, NewGameState);
	if (!HasSlot)
	{
		bShouldUnequip = true;
	}
	else if (ItemState != none)
	{
		if (!IsWeaponAllowedInPistolSlot(X2WeaponTemplate(ItemState.GetMyTemplate()), Unit))
		{
			bShouldUnequip = true;
		}
	}

	//	If there's an item equipped in the slot, but the unit is not supposed to have the slot, or the item is not supposed to be in the slot, then unequip it and put it into HQ Inventory.
	if (bShouldUnequip && ItemState != none)
	{
		ItemState = XComGameState_Item(NewGameState.ModifyStateObject(class'XComGameState_Item', ItemState.ObjectID));
		Unit = XComGameState_Unit(NewGameState.ModifyStateObject(class'XComGameState_Unit', Unit.ObjectID));
		if (Unit.RemoveItemFromInventory(ItemState, NewGameState))
		{
			XComHQ.PutItemInInventory(NewGameState, ItemState);
		}	
	}
}

static function bool CanAddItemToPistolSlot(
	CHItemSlot Slot,
	XComGameState_Unit UnitState,
	X2ItemTemplate Template,
	optional XComGameState CheckGameState,
	optional int Quantity = 1,
	optional XComGameState_Item ItemState)
{
	local X2WeaponTemplate WeaponTemplate;

	WeaponTemplate = X2WeaponTemplate(Template);
	if (WeaponTemplate != none && UnitState.GetItemInSlot(Slot.InvSlot, CheckGameState) == none)
	{
		return IsWeaponAllowedInPistolSlot(WeaponTemplate, UnitState);
	}
	return false;
}

static function bool HasPistolSlot(
	CHItemSlot Slot,
	XComGameState_Unit UnitState,
	out string LockedReason,
	optional XComGameState CheckGameState)
{
	return default.EXCLUDE_FROM_PISTOL_SLOT_CLASSES.Find(UnitState.GetSoldierClassTemplateName()) == INDEX_NONE;
}

static function int PistolGetPriority(CHItemSlot Slot, XComGameState_Unit UnitState, optional XComGameState CheckGameState)
{
	return 45; // Ammo Pocket is 110 
}

static function bool ShowPistolItemInLockerList(
	CHItemSlot Slot,
	XComGameState_Unit Unit,
	XComGameState_Item ItemState,
	X2ItemTemplate ItemTemplate,
	XComGameState CheckGameState)
{
	local X2WeaponTemplate WeaponTemplate;

	WeaponTemplate = X2WeaponTemplate(ItemTemplate);
	if (WeaponTemplate != none)
	{
		return IsWeaponAllowedInPistolSlot(WeaponTemplate, Unit);
	}
	return false;
}

static function ECHSlotUnequipBehavior PistolGetUnequipBehavior(
	CHItemSlot Slot,
	ECHSlotUnequipBehavior DefaultBehavior,
	XComGameState_Unit Unit,
	XComGameState_Item ItemState,
	optional XComGameState CheckGameState)
{
	return eCHSUB_AllowEmpty;
}

// Determines whether the given weapon type is allowed in the pistol slot
static function bool IsWeaponAllowedInPistolSlot(X2WeaponTemplate WeaponTemplate, optional XCOmGameState_Unit UnitState)
{
	local array<PistolSlotOverrideStruct> arrOverrides;
	local PistolSlotOverrideStruct Override;
	local name UnitClassName;

	// custom pistol slot class overrides array logic.
	if(UnitState != none)
	{
		UnitClassName = UnitState.GetSoldierClassTemplateName();

		foreach default.PISTOL_CLASS_OVERRIDES (Override)
		{
			if(Override.ClassName == UnitClassName)
			{
				arrOverrides.AddItem(Override);
			}
		}

		if(arrOverrides.length > 0)
		{
			foreach arrOverrides (Override)
			{
				if(WeaponTemplate.WeaponCat == Override.AllowedWeaponCat)
				{
					return true;
				}
			}
			return false;
		}

	}
	// Check the config var for allowed weapon categories, but if that's empty,
	// fall back to the default list.
	return default.PISTOL_SLOT_WEAPON_CATS.Length > 0 ?
		default.PISTOL_SLOT_WEAPON_CATS.Find(WeaponTemplate.WeaponCat) != INDEX_NONE :
		default.DEFAULT_ALLOWED_WEAPON_CATS.Find(WeaponTemplate.WeaponCat) != INDEX_NONE;
}

defaultproperties
{
	DEFAULT_ALLOWED_WEAPON_CATS[0] = "pistol";
	DEFAULT_ALLOWED_WEAPON_CATS[1] = "sidearm";
}
