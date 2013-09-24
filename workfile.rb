#!/usr/bin/ruby

CONFIG_CCOMPILE_DEFAULT = 'debug'

require './config.rb'
require File.expand_path "#{CONFIG_WOWFOOT_DIR}/rules/cExe.rb"
require './genLuaFromHeader.rb'
require './genDbc.rb'
require './libs.rb'

class GenTask < MultiFileTask
	def initialize(name)
		@src = "src/#{name}.rb"
		@prerequisites = [FileTask.new(@src)]
		super("build/#{name}.c", ["build/#{name}.h"])
	end
	def fileExecute
		sh "ruby #{@src}"
	end
end

work = ExeWork.new do
	@SOURCES = ['src', 'src/worldMsgHandlers', 'server-code/Auth']
	@SOURCE_FILES = [
		"#{CONFIG_WOWFOOT_DIR}/wowfoot-cpp/handlers/spell/spellStrings.cpp",
		"#{CONFIG_WOWFOOT_DIR}/wowfoot-cpp/handlers/dbcSkillLineAbility/SkillLineAbility.index.cpp",
	]
	@SOURCE_TASKS = @REQUIREMENTS = [
		GenTask.new('Opcodes'),
		GenTask.new('movementFlags'),
		GenLuaFromHeaderTask.new('UpdateFields', 'server-code/UpdateFields.h'),
		GenLuaFromHeaderTask.new('updateBlockFlags', 'src/updateBlockFlags.h'),
		GenLuaFromHeaderTask.new('SharedDefines', 'server-code/SharedDefines.h',
			{:includedEnums=>['SpellEffects', 'SpellRangeIndex', 'Powers',
				'SpellAttributes', 'SpellAttributesEx', 'SpellAttributesEx2',
				'SpellAttributesEx3', 'SpellAttributesEx4',
				'UnitDynFlags',
				'GameobjectTypes',
				'GameObjectFlags',
				'GameObjectDynamicLowFlags',
				'Targets',
				'LockKeyType', 'LockType',
				'ItemQualities',
				'Stats',
				'TradeStatus', 'Language', 'ChatMsg']}),
		GenLuaFromHeaderTask.new('Unit', 'server-code/Unit.h',
			{:includedEnums=>['UnitFlags', 'NPCFlags']}),
		GenLuaFromHeaderTask.new('ObjectGuid', 'server-code/ObjectGuid.h',
			{:includedEnums=>['TypeMask']}),
		GenLuaFromHeaderTask.new('DBCEnums', 'server-code/DBCEnums.h',
			{:includedEnums=>['SpellCastTargetFlags', 'SpellFamily']}),
		GenLuaFromHeaderTask.new('movement', 'src/movement.h',
			{:includedEnums=>['MonsterMoveType']}),
		GenLuaFromHeaderTask.new('QuestDef', 'server-code/QuestDef.h',
			{:includedEnums=>['__QuestGiverStatus']}),
		GenLuaFromHeaderTask.new('ItemPrototype', 'server-code/ItemPrototype.h',
			{:includedEnums=>['InventoryType', 'ItemClass', 'ItemSubclassWeapon',
				'ItemModType',
				'ItemSubclassArmor']}),
		GenLuaFromHeaderTask.new('Player', 'server-code/Player.h',
			{:includedEnums=>['EquipmentSlots', 'InventorySlots', 'InventoryPackSlots',
				'BankItemSlots', 'BankBagSlots',
				'TradeSlots', 'TrainerSpellState', 'QuestSlotStateMask']}),
		GenLuaFromHeaderTask.new('Config', 'server-code/SharedDefines.h',
			{:includedEnums=>['Gender', 'Races', 'Classes'],
				:cutPrefix=>true}),
		GenLuaFromHeaderTask.new('LootMgr', 'server-code/LootMgr.h'),
		GenLuaFromHeaderTask.new('GossipDef', 'server-code/GossipDef.h',
			{:includedEnums=>['GossipOptionIcon']}),
		GenDbcTask.new(DBCs),
		GenLuaFromHeaderTask.new('SpellAuraDefines', 'server-code/SpellAuraDefines.h',
			{:includedEnums=>['AuraType', 'AuraConstants']}),
		GenLuaFromHeaderTask.new('worldHandlers', 'src/worldHandlers.h',
			{:includedEnums=>['RaidIcons']}),
	]
	@SPECIFIC_CFLAGS = {
		'worldPacketParsersLua.c' => ' -Wno-vla',
		'cDbc.cpp' => " -I#{CONFIG_WOWFOOT_DIR}/wowfoot-cpp/handlers"+
			" -I#{CONFIG_WOWFOOT_DIR}/wowfoot-cpp",
		'exception.cpp' => " -I#{CONFIG_WOWFOOT_DIR}/wowfoot-cpp",
		'stackTrace.cpp' => " -I#{CONFIG_WOWFOOT_DIR}/wowfoot-cpp",
		'process.cpp' => " -I#{CONFIG_WOWFOOT_DIR}/wowfoot-cpp -Wno-missing-format-attribute",
	}
	@SPECIFIC_CFLAGS['cDbcAux.cpp'] = @SPECIFIC_CFLAGS['cDbc.cpp'] +
		' -Ibuild/dbcSkillLineAbility -DWOWBOT=1'
	@SPECIFIC_CFLAGS['SkillLineAbility.index.cpp'] = @SPECIFIC_CFLAGS['cDbcAux.cpp']
	@EXTRA_INCLUDES = ['build', 'src', 'server-code', 'server-code/Auth',
		"#{CONFIG_WOWFOOT_DIR}/wowfoot-cpp/handlers/spell",
	]
	@EXTRA_OBJECTS = DBC_WORKS
	@LIBRARIES = ['crypto', 'z']
	if(HOST == :win32)
		@SOURCES << "#{CONFIG_WOWFOOT_DIR}/wowfoot-cpp/util/win32"
		@SOURCES << "#{CONFIG_WOWFOOT_DIR}/wowfoot-cpp/util/win32/sym_engine"
		@LIBRARIES += ['lua', 'wsock32', 'gdi32', 'imagehlp']
	elsif(HOST == :linux)
		@SOURCES << "#{CONFIG_WOWFOOT_DIR}/wowfoot-cpp/util/unix"
		@SOURCE_FILES << "#{CONFIG_WOWFOOT_DIR}/wowfoot-cpp/util/process.cpp"
		@EXTRA_CFLAGS = LUA_CFLAGS
		@EXTRA_CPPFLAGS = LUA_CFLAGS
		@EXTRA_LINKFLAGS = LUA_LINKFLAGS
		@LIBRARIES += ['rt']
		#@LIBRARIES = ['dl']
	else
		raise "Unsupported platform: #{HOST}"
	end
	@NAME = 'wowbot'
end

DirTask.new('state')

target :run do
	sh "#{work}"
end

target :gdb do
	sh "gdb --args #{work}"
end

target :mc do
	sh "valgrind --leak-check=full #{work}"
end

Works.run
