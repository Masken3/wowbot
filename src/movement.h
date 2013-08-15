#ifndef MOVEMENT_H
#define MOVEMENT_H

#include "movementFlags.h"

enum eFlags
{
	None         = 0x00000000,
	Done         = 0x00000001,
	Falling      = 0x00000002,           // Affects elevation computation
	Unknown3     = 0x00000004,
	Unknown4     = 0x00000008,
	Unknown5     = 0x00000010,
	Unknown6     = 0x00000020,
	Unknown7     = 0x00000040,
	Unknown8     = 0x00000080,
	Runmode      = 0x00000100,
	Flying       = 0x00000200,           // Smooth movement(Catmullrom interpolation mode), flying animation
	No_Spline    = 0x00000400,
	Unknown12    = 0x00000800,
	Unknown13    = 0x00001000,
	Unknown14    = 0x00002000,
	Unknown15    = 0x00004000,
	Unknown16    = 0x00008000,
	Final_Point  = 0x00010000,
	Final_Target = 0x00020000,
	Final_Angle  = 0x00040000,
	Unknown19    = 0x00080000,           // exists, but unknown what it does
	Cyclic       = 0x00100000,           // Movement by cycled spline
	Enter_Cycle  = 0x00200000,           // Everytimes appears with cyclic flag in monster move packet, erases first spline vertex after first cycle done
	Frozen       = 0x00400000,           // Will never arrive
	Unknown23    = 0x00800000,
	Unknown24    = 0x01000000,
	Unknown25    = 0x02000000,          // exists, but unknown what it does
	Unknown26    = 0x04000000,
	Unknown27    = 0x08000000,
	Unknown28    = 0x10000000,
	Unknown29    = 0x20000000,
	Unknown30    = 0x40000000,
	Unknown31    = 0x80000000,

	// Masks
	Mask_Final_Facing = Final_Point | Final_Target | Final_Angle,
	// flags that shouldn't be appended into SMSG_MONSTER_MOVE\SMSG_MONSTER_MOVE_TRANSPORT packet, should be more probably
	Mask_No_Monster_Move = Mask_Final_Facing | Done,
	// CatmullRom interpolation mode used
	Mask_CatmullRom = Flying,
};

enum MonsterMoveType
{
	MonsterMoveNormal       = 0,
	MonsterMoveStop         = 1,
	MonsterMoveFacingSpot   = 2,
	MonsterMoveFacingTarget = 3,
	MonsterMoveFacingAngle  = 4,
};

#define MOVEMENT_OPCODES(m)\
	m(MSG_MOVE_START_FORWARD)\
	m(MSG_MOVE_START_BACKWARD)\
	m(MSG_MOVE_STOP)\
	m(MSG_MOVE_START_STRAFE_LEFT)\
	m(MSG_MOVE_START_STRAFE_RIGHT)\
	m(MSG_MOVE_STOP_STRAFE)\
	m(MSG_MOVE_JUMP)\
	m(MSG_MOVE_START_TURN_LEFT)\
	m(MSG_MOVE_START_TURN_RIGHT)\
	m(MSG_MOVE_STOP_TURN)\
	m(MSG_MOVE_START_PITCH_UP)\
	m(MSG_MOVE_START_PITCH_DOWN)\
	m(MSG_MOVE_STOP_PITCH)\
	m(MSG_MOVE_SET_RUN_MODE)\
	m(MSG_MOVE_SET_WALK_MODE)\
	m(MSG_MOVE_FALL_LAND)\
	m(MSG_MOVE_START_SWIM)\
	m(MSG_MOVE_STOP_SWIM)\
	m(MSG_MOVE_SET_FACING)\
	m(MSG_MOVE_SET_PITCH)\

#endif	//MOVEMENT_H
