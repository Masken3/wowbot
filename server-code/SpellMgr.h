
enum ProcFlags
{
	PROC_FLAG_NONE                          = 0x00000000,

	PROC_FLAG_KILLED                        = 0x00000001,   ///< (From source) 00 Killed by aggressor
	PROC_FLAG_KILL                          = 0x00000002,   ///< (From source) 01 Kill target (in most cases need XP/Honor reward, see Unit::IsTriggeredAtSpellProcEvent for additinoal check)

	PROC_FLAG_SUCCESSFUL_MELEE_HIT          = 0x00000004,   ///< (From source) 02 Successful melee auto attack
	PROC_FLAG_TAKEN_MELEE_HIT               = 0x00000008,   ///< (From source) 03 Taken damage from melee auto attack hit

	PROC_FLAG_SUCCESSFUL_MELEE_SPELL_HIT    = 0x00000010,   ///< (From source) 04 Successful attack by Spell that use melee weapon
	PROC_FLAG_TAKEN_MELEE_SPELL_HIT         = 0x00000020,   ///< (From source) 05 Taken damage by Spell that use melee weapon

	PROC_FLAG_SUCCESSFUL_RANGED_HIT         = 0x00000040,   ///< (From source) 06 Successful Ranged auto attack
	PROC_FLAG_TAKEN_RANGED_HIT              = 0x00000080,   ///< (From source) 07 Taken damage from ranged auto attack

	PROC_FLAG_SUCCESSFUL_RANGED_SPELL_HIT   = 0x00000100,   ///< (From source) 08 Successful Ranged attack by Spell that use ranged weapon
	PROC_FLAG_TAKEN_RANGED_SPELL_HIT        = 0x00000200,   ///< (From source) 09 Taken damage by Spell that use ranged weapon

	PROC_FLAG_SUCCESSFUL_POSITIVE_AOE_HIT   = 0x00000400,   ///< (From source) 10 Successful AoE (not 100% shure unused)
	PROC_FLAG_TAKEN_POSITIVE_AOE            = 0x00000800,   ///< (From source) 11 Taken AoE      (not 100% shure unused)

	PROC_FLAG_SUCCESSFUL_AOE_SPELL_HIT      = 0x00001000,   ///< (From source) 12 Successful AoE damage spell hit (not 100% shure unused)
	PROC_FLAG_TAKEN_AOE_SPELL_HIT           = 0x00002000,   ///< (From source) 13 Taken AoE damage spell hit      (not 100% shure unused)

	PROC_FLAG_SUCCESSFUL_POSITIVE_SPELL     = 0x00004000,   ///< (From source) 14 Successful cast positive spell (by default only on healing)
	PROC_FLAG_TAKEN_POSITIVE_SPELL          = 0x00008000,   ///< (From source) 15 Taken positive spell hit (by default only on healing)

	PROC_FLAG_SUCCESSFUL_NEGATIVE_SPELL_HIT = 0x00010000,   ///< (From source) 16 Successful negative spell cast (by default only on damage)
	PROC_FLAG_TAKEN_NEGATIVE_SPELL_HIT      = 0x00020000,   ///< (From source) 17 Taken negative spell (by default only on damage)

	PROC_FLAG_ON_DO_PERIODIC                = 0x00040000,   ///< (From source) 18 Successful do periodic (damage / healing, determined by PROC_EX_PERIODIC_POSITIVE or negative if no procEx)
	PROC_FLAG_ON_TAKE_PERIODIC              = 0x00080000,   ///< (From source) 19 Taken spell periodic (damage / healing, determined by PROC_EX_PERIODIC_POSITIVE or negative if no procEx)

	PROC_FLAG_TAKEN_ANY_DAMAGE              = 0x00100000,   ///< (From source) 20 Taken any damage
	PROC_FLAG_ON_TRAP_ACTIVATION            = 0x00200000,   ///< (From source) 21 On trap activation

	PROC_FLAG_TAKEN_OFFHAND_HIT             = 0x00400000,   ///< (From source) 22 Taken off-hand melee attacks(not used)
	PROC_FLAG_SUCCESSFUL_OFFHAND_HIT        = 0x00800000    ///< (From source) 23 Successful off-hand melee attacks
};
