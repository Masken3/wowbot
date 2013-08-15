
# These flags denote the different kinds of movement you can do. You can have many at the
# same time as this is used as a bitmask.
# \todo [-ZERO] Need check and update used in most movement packets (send and received)
# \see MovementInfo
MovementFlags = {
	:MOVEFLAG_NONE               => 0x00000000,
	:MOVEFLAG_FORWARD            => 0x00000001,
	:MOVEFLAG_BACKWARD           => 0x00000002,
	:MOVEFLAG_STRAFE_LEFT        => 0x00000004,
	:MOVEFLAG_STRAFE_RIGHT       => 0x00000008,
	:MOVEFLAG_TURN_LEFT          => 0x00000010,
	:MOVEFLAG_TURN_RIGHT         => 0x00000020,
	:MOVEFLAG_PITCH_UP           => 0x00000040,
	:MOVEFLAG_PITCH_DOWN         => 0x00000080,
	:MOVEFLAG_WALK_MODE          => 0x00000100,               # Walking

	:MOVEFLAG_LEVITATING         => 0x00000400,
	:MOVEFLAG_ROOT               => 0x00000800,               # [-ZERO] is it really need and correct value
	:MOVEFLAG_FALLING            => 0x00002000,
	:MOVEFLAG_FALLINGFAR         => 0x00004000,
	:MOVEFLAG_SWIMMING           => 0x00200000,               # appears with fly flag also
	:MOVEFLAG_ASCENDING          => 0x00400000,               # [-ZERO] is it really need and correct value
	:MOVEFLAG_CAN_FLY            => 0x00800000,               # [-ZERO] is it really need and correct value
	:MOVEFLAG_FLYING             => 0x01000000,               # [-ZERO] is it really need and correct value

	:MOVEFLAG_ONTRANSPORT        => 0x02000000,               # Used for flying on some creatures
	:MOVEFLAG_SPLINE_ELEVATION   => 0x04000000,               # used for flight paths
	:MOVEFLAG_SPLINE_ENABLED     => 0x08000000,               # used for flight paths
	:MOVEFLAG_WATERWALKING       => 0x10000000,               # prevent unit from falling through water
	:MOVEFLAG_SAFE_FALL          => 0x20000000,               # active rogue safe fall spell (passive)
	:MOVEFLAG_HOVER              => 0x40000000,
}

open('build/movementFlags.h', 'w') do |file|
	file.puts '#ifndef MOVEMENTFLAGS_H'
	file.puts '#define MOVEMENTFLAGS_H'
	file.puts
	file.puts 'typedef struct lua_State lua_State;'
	file.puts
	file.puts 'enum MovementFlag {'
	MovementFlags.each do |k, v|
		file.puts "\t#{k} = #{v},"
	end
	file.puts '};'
	file.puts
	file.puts 'void movementFlagsLua(lua_State*);'
	file.puts
	file.puts '#endif	//MOVEMENTFLAGS_H'
end

open('build/movementFlags.c', 'w') do |file|
	file.puts '#include "movementFlags.h"'
	file.puts '#include <lua.h>'
	file.puts
	file.puts 'void movementFlagsLua(lua_State* L) {'
	MovementFlags.each do |k, v|
		file.puts "\tlua_pushnumber(L, #{k});"
		file.puts "\tlua_setglobal(L, \"#{k}\");"
	end
	file.puts '}'
end
