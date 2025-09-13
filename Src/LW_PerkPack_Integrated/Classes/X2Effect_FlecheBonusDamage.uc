//---------------------------------------------------------------------------------------
//  FILE:    X2Effect_FlecheBonusDamage.uc
//  AUTHOR:  Amineri / Pavonis Interactive
//  PURPOSE: Adds bonus damage when a particular ability is being used
//			  the amount of bonus depends on distance from starting point to target point
//---------------------------------------------------------------------------------------

class X2Effect_FlecheBonusDamage extends X2Effect_Persistent;

`include(LW_PerkPack_Integrated\LW_PerkPack.uci)

var float BonusDmgPerTile;
var int MaxBonusDamage;
var array<name> AbilityNames;

function int GetAttackingDamageModifier(XComGameState_Effect EffectState, XComGameState_Unit Attacker, Damageable TargetDamageable, XComGameState_Ability AbilityState, const out EffectAppliedData AppliedData, const int CurrentDamage, optional XComGameState NewGameState) 
{ 
	local XComWorldData WorldData;
	local XComGameState_Unit TargetUnit;
	local XComGameState_Destructible TargetObject;
	local X2Effect_ApplyWeaponDamage WeaponDamageEffect;
	local float BonusDmg;
	local float Dist;
	local vector StartLoc, TargetLoc;

	TargetUnit = XComGameState_Unit(TargetDamageable);
	if (TargetUnit != none)
	{
		`PPTRACE("Fleche: Target Unit=" $ TargetUnit.GetFullName());
	}
	TargetObject = XComGameState_Destructible(TargetDamageable);
	if (TargetObject != none)
	{
		`PPTRACE("Fleche: Targeting destructible object");
	}
	`PPTRACE("Fleche: Activated Ability Name=" @ AbilityState.GetMyTemplate().DataName);

	// Don't apply the bonus to extra damage that ignores the weapon's based damage,
	// for example the burn on Fusion Blades or the Shredder effect.
	WeaponDamageEffect = X2Effect_ApplyWeaponDamage(class'X2Effect'.static.GetX2Effect(AppliedData.EffectRef));
	if (WeaponDamageEffect != none && WeaponDamageEffect.bIgnoreBaseDamage)
	{
		return 0;
	}

	if (class'XComGameStateContext_Ability'.static.IsHitResultHit(AppliedData.AbilityResultContext.HitResult))
	{
		if ((TargetUnit != none || TargetObject != none) && AbilityNames.Find(AbilityState.GetMyTemplate().DataName) != -1)
		{
			WorldData = `XWORLD;
			StartLoc = WorldData.GetPositionFromTileCoordinates(Attacker.TurnStartLocation);
			if (TargetUnit != none)
			{
				TargetLoc = WorldData.GetPositionFromTileCoordinates(TargetUnit.TileLocation);
			}
			else if (TargetObject != none)
			{
				TargetLoc = WorldData.GetPositionFromTileCoordinates(TargetObject.TileLocation);
			}
			Dist = VSize(StartLoc - TargetLoc);
			`PPTRACE("Fleche: Start=" $ string(StartLoc) $ ", End=" $ string(TargetLoc) $ ", Dist=" $ string(Dist));
			BonusDmg = BonusDmgPerTile * VSize(StartLoc - TargetLoc)/ WorldData.WORLD_StepSize;
			`PPTRACE("Fleche: BonusDamage=" $ int(BonusDmg));
			`PPTRACE("Fleche: Output Damage should be:" @ string (CurrentDamage+int(BonusDmg)));
			BonusDmg = Min(BonusDmg, MaxBonusDamage);

			// Reduce bonus damage if the hit is a graze.
			if (AppliedData.AbilityResultContext.HitResult == eHit_Graze)
			{
				BonusDmg *= class'X2Effect_ApplyWeaponDamage'.default.GRAZE_DMG_MULT;
			}

			return int(BonusDmg);
		}
	}
	return 0; 
}
